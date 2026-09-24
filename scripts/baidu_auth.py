#!/usr/bin/env python3
"""One-time Baidu Netdisk device login.

Reads BAIDU_APP_KEY and BAIDU_SECRET_KEY from the environment, prints a
user code, and stores the refresh token as GitHub secret BAIDU_REFRESH_TOKEN.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOKEN_URL = "https://openapi.baidu.com/oauth/2.0/token"
DEVICE_URL = "https://openapi.baidu.com/oauth/2.0/device/code"


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"缺少环境变量 {name}")
    return value


def get_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        # Baidu returns 400 while the user has not confirmed yet.
        body = error.read()
        if not body:
            raise SystemExit(f"百度接口 HTTP {error.code}") from error
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"百度接口返回了无法识别的内容: {payload!r}")
    return payload


def repo() -> str:
    result = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> None:
    query = urllib.parse.urlencode(
        {
            "response_type": "device_code",
            "client_id": env("BAIDU_APP_KEY"),
            "scope": "basic,netdisk",
        }
    )
    device = get_json(f"{DEVICE_URL}?{query}")
    if device.get("error"):
        raise SystemExit(f"申请设备码失败: {device}")

    user_code = device["user_code"]
    verification = device.get("verification_url") or "https://openapi.baidu.com/device"
    print("在浏览器打开这个地址，登录你的百度账号并授权：", flush=True)
    print(verification, flush=True)
    if device.get("qrcode_url"):
        print(device["qrcode_url"], flush=True)
    print(f"用户码: {user_code}", flush=True)

    deadline = time.time() + int(device.get("expires_in", 300))
    interval = max(int(device.get("interval", 5)), 5)
    device_code = device["device_code"]
    while time.time() < deadline:
        time.sleep(interval)
        poll = urllib.parse.urlencode(
            {
                "grant_type": "device_token",
                "code": device_code,
                "client_id": env("BAIDU_APP_KEY"),
                "client_secret": env("BAIDU_SECRET_KEY"),
            }
        )
        payload = get_json(f"{TOKEN_URL}?{poll}")
        if payload.get("refresh_token"):
            name = repo()
            subprocess.run(
                ["gh", "secret", "set", "BAIDU_REFRESH_TOKEN", "--repo", name],
                input=payload["refresh_token"].encode(),
                check=True,
            )
            print(f"授权成功，已写入 {name} 的 Secret：BAIDU_REFRESH_TOKEN", flush=True)
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
    raise SystemExit("授权超时。重新运行本脚本，并在 5 分钟内完成浏览器确认。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
