#!/usr/bin/env python3
"""Upload the latest GitHub Release disk image from this Mac.

Aliyun Drive uses the local aliyunpan login. Baidu Netdisk uses
~/.config/macpower/baidu.json and writes back a rotated refresh token.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "RyanStarFox/MacPower"
CONFIG = Path.home() / ".config" / "macpower"
STATE_PATH = CONFIG / "synced.json"
BAIDU_PATH = CONFIG / "baidu.json"
ALIYUNPAN = Path.home() / "bin" / "aliyunpan"
GH = Path("/opt/homebrew/bin/gh")
UPLOAD_BAIDU = Path(__file__).with_name("upload_baidu.py")
ALIYUN_DIR = "/软件/MacPower"


def run(args: list[str], env: dict | None = None) -> None:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    subprocess.run(args, check=True, env=merged)


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    path.chmod(0o600)


def latest_tag() -> str:
    result = subprocess.run(
        [str(GH), "release", "view", "--repo", REPO, "--json", "tagName"],
        check=True,
        capture_output=True,
        text=True,
    )
    tag = json.loads(result.stdout)["tagName"]
    if not tag.startswith("v"):
        raise SystemExit(f"无法识别的 release tag: {tag}")
    return tag


def download(tag: str, dest: Path) -> Path:
    run(
        [
            str(GH),
            "release",
            "download",
            tag,
            "--repo",
            REPO,
            "--pattern",
            "MacPower-*.dmg",
            "--dir",
            str(dest),
            "--clobber",
        ]
    )
    matches = list(dest.glob("MacPower-*.dmg"))
    if len(matches) != 1:
        raise SystemExit(f"期望 1 个 dmg，实际找到 {len(matches)}")
    return matches[0]


def upload_aliyun(dmg: Path) -> None:
    if not ALIYUNPAN.exists():
        raise SystemExit(f"找不到 {ALIYUNPAN}")
    run([str(ALIYUNPAN), "upload", "--np", "--skip", str(dmg), ALIYUN_DIR])


def upload_baidu(dmg: Path) -> None:
    config = load_json(BAIDU_PATH)
    refresh = str(config.get("refresh_token", "")).strip()
    app_key = str(config.get("app_key", "")).strip()
    secret = str(config.get("secret_key", "")).strip()
    app_name = str(config.get("app_name", "MacPower")).strip() or "MacPower"
    if not refresh or not app_key or not secret:
        print("跳过百度网盘：~/.config/macpower/baidu.json 里还没有可用的 refresh_token", flush=True)
        return
    token_file = CONFIG / "baidu_refresh_token"
    token_file.write_text(refresh + "\n", encoding="utf-8")
    token_file.chmod(0o600)
    before = refresh
    run(
        [sys.executable, str(UPLOAD_BAIDU), str(dmg)],
        {
            "BAIDU_APP_KEY": app_key,
            "BAIDU_SECRET_KEY": secret,
            "BAIDU_REFRESH_TOKEN": refresh,
            "BAIDU_APP_NAME": app_name,
            "BAIDU_TOKEN_FILE": str(token_file),
        },
    )
    updated = token_file.read_text(encoding="utf-8").strip()
    if updated and updated != before:
        config["refresh_token"] = updated
        save_json(BAIDU_PATH, config)
        print("百度 refresh token 已轮换并写回本机配置", flush=True)


def mark(state: dict, service: str, tag: str) -> None:
    state[service] = tag
    save_json(STATE_PATH, state)


def main() -> None:
    tag = latest_tag()
    state = load_json(STATE_PATH)
    need_aliyun = state.get("aliyun") != tag
    need_baidu = state.get("baidu") != tag
    if not need_aliyun and not need_baidu:
        print(f"{tag} 已同步", flush=True)
        return
    with tempfile.TemporaryDirectory(prefix="macpower-release-") as temp:
        dmg = download(tag, Path(temp))
        if need_aliyun:
            upload_aliyun(dmg)
            mark(state, "aliyun", tag)
            print(f"阿里云盘已上传 {dmg.name}", flush=True)
        if need_baidu:
            upload_baidu(dmg)
            if load_json(BAIDU_PATH).get("refresh_token"):
                mark(state, "baidu", tag)
                print(f"百度网盘已上传 {dmg.name}", flush=True)


if __name__ == "__main__":
    main()
