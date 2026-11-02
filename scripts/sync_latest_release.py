#!/usr/bin/env python3
"""Mirror the latest GitHub Release from this Mac.

Run this after publishing a GitHub Release. It is not scheduled.
Gitee uses the token in ~/.netrc. Aliyun Drive uses the local aliyunpan
login. Baidu Netdisk uses ~/.config/macpower/baidu.json and writes back a
rotated refresh token.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

REPO = "RyanStarFox/MacPower"
ROOT = Path(__file__).resolve().parent.parent
CONFIG = Path.home() / ".config" / "macpower"
STATE_PATH = CONFIG / "synced.json"
BAIDU_PATH = CONFIG / "baidu.json"
ALIYUNPAN = Path.home() / "bin" / "aliyunpan"
GH = Path("/opt/homebrew/bin/gh")
UPLOAD_BAIDU = Path(__file__).with_name("upload_baidu.py")
ALIYUN_DIR = "/软件/MacPower"
GITEE_API = "https://gitee.com/api/v5/repos/Ryan_LS_Wang/MacPower"
GITEE_REMOTE = "gitee"


def run(args: list[str], env: dict | None = None, cwd: Path | None = None) -> None:
    merged = os.environ.copy()
    merged.setdefault("GIT_TERMINAL_PROMPT", "0")
    if env:
        merged.update(env)
    subprocess.run(args, check=True, env=merged, cwd=cwd)


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


def github_asset_names(tag: str) -> list[str]:
    result = subprocess.run(
        [str(GH), "release", "view", tag, "--repo", REPO, "--json", "assets"],
        check=True,
        capture_output=True,
        text=True,
    )
    assets = json.loads(result.stdout).get("assets") or []
    return [str(item.get("name", "")) for item in assets]


def download_asset(tag: str, name: str, dest: Path) -> Path:
    run(
        [
            str(GH),
            "release",
            "download",
            tag,
            "--repo",
            REPO,
            "--pattern",
            name,
            "--dir",
            str(dest),
            "--clobber",
        ]
    )
    path = dest / name
    if not path.exists():
        raise SystemExit(f"没有下载到 {name}")
    return path


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
        print("跳过百度网盘：还没有可用的 refresh token。", flush=True)
        print("运行 python3 scripts/set_baidu_refresh_token.py", flush=True)
        print("它会打印授权网址和用户码。打开该网址，登录百度并输入用户码即可。", flush=True)
        return
    token_file = CONFIG / "baidu_refresh_token"
    token_file.write_text(refresh + "\n", encoding="utf-8")
    token_file.chmod(0o600)
    before = refresh
    try:
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
    finally:
        updated = token_file.read_text(encoding="utf-8").strip()
        if updated and updated != before:
            config["refresh_token"] = updated
            save_json(BAIDU_PATH, config)
            print("百度 refresh token 已轮换并写回本机配置", flush=True)


def gitee_token() -> str:
    netrc = Path.home() / ".netrc"
    if not netrc.exists():
        raise SystemExit("找不到 ~/.netrc。请写入 machine gitee.com 的私人令牌，不要把令牌放进仓库。")
    lines = netrc.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if line.strip() != "machine gitee.com":
            continue
        for extra in lines[index + 1 :]:
            if extra.startswith("machine "):
                break
            if extra.startswith("password "):
                token = extra.split(" ", 1)[1].strip()
                if token:
                    return token
    raise SystemExit("~/.netrc 里没有 machine gitee.com 的 password。")


def gitee_json(method: str, url: str, data: bytes | None = None, headers: dict | None = None) -> dict:
    request = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            body = response.read()
            return json.loads(body.decode("utf-8")) if body else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        safe_url = url.split("?", 1)[0]
        if error.code == 404:
            raise FileNotFoundError(safe_url)
        raise SystemExit(f"Gitee 接口失败 HTTP {error.code} {method} {safe_url}\n{detail[:600]}") from error


def gitee_release(token: str, tag: str) -> dict | None:
    query = urllib.parse.urlencode({"access_token": token})
    url = f"{GITEE_API}/releases/tags/{urllib.parse.quote(tag, safe='')}?{query}"
    try:
        return gitee_json("GET", url)
    except FileNotFoundError:
        return None


def push_gitee(tag: str) -> None:
    probe = subprocess.run(
        ["git", "remote", "get-url", GITEE_REMOTE],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if probe.returncode != 0:
        raise SystemExit("这个仓库没有名为 gitee 的远程。")
    run(["git", "fetch", "origin", "main"], cwd=ROOT)
    run(["git", "push", GITEE_REMOTE, "origin/main:main"], cwd=ROOT)
    run(["git", "fetch", "origin", "tag", tag], cwd=ROOT)
    run(["git", "push", GITEE_REMOTE, f"refs/tags/{tag}"], cwd=ROOT)
    print(f"Gitee 已推送 main 和 {tag}", flush=True)


def upload_gitee(tag: str, dmg: Path) -> None:
    token = gitee_token()
    release = gitee_release(token, tag)
    if release is None:
        meta = subprocess.run(
            [str(GH), "release", "view", tag, "--repo", REPO, "--json", "name,body,isPrerelease"],
            check=True,
            capture_output=True,
            text=True,
        )
        info = json.loads(meta.stdout)
        fields = urllib.parse.urlencode(
            {
                "access_token": token,
                "tag_name": tag,
                "name": info.get("name") or tag,
                "body": info.get("body") or "",
                "target_commitish": "main",
                "prerelease": "true" if info.get("isPrerelease") else "false",
            }
        ).encode()
        release = gitee_json("POST", f"{GITEE_API}/releases", fields)
        print(f"Gitee 已创建发行版 {tag}", flush=True)
    names = [item.get("name", "") for item in release.get("assets") or []]
    if dmg.name in names:
        print(f"Gitee 发行版已有 {dmg.name}", flush=True)
        return
    boundary = f"----MacPowerGitee{uuid.uuid4().hex}"
    payload = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{dmg.name}"\r\n'.encode(),
            b"Content-Type: application/octet-stream\r\n\r\n",
            dmg.read_bytes(),
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    query = urllib.parse.urlencode({"access_token": token})
    gitee_json(
        "POST",
        f"{GITEE_API}/releases/{release['id']}/attach_files?{query}",
        payload,
        {"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    print(f"Gitee 已上传 {dmg.name}", flush=True)


def mark(state: dict, service: str, tag: str) -> None:
    state[service] = tag
    save_json(STATE_PATH, state)


def main() -> None:
    tag = latest_tag()
    state = load_json(STATE_PATH)
    need_gitee = state.get("gitee") != tag
    need_aliyun = state.get("aliyun") != tag
    need_baidu = state.get("baidu") != tag
    if not need_gitee and not need_aliyun and not need_baidu:
        print(f"{tag} 已同步", flush=True)
        return
    if need_gitee:
        push_gitee(tag)
    token = gitee_token() if need_gitee else ""
    release = gitee_release(token, tag) if need_gitee else None
    names = [item.get("name", "") for item in (release or {}).get("assets") or []]
    wanted = [
        name
        for name in github_asset_names(tag)
        if name.startswith("MacPower-") and name.endswith((".dmg", ".zip"))
    ]
    if not any(name.endswith(".dmg") for name in wanted):
        raise SystemExit(f"{tag} 没有 MacPower dmg")
    missing_on_gitee = [name for name in wanted if name not in names]
    if need_gitee and not missing_on_gitee and not need_aliyun and not need_baidu:
        mark(state, "gitee", tag)
        print(f"Gitee 发行版已有 {', '.join(wanted)}", flush=True)
        return
    with tempfile.TemporaryDirectory(prefix="macpower-release-") as temp:
        files = [download_asset(tag, name, Path(temp)) for name in wanted]
        if need_gitee:
            for path in files:
                upload_gitee(tag, path)
            mark(state, "gitee", tag)
        if need_aliyun:
            for path in files:
                upload_aliyun(path)
                print(f"阿里云盘已上传 {path.name}", flush=True)
            mark(state, "aliyun", tag)
        if need_baidu:
            for path in files:
                upload_baidu(path)
                print(f"百度网盘已上传 {path.name}", flush=True)
            if load_json(BAIDU_PATH).get("refresh_token"):
                mark(state, "baidu", tag)


if __name__ == "__main__":
    main()
