#!/usr/bin/env python3
"""Upload a file into this Baidu Netdisk app's sandbox directory.

Requires BAIDU_APP_KEY, BAIDU_SECRET_KEY, BAIDU_REFRESH_TOKEN, and
BAIDU_APP_NAME. Files land in /apps/<BAIDU_APP_NAME>/releases/.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CHUNK_SIZE = 4 * 1024 * 1024
TOKEN_URL = "https://openapi.baidu.com/oauth/2.0/token"
FILE_URL = "https://pan.baidu.com/rest/2.0/xpan/file"
UPLOAD_URL = "https://d.pcs.baidu.com/rest/2.0/pcs/superfile2"


def env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"缺少环境变量 {name}")
    return value


def mask(secret: str) -> None:
    if os.environ.get("GITHUB_ACTIONS") and secret:
        print(f"::add-mask::{secret}", flush=True)


def request(method: str, url: str, data: bytes | None = None, headers: dict | None = None) -> dict:
    last_error: Exception | None = None
    for attempt in range(1, 4):
        req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
        try:
            with urllib.request.urlopen(req, timeout=180) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")
            raise SystemExit(f"百度接口 HTTP {error.code}: {detail[:500]}") from error
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = error
            print(f"连接中断，5 秒后重试（第 {attempt} 次）", flush=True)
            time.sleep(5)
            continue
        if not body:
            return {}
        payload = json.loads(body.decode("utf-8"))
        if isinstance(payload, dict) and payload.get("errno") not in (None, 0):
            raise SystemExit(f"百度接口失败 errno={payload.get('errno')} {payload}")
        return payload
    raise SystemExit(f"连接百度失败: {last_error}")


def refresh_access_token() -> str:
    query = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": env("BAIDU_REFRESH_TOKEN"),
            "client_id": env("BAIDU_APP_KEY"),
            "client_secret": env("BAIDU_SECRET_KEY"),
        }
    )
    url = f"{TOKEN_URL}?{query}"
    delay = 20
    last_detail = ""
    for attempt in range(1, 9):
        req = urllib.request.Request(url)
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            last_detail = error.read().decode("utf-8", "replace")
            if "security policy" in last_detail.lower() or "try again later" in last_detail.lower():
                print(f"百度限制了令牌刷新，{delay} 秒后重试（第 {attempt} 次）", flush=True)
                time.sleep(delay)
                delay = min(delay * 2, 120)
                continue
            raise SystemExit(f"刷新 access_token 失败: HTTP {error.code}: {last_detail[:500]}") from error
        if payload.get("error"):
            raise SystemExit(
                f"刷新 access_token 失败: {payload.get('error')} {payload.get('error_description', '')}"
            )
        token = payload.get("access_token", "")
        mask(token)
        if not token:
            raise SystemExit("刷新 access_token 失败：响应里没有 access_token")
        return token
    raise SystemExit(f"刷新 access_token 多次被百度风控拦截: {last_detail[:500]}")


def block_md5s(path: str) -> list[str]:
    digests: list[str] = []
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(CHUNK_SIZE)
            if not chunk:
                break
            digests.append(hashlib.md5(chunk).hexdigest())
    if not digests:
        digests.append(hashlib.md5(b"").hexdigest())
    return digests


def remote_path(filename: str) -> str:
    app_name = env("BAIDU_APP_NAME").strip("/")
    if "/" in app_name:
        raise SystemExit("BAIDU_APP_NAME 不能包含 /，填开放平台控制台里的应用名称")
    return f"/apps/{app_name}/releases/{filename}"


def ensure_dir(token: str, path: str) -> None:
    body = urllib.parse.urlencode(
        {"path": path, "size": "0", "isdir": "1", "rtype": "1"}
    ).encode()
    url = f"{FILE_URL}?method=create&access_token={urllib.parse.quote(token)}"
    req = urllib.request.Request(url, data=body, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise SystemExit(f"创建目录失败 HTTP {error.code}") from error
    errno = payload.get("errno")
    # -8 / 31061: directory already exists.
    if errno not in (0, -8, 31061):
        raise SystemExit(f"创建目录失败 {path}: {payload}")


def precreate(token: str, path: str, size: int, blocks: list[str]) -> tuple[str, list[int]]:
    body = urllib.parse.urlencode(
        {
            "path": path,
            "size": str(size),
            "isdir": "0",
            "autoinit": "1",
            "rtype": "3",
            "block_list": json.dumps(blocks),
        }
    ).encode()
    url = f"{FILE_URL}?method=precreate&access_token={urllib.parse.quote(token)}"
    payload = request("POST", url, body)
    upload_id = payload.get("uploadid", "")
    if not upload_id:
        raise SystemExit(f"预上传没有返回 uploadid: {payload}")
    pending = payload.get("block_list")
    if not isinstance(pending, list):
        pending = list(range(len(blocks)))
    return upload_id, [int(item) for item in pending]


def upload_part(token: str, path: str, upload_id: str, index: int, chunk: bytes) -> None:
    boundary = "----MacPowerBaiduUpload"
    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="file"; filename="chunk"\r\n',
            b"Content-Type: application/octet-stream\r\n\r\n",
            chunk,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    query = urllib.parse.urlencode(
        {
            "method": "upload",
            "access_token": token,
            "type": "tmpfile",
            "path": path,
            "uploadid": upload_id,
            "partseq": str(index),
        }
    )
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    last_error = ""
    for attempt in range(1, 4):
        try:
            request("POST", f"{UPLOAD_URL}?{query}", body, headers)
            return
        except SystemExit as error:
            last_error = str(error)
            print(f"分片 {index} 第 {attempt} 次失败，15 秒后重试", flush=True)
            time.sleep(15)
    raise SystemExit(last_error)


def create_file(token: str, path: str, size: int, upload_id: str, blocks: list[str]) -> None:
    body = urllib.parse.urlencode(
        {
            "path": path,
            "size": str(size),
            "isdir": "0",
            "rtype": "3",
            "uploadid": upload_id,
            "block_list": json.dumps(blocks),
        }
    ).encode()
    url = f"{FILE_URL}?method=create&access_token={urllib.parse.quote(token)}"
    request("POST", url, body)


def upload(local_path: str, token: str) -> None:
    app_root = f"/apps/{env('BAIDU_APP_NAME').strip('/')}"
    ensure_dir(token, app_root)
    ensure_dir(token, f"{app_root}/releases")

    filename = os.path.basename(local_path)
    path = remote_path(filename)
    size = os.path.getsize(local_path)
    blocks = block_md5s(local_path)
    print(f"上传 {filename} ({size} bytes) -> {path}", flush=True)
    upload_id, pending = precreate(token, path, size, blocks)
    with open(local_path, "rb") as handle:
        for index in pending:
            handle.seek(index * CHUNK_SIZE)
            chunk = handle.read(CHUNK_SIZE)
            upload_part(token, path, upload_id, index, chunk)
            print(f"分片 {index + 1}/{len(blocks)} 完成", flush=True)
    create_file(token, path, size, upload_id, blocks)
    print(f"已上传到 {path}", flush=True)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("用法: upload_baidu.py <file> [file...]")
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            raise SystemExit(f"找不到文件: {path}")
    token = refresh_access_token()
    for path in sys.argv[1:]:
        upload(path, token)


if __name__ == "__main__":
    main()
