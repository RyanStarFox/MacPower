#!/usr/bin/env python3
"""Authorize Baidu Netdisk in the browser and store the refresh token locally.

Prints the verification URL and user code on every run. The token is written
to ~/.config/macpower/baidu.json, not to GitHub.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PATH = Path.home() / ".config" / "macpower" / "baidu.json"
TOKEN_URL = "https://openapi.baidu.com/oauth/2.0/token"
DEVICE_URL = "https://openapi.baidu.com/oauth/2.0/device/code"


def get_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        # Baidu returns HTTP 400 while the browser confirmation is still pending.
        body = error.read()
        if not body:
            raise SystemExit(f"百度接口 HTTP {error.code}") from error
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"百度接口返回了无法识别的内容: {payload!r}")
    return payload


def main() -> None:
    if not PATH.exists():
        raise SystemExit(f"找不到 {PATH}")
    data = json.loads(PATH.read_text(encoding="utf-8"))
    app_key = str(data.get("app_key", "")).strip()
    secret = str(data.get("secret_key", "")).strip()
    if not app_key or not secret:
        raise SystemExit(f"{PATH} 里缺少 app_key 或 secret_key")

    query = urllib.parse.urlencode(
        {
            "response_type": "device_code",
            "client_id": app_key,
            "scope": "basic,netdisk",
        }
    )
    device = get_json(f"{DEVICE_URL}?{query}")
    if device.get("error"):
        raise SystemExit(f"申请设备码失败: {device}")

    user_code = device["user_code"]
    verification = device.get("verification_url") or "https://openapi.baidu.com/device"
    expires = int(device.get("expires_in", 300))
    print("获取百度 refresh token：", flush=True)
    print(f"1. 在浏览器打开：{verification}", flush=True)
    if device.get("qrcode_url"):
        print(f"   或打开二维码：{device['qrcode_url']}", flush=True)
    print("2. 登录你的百度账号。", flush=True)
    print(f"3. 输入用户码：{user_code}", flush=True)
    print(f"4. 确认授权。请在 {max(expires // 60, 1)} 分钟内完成。", flush=True)

    deadline = time.time() + expires
    interval = max(int(device.get("interval", 5)), 5)
    device_code = device["device_code"]
    while time.time() < deadline:
        time.sleep(interval)
        poll = urllib.parse.urlencode(
            {
                "grant_type": "device_token",
                "code": device_code,
                "client_id": app_key,
                "client_secret": secret,
            }
        )
        payload = get_json(f"{TOKEN_URL}?{poll}")
        token = str(payload.get("refresh_token", "")).strip()
        if token:
            data["refresh_token"] = token
            PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            PATH.chmod(0o600)
            print("授权成功，refresh token 已写入 ~/.config/macpower/baidu.json", flush=True)
            return
        error = payload.get("error", "")
        if error == "authorization_pending":
            print("等待浏览器授权…", flush=True)
            continue
        if error == "slow_down":
            interval += 5
            print("授权轮询过快，已放慢重试。", flush=True)
            continue
        raise SystemExit(f"授权失败: {payload}")
    raise SystemExit("授权超时。重新运行本脚本，并在提示的时间内完成浏览器确认。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
