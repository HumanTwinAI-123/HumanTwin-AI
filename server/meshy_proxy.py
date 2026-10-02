#!/usr/bin/env python3
"""HumanTwin AI local generation proxy (Python 3 standard library only).

The Flutter app talks only to this loopback proxy.

* ``--upstream fake`` (default) simulates a generation task and serves the
  bundled sample GLB. The sample model is NOT reconstructed from the photos.
* ``--upstream meshy`` (opt-in) forwards to Meshy's Multi-Image-to-3D API.
  The key is read from this process's ``MESHY_API_KEY`` environment variable
  only; it never reaches the app, responses, or logs.

Creating a Meshy task costs credits, so this proxy allows at most ONE upstream
creation per ordered photo set. Any ambiguous creation outcome (timeout, reset,
5xx, malformed reply, crash mid-request) is stored as ``submission_unknown``
and is never re-submitted automatically; an operator must check the Meshy
dashboard and delete that row from the SQLite DB by hand to allow a retry.

Records are scoped per upstream: each fake scenario has its own scope, and a
Meshy scope names its endpoint, so QA runs never leak into the default demo or
into the real API. Downloaded Meshy models are cached beside the DB
(``models/``) so retries never download a model twice.

Run ``python3 server/meshy_proxy.py --help`` for options.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import http.client
import json
import logging
import os
import re
import socket
import socketserver
import sqlite3
import ssl
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SAMPLE_GLB = REPO_ROOT / "assets" / "models" / "human_demo.glb"
DEFAULT_DB = REPO_ROOT / "server" / ".data" / "generation_tasks.sqlite3"
DEFAULT_MESHY_BASE = "https://api.meshy.ai"
MESHY_PATH = "/openapi/v1/multi-image-to-3d"
LOOPBACK_HOSTS = ("127.0.0.1", "::1", "localhost")

MAX_BODY_BYTES = 36 * 1024 * 1024
MAX_IMAGE_BYTES = 10 * 1024 * 1024
MAX_IMAGE_B64 = 4 * ((MAX_IMAGE_BYTES + 2) // 3)
MAX_MODEL_BYTES = 64 * 1024 * 1024
MAX_API_REPLY_BYTES = 1024 * 1024
TASK_ID_RE = re.compile(r"[A-Za-z0-9_-]{1,128}")
STATUSES = ("PENDING", "IN_PROGRESS", "SUCCEEDED", "FAILED", "CANCELED")
TERMINAL = ("SUCCEEDED", "FAILED", "CANCELED")
PHOTO_TYPES = {
    "data:image/jpeg;base64": b"\xff\xd8\xff",
    "data:image/png;base64": b"\x89PNG\r\n\x1a\n",
}

LOG = logging.getLogger("meshy_proxy")

# code -> (retryable, short controlled message shown to the user)
ERRORS = {
    "forbidden": (False, "不接受来自浏览器页面的请求。"),
    "not_found": (False, "接口不存在。"),
    "method_not_allowed": (False, "不支持该请求方法。"),
    "length_required": (False, "请求缺少内容长度。"),
    "unsupported_media_type": (False, "请求内容必须是 JSON。"),
    "payload_too_large": (False, "照片数据过大。"),
    "invalid_request": (False, "请求内容无法解析。"),
    "invalid_photos": (False, "照片无效，请重新选择正面、侧面和背面照片。"),
    "photos_rejected": (False, "生成服务无法处理这组照片。"),
    "service_auth": (False, "生成服务认证失败，请检查代理配置。"),
    "service_quota": (False, "生成服务额度不足。"),
    "service_busy": (True, "生成服务繁忙，请稍后重试。"),
    "service_unavailable": (True, "暂时无法连接生成服务，请稍后重试。"),
    "submission_unknown": (False, "提交结果未知。为避免重复扣费，不会自动重新提交。"),
    "task_not_found": (False, "未找到该生成任务。"),
    "upstream_invalid": (True, "生成服务返回了无法识别的数据。"),
    "upstream_error": (False, "生成服务无法提供该任务。"),
    "model_not_ready": (True, "模型尚未生成完成。"),
    "model_invalid": (False, "模型文件无效。"),
    "internal_error": (False, "代理服务内部错误。"),
}


class ApiError(Exception):
    """An error answered to the app with a controlled JSON body."""

    def __init__(self, status, code, retry_after=None, allow=None):
        super().__init__(code)
        self.status, self.code = status, code
        self.retry_after, self.allow = retry_after, allow


class UpstreamError(Exception):
    """Upstream failure without any upstream text attached.

    kind: "http" (status set), "unreachable" (nothing was sent),
    "network" (timeout/reset; the outcome is unknown), "invalid" (bad reply).
    """

    def __init__(self, kind, status=None, retry_after=None):
        super().__init__(kind)
        self.kind, self.status, self.retry_after = kind, status, retry_after


def input_hash(images):
    """sha256 over (8-byte big-endian length + raw bytes) for each image in order."""
    digest = hashlib.sha256()
    for raw in images:
        digest.update(len(raw).to_bytes(8, "big"))
        digest.update(raw)
    return digest.hexdigest()


def decode_photo(value):
    """Return the raw bytes of a valid JPEG/PNG data URI, else None."""
    if not isinstance(value, str):
        return None
    header, sep, payload = value.partition(",")
    magic = PHOTO_TYPES.get(header)
    if not sep or magic is None or len(payload) > MAX_IMAGE_B64:
        return None
    try:
        raw = base64.b64decode(payload, validate=True)
    except (binascii.Error, ValueError):
        return None
    if not raw or len(raw) > MAX_IMAGE_BYTES or not raw.startswith(magic):
        return None
    return raw


def ascii_int(value, max_digits=15):
    """Parse an ASCII decimal header value; None if absent or malformed.

    str.isdigit()/\\d also accept non-ASCII digits (e.g. latin-1 "²") that int()
    then rejects, so only [0-9] is accepted here.
    """
    value = (value or "").strip()
    if not re.fullmatch(r"[0-9]{1,%d}" % max_digits, value):
        return None
    return int(value)


def parse_retry_after(value):
    seconds = ascii_int(value, 4)
    return seconds if seconds is not None and 1 <= seconds <= 600 else None


def glb_length(data):
    """Total length declared by a binary glTF 2.0 header, or None if not GLB 2.0."""
    if len(data) < 12 or bytes(data[:4]) != b"glTF" or int.from_bytes(data[4:8], "little") != 2:
        return None
    return int.from_bytes(data[8:12], "little")


def write_atomic(path, data):
    """Best-effort atomic file write; a cache failure never fails a request."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".part")
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(data)
                out.flush()
                os.fsync(out.fileno())
            os.replace(tmp, path)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
    except OSError as err:
        LOG.warning("model cache write failed: %s", type(err).__name__)


def is_loopback_http(url):
    parts = urllib.parse.urlsplit(url)
    return parts.scheme == "http" and parts.hostname in LOOPBACK_HOSTS


# --------------------------------------------------------------------------- store


class TaskStore:
    """SQLite record of every creation attempt, keyed by (upstream scope, input_hash).

    The ``upstream`` column holds the upstream's ``scope`` (see the upstream classes).
    """

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS generations (
        upstream TEXT NOT NULL,
        input_hash TEXT NOT NULL,
        state TEXT NOT NULL,   -- creating | created | submission_unknown
        task_id TEXT,
        status TEXT,
        progress INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        PRIMARY KEY (upstream, input_hash)
    );
    CREATE UNIQUE INDEX IF NOT EXISTS generations_task
        ON generations (upstream, task_id) WHERE task_id IS NOT NULL;
    """

    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        # Autocommit: every statement is durable before the next step runs.
        self._db = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._db.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        self._run_script(self.SCHEMA)
        # A row still "creating" means the process died mid-create: outcome unknown.
        self._write(
            "UPDATE generations SET state='submission_unknown', updated_at=? WHERE state='creating'",
            (time.time(),),
        )

    def _run_script(self, script):
        with self._lock:
            self._db.executescript(script)

    def _write(self, sql, args):
        with self._lock:
            self._db.execute(sql, args)

    def _one(self, sql, args):
        with self._lock:
            row = self._db.execute(sql, args).fetchone()
        return dict(row) if row else None

    def by_hash(self, mode, digest):
        return self._one("SELECT * FROM generations WHERE upstream=? AND input_hash=?", (mode, digest))

    def by_task(self, mode, task_id):
        return self._one("SELECT * FROM generations WHERE upstream=? AND task_id=?", (mode, task_id))

    def insert_creating(self, mode, digest):
        now = time.time()
        self._write(
            "INSERT INTO generations (upstream, input_hash, state, progress, created_at, updated_at)"
            " VALUES (?, ?, 'creating', 0, ?, ?)",
            (mode, digest, now, now),
        )

    def mark_created(self, mode, digest, task_id):
        now = time.time()
        self._write(
            "UPDATE generations SET state='created', task_id=?, status='PENDING', progress=0,"
            " created_at=?, updated_at=? WHERE upstream=? AND input_hash=?",
            (task_id, now, now, mode, digest),
        )

    def mark_unknown(self, mode, digest):
        self._write(
            "UPDATE generations SET state='submission_unknown', updated_at=?"
            " WHERE upstream=? AND input_hash=? AND task_id IS NULL",
            (time.time(), mode, digest),
        )

    def delete_uncreated(self, mode, digest):
        self._write(
            "DELETE FROM generations WHERE upstream=? AND input_hash=? AND task_id IS NULL",
            (mode, digest),
        )

    def update_status(self, mode, task_id, status, progress):
        self._write(
            "UPDATE generations SET status=?, progress=?, updated_at=? WHERE upstream=? AND task_id=?",
            (status, progress, time.time(), mode, task_id),
        )

    def close(self):
        with self._lock:
            self._db.close()


# ------------------------------------------------------------------------ upstreams


class FakeUpstream:
    """Simulated task that always yields the bundled sample GLB (not the photos)."""

    mode = "fake"
    simulated = True
    poll_after_ms = 1000
    SCENARIOS = ("ok", "task-failed", "lost-create-response", "upstream-unknown", "flaky-poll")

    def __init__(self, duration=6.0, scenario="ok", sample_path=SAMPLE_GLB):
        if scenario not in self.SCENARIOS:
            raise ValueError("unknown fake scenario")
        self.duration = max(0.0, float(duration))
        self.scenario = scenario
        # Storage scope: failure-scenario QA must never leak into the default "ok" demo.
        self.scope = "fake" if scenario == "ok" else "fake:" + scenario
        self.drop_create_response = scenario == "lost-create-response"
        self.sample = Path(sample_path).read_bytes()
        if not self.sample.startswith(b"glTF"):
            raise ValueError("sample model is not a binary glTF file")
        self._polls = 0
        self._lock = threading.Lock()

    def create(self, images):
        if self.scenario == "upstream-unknown":
            raise UpstreamError("network")  # behaves like a create timeout
        return "fake-" + uuid.uuid4().hex

    def get(self, record):
        if self.scenario == "flaky-poll":
            with self._lock:
                self._polls += 1
                flaky = self._polls % 2 == 1
            if flaky:
                raise UpstreamError("network", retry_after=1)
        elapsed = time.time() - record["created_at"]
        if elapsed >= self.duration:
            if self.scenario == "task-failed":
                return {"status": "FAILED", "progress": 0}
            return {"status": "SUCCEEDED", "progress": 100}
        pending = min(1.0, self.duration / 4)
        if elapsed < pending:
            return {"status": "PENDING", "progress": 0}
        share = (elapsed - pending) / max(self.duration - pending, 1e-6)
        return {"status": "IN_PROGRESS", "progress": max(1, min(99, int(99 * share)))}

    def fetch_model(self, record):
        return self.sample


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """API calls never follow redirects (the Authorization header must not travel)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class _SafeRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, allowed):
        super().__init__()
        self._allowed = allowed

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not self._allowed(newurl):
            fp.close()
            raise UpstreamError("invalid")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _network_kind(reason):
    # Only failures that certainly happen before any request byte is sent.
    if isinstance(reason, (ConnectionRefusedError, socket.gaierror, ssl.SSLCertVerificationError)):
        return "unreachable"
    return "network"


class MeshyUpstream:
    """Meshy Multi-Image-to-3D (https://docs.meshy.ai/en/api/multi-image-to-3d)."""

    mode = "meshy"
    simulated = False
    poll_after_ms = 5000
    drop_create_response = False

    def __init__(self, api_key, base_url=DEFAULT_MESHY_BASE, *, create_timeout=60.0,
                 get_timeout=20.0, download_timeout=60.0, allow_insecure_loopback=False,
                 max_model_bytes=MAX_MODEL_BYTES):
        if not api_key:
            raise ValueError("missing API key")
        self._key = api_key
        self.allow_insecure_loopback = allow_insecure_loopback
        parts = urllib.parse.urlsplit(base_url)
        if not (parts.scheme == "https" and parts.hostname) and not (
                allow_insecure_loopback and is_loopback_http(base_url)):
            raise ValueError("Meshy base URL must be https")
        self._endpoint = base_url.rstrip("/") + MESHY_PATH
        # Storage scope names the endpoint (never userinfo, path or key), so records
        # made against a local test server are never reused against the real API.
        host = f"[{parts.hostname}]" if ":" in parts.hostname else parts.hostname
        origin = f"{parts.scheme}://{host}:{parts.port or (443 if parts.scheme == 'https' else 80)}"
        self.scope = "meshy" if origin == "https://api.meshy.ai:443" else "meshy@" + origin
        self.create_timeout, self.get_timeout = create_timeout, get_timeout
        self.download_timeout, self.max_model_bytes = download_timeout, max_model_bytes
        # Tests on 127.0.0.1 must not be routed through environment proxies.
        extra = [urllib.request.ProxyHandler({})] if allow_insecure_loopback else []
        self._api = urllib.request.build_opener(*extra, _NoRedirect())
        self._download = urllib.request.build_opener(*extra, _SafeRedirect(self._model_url_ok))

    def _model_url_ok(self, url):
        parts = urllib.parse.urlsplit(url)
        if parts.scheme == "https" and parts.hostname:
            return True
        return self.allow_insecure_loopback and parts.scheme == "http" and parts.hostname == "127.0.0.1"

    def _call(self, method, url, payload, timeout):
        headers = {"Authorization": "Bearer " + self._key, "Accept": "application/json"}
        data = None
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self._api.open(request, timeout=timeout) as resp:
                status = resp.status
                raw = resp.read(MAX_API_REPLY_BYTES + 1)
        except urllib.error.HTTPError as err:
            retry_after = parse_retry_after(err.headers.get("Retry-After") if err.headers else None)
            err.close()
            raise UpstreamError("http", status=err.code, retry_after=retry_after) from None
        except urllib.error.URLError as err:
            raise UpstreamError(_network_kind(err.reason)) from None
        except (OSError, http.client.HTTPException):
            raise UpstreamError("network") from None
        if status not in (200, 201, 202):
            raise UpstreamError("http", status=status)
        try:
            if len(raw) > MAX_API_REPLY_BYTES:
                raise ValueError
            doc = json.loads(raw)
        except (ValueError, RecursionError):
            raise UpstreamError("invalid") from None
        if not isinstance(doc, dict):
            raise UpstreamError("invalid")
        return doc

    def _task_url(self, task_id):
        return self._endpoint + "/" + urllib.parse.quote(task_id, safe="")

    def create(self, images):
        payload = {
            "image_urls": list(images),  # front, side, back data URIs, in order
            "ai_model": "meshy-7.1",
            "geometry_resolution": "standard",
            "should_texture": True,
            "should_remesh": True,
            "target_polycount": 30000,
            "target_formats": ["glb"],
        }
        doc = self._call("POST", self._endpoint, payload, self.create_timeout)
        task_id = doc.get("result")
        if not isinstance(task_id, str) or not TASK_ID_RE.fullmatch(task_id):
            raise UpstreamError("invalid")
        return task_id

    def get(self, record):
        doc = self._call("GET", self._task_url(record["task_id"]), None, self.get_timeout)
        return {"status": doc.get("status"), "progress": doc.get("progress", 0)}

    def fetch_model(self, record):
        doc = self._call("GET", self._task_url(record["task_id"]), None, self.get_timeout)
        urls = doc.get("model_urls")
        url = urls.get("glb") if isinstance(urls, dict) else None
        if not isinstance(url, str) or not self._model_url_ok(url):
            raise UpstreamError("invalid")
        return self._download_model(url)

    def _download_model(self, url):
        request = urllib.request.Request(url, headers={"Accept": "model/gltf-binary, */*"})
        deadline = time.monotonic() + self.download_timeout
        data = bytearray()
        try:
            with self._download.open(request, timeout=self.download_timeout) as resp:
                if resp.status != 200:
                    raise UpstreamError("network")
                declared = ascii_int(resp.headers.get("Content-Length"))
                if declared is not None and declared > self.max_model_bytes:
                    raise UpstreamError("invalid")
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise UpstreamError("network")  # total deadline, even for a trickle
                    _set_read_timeout(resp, remaining)
                    # read1: at most one recv, so the deadline is checked after every packet.
                    chunk = resp.read1(min(1 << 16, self.max_model_bytes + 1 - len(data)))
                    if not chunk:
                        break
                    data += chunk
                    if len(data) > self.max_model_bytes:
                        raise UpstreamError("invalid")
        except urllib.error.HTTPError as err:
            err.close()
            raise UpstreamError("invalid" if 300 <= err.code < 400 else "network") from None
        except urllib.error.URLError:
            raise UpstreamError("network") from None
        except (OSError, http.client.HTTPException):
            raise UpstreamError("network") from None
        # http.client returns short (no IncompleteRead) when the peer closes early.
        if declared is not None and len(data) != declared:
            raise UpstreamError("network")  # dropped mid-transfer: transient
        total = glb_length(data)
        if declared is None and total is not None and total > len(data):
            raise UpstreamError("network")  # close-delimited body cut short
        if total != len(data):
            raise UpstreamError("invalid")
        return bytes(data)


def _set_read_timeout(resp, seconds):
    """Best effort: bound the next recv by the remaining download deadline.

    HTTPResponse has no public socket accessor; if this lookup ever fails, each
    recv is still bounded by the open() timeout and the deadline check above.
    """
    sock = getattr(getattr(resp.fp, "raw", None), "_sock", None)
    if sock is not None:
        sock.settimeout(max(0.01, seconds))


# --------------------------------------------------------------------- HTTP server

ROUTE_METHODS = {"health": "GET", "create": "POST", "task": "GET", "model": "GET"}
ROUTE_LABELS = {
    "health": "/v1/health",
    "create": "/v1/generations",
    "task": "/v1/generations/{id}",
    "model": "/v1/generations/{id}/model.glb",
}
_TASK_PATH_RE = re.compile(r"/v1/generations/([^/]+)(/model\.glb)?")


def match_route(path):
    if path == "/v1/health":
        return "health", None
    if path == "/v1/generations":
        return "create", None
    found = _TASK_PATH_RE.fullmatch(path)
    if found:
        return ("model" if found.group(2) else "task"), urllib.parse.unquote(found.group(1))
    raise ApiError(404, "not_found")


def create_error(err):
    """Map a DEFINITIVE creation failure to an ApiError; None means ambiguous."""
    if err.kind == "unreachable":
        return ApiError(503, "service_unavailable", retry_after=5)
    if err.kind == "http":
        if err.status in (400, 422):
            return ApiError(422, "photos_rejected")
        if err.status in (401, 403):
            return ApiError(502, "service_auth")
        if err.status == 402:
            return ApiError(502, "service_quota")
        if err.status == 429:
            return ApiError(503, "service_busy", retry_after=err.retry_after or 5)
    return None


def poll_error(err, upstream, invalid_code):
    """Map a failure while reading an existing task (never creates anything)."""
    wait = err.retry_after or max(1, upstream.poll_after_ms // 1000)
    if err.kind == "http":
        status = err.status or 0
        if status == 429:
            return ApiError(503, "service_busy", retry_after=wait)
        if status >= 500:
            return ApiError(503, "service_unavailable", retry_after=wait)
        if status in (401, 403):
            return ApiError(502, "service_auth")
        if status == 402:
            return ApiError(502, "service_quota")
        return ApiError(502, "upstream_error")
    if err.kind == "invalid":
        return ApiError(502, invalid_code)
    return ApiError(503, "service_unavailable", retry_after=wait)


def task_json(record, upstream, reused=None):
    doc = {
        "task_id": record["task_id"],
        "status": record["status"],
        "progress": int(record["progress"]),
        "simulated": bool(upstream.simulated),
        "poll_after_ms": int(upstream.poll_after_ms),
    }
    if reused is not None:
        doc["reused"] = reused
    return doc


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "HumanTwinProxy/1.0"
    sys_version = ""
    protocol_version = "HTTP/1.0"
    timeout = 60

    # Default access/error logs contain raw paths and request lines; we log our own.
    def log_request(self, code="-", size="-"):
        pass

    def log_message(self, format, *args):
        pass

    # Every method (HEAD, OPTIONS, BREW, ...) goes through _dispatch, so the Origin
    # guard and the JSON 405 apply instead of the framework's HTML 501 page.
    def __getattr__(self, name):
        if name.startswith("do_"):
            return self._dispatch
        raise AttributeError(name)

    def _dispatch(self):
        self._route = self._task_id = None
        self._notes = []
        self._responded = False
        try:
            if self.headers.get("Origin") is not None:
                raise ApiError(403, "forbidden")
            self._route, self._task_id = match_route(urllib.parse.urlsplit(self.path).path)
            allowed = ROUTE_METHODS[self._route]
            if self.command != allowed:
                raise ApiError(405, "method_not_allowed", allow=allowed)
            getattr(self, "_handle_" + self._route)()
        except ApiError as err:
            self._send_error(err)
        except ConnectionError:  # the app went away mid-response (e.g. its timeout)
            self.close_connection = True
            LOG.info("%s %s client disconnected", self.command, ROUTE_LABELS.get(self._route, "-"))
        except Exception as exc:  # never leak details; log the type only
            LOG.error("internal error %s %s: %s", self.command,
                      ROUTE_LABELS.get(self._route, "-"), type(exc).__name__)
            if not self._responded:
                self._send_error(ApiError(500, "internal_error"))

    # ---- responses

    def _send(self, status, body, content_type, headers=()):
        self._responded = True
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        self._log(status)

    def _send_json(self, status, doc, headers=()):
        body = json.dumps(doc, ensure_ascii=False).encode("utf-8")
        self._send(status, body, "application/json; charset=utf-8", headers)

    def _send_error(self, err):
        retryable, message = ERRORS[err.code]
        headers = []
        if err.retry_after:
            headers.append(("Retry-After", str(err.retry_after)))
        if err.allow:
            headers.append(("Allow", err.allow))
        self.close_connection = True
        self._send_json(err.status, {"error": {"code": err.code, "message": message,
                                               "retryable": retryable}}, headers)

    def _log(self, status):
        parts = [self.command, ROUTE_LABELS.get(self._route, "-"), str(status)]
        if self._task_id and TASK_ID_RE.fullmatch(self._task_id):
            parts.append("task=" + self._task_id[:12])
        LOG.info(" ".join(parts + self._notes))

    # ---- endpoints

    def _handle_health(self):
        up = self.server.upstream
        self._send_json(200, {"ok": True, "upstream": up.mode, "simulated": bool(up.simulated)})

    def _read_json_body(self):
        content_type = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if content_type != "application/json":
            raise ApiError(415, "unsupported_media_type")
        declared = self.headers.get("Content-Length")
        if declared is None:
            raise ApiError(411, "length_required")
        declared = declared.strip()
        if not re.fullmatch(r"[0-9]+", declared):  # ASCII only: "²".isdigit() is True
            raise ApiError(400, "invalid_request")
        if len(declared) > 12 or int(declared) > MAX_BODY_BYTES:
            raise ApiError(413, "payload_too_large")  # body is never read
        length = int(declared)
        raw = self.rfile.read(length)
        if len(raw) != length:
            raise ApiError(400, "invalid_request")
        try:
            return json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError, RecursionError):
            raise ApiError(400, "invalid_request") from None

    def _handle_create(self):
        payload = self._read_json_body()
        if not isinstance(payload, dict):
            raise ApiError(400, "invalid_request")
        images = payload.get("images")
        if not isinstance(images, list) or len(images) != 3:
            raise ApiError(400, "invalid_photos")
        decoded = [decode_photo(item) for item in images]
        if any(raw is None for raw in decoded):
            raise ApiError(400, "invalid_photos")
        digest = input_hash(decoded)
        self._notes.append("input=" + digest[:10])
        status, doc = self._create_once(digest, images)
        if status is None:  # fake "lost-create-response": close without any reply
            self.close_connection = True
            self._responded = True
            LOG.info("POST /v1/generations dropped-response (simulated) %s", " ".join(self._notes))
            return
        self._send_json(status, doc)

    def _create_once(self, digest, images):
        up, store = self.server.upstream, self.server.store
        with self.server.create_lock:
            record = store.by_hash(up.scope, digest)
            if record is not None:
                if record["task_id"]:
                    self._notes.append("reused=true")
                    return 200, task_json(record, up, reused=True)
                if record["state"] == "creating":  # left over from a crash mid-create
                    store.mark_unknown(up.scope, digest)
                self._notes.append("state=submission_unknown")
                raise ApiError(409, "submission_unknown")
            store.insert_creating(up.scope, digest)  # committed before the paid call
            try:
                task_id = up.create(images)
                if not isinstance(task_id, str) or not TASK_ID_RE.fullmatch(task_id):
                    raise UpstreamError("invalid")
            except UpstreamError as err:
                definitive = create_error(err)
                if definitive is None:
                    store.mark_unknown(up.scope, digest)
                    self._notes.append("state=submission_unknown")
                    raise ApiError(502, "submission_unknown") from None
                store.delete_uncreated(up.scope, digest)
                raise definitive from None
            except Exception as exc:  # unexpected: treat the outcome as unknown
                store.mark_unknown(up.scope, digest)
                LOG.error("unexpected create failure: %s", type(exc).__name__)
                self._notes.append("state=submission_unknown")
                raise ApiError(502, "submission_unknown") from None
            store.mark_created(up.scope, digest, task_id)
            record = store.by_hash(up.scope, digest)
        self._task_id = task_id
        self._notes.append("reused=false")
        if up.drop_create_response:
            return None, None
        return 201, task_json(record, up, reused=False)

    def _lookup(self):
        task_id = self._task_id
        if not task_id or not TASK_ID_RE.fullmatch(task_id):
            raise ApiError(404, "task_not_found")
        record = self.server.store.by_task(self.server.upstream.scope, task_id)
        if record is None:
            raise ApiError(404, "task_not_found")
        return record

    def _handle_task(self):
        up, store = self.server.upstream, self.server.store
        record = self._lookup()
        if record["status"] not in TERMINAL:
            try:
                result = up.get(record)
            except UpstreamError as err:
                raise poll_error(err, up, "upstream_invalid") from None
            status = result.get("status")
            if status not in STATUSES:
                raise ApiError(502, "upstream_invalid")
            try:
                progress = max(0, min(100, int(result.get("progress") or 0)))
            except (TypeError, ValueError, OverflowError):
                progress = 0
            if status == "SUCCEEDED":
                progress = 100
            store.update_status(up.scope, record["task_id"], status, progress)
            record.update(status=status, progress=progress)
        self._send_json(200, task_json(record, up))

    def _handle_model(self):
        up = self.server.upstream
        record = self._lookup()
        if record["status"] != "SUCCEEDED":
            raise ApiError(409, "model_not_ready")
        try:
            data = up.fetch_model(record) if up.simulated else self._cached_model(record)
        except UpstreamError as err:
            raise poll_error(err, up, "model_invalid") from None
        if not isinstance(data, (bytes, bytearray)) or glb_length(data) != len(data):
            raise ApiError(502, "model_invalid")
        self._send(200, bytes(data), "model/gltf-binary")

    def _cached_model(self, record):
        """Download a task's model at most once; retries and re-entries reuse it.

        The per-task lock makes a retry (e.g. after the app's own timeout) wait for
        the download already in flight instead of starting a second one.
        """
        up, server = self.server.upstream, self.server
        key = hashlib.sha256(f"{up.scope}\n{record['task_id']}".encode()).hexdigest()[:40]
        path = server.model_dir / (key + ".glb")
        with server.model_lock(key):
            try:
                cached = path.read_bytes()
                if glb_length(cached) == len(cached):
                    return cached
            except OSError:
                pass
            data = up.fetch_model(record)
            if isinstance(data, (bytes, bytearray)) and glb_length(data) == len(data):
                write_atomic(path, bytes(data))
            return data


class ProxyServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, upstream, store, model_dir):
        self.upstream = upstream
        self.store = store
        self.model_dir = Path(model_dir)
        self.create_lock = threading.Lock()
        self._model_locks = {}
        self._model_locks_guard = threading.Lock()
        super().__init__(address, ProxyHandler)

    def model_lock(self, key):
        with self._model_locks_guard:
            return self._model_locks.setdefault(key, threading.Lock())

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)  # skip HTTPServer's reverse-DNS lookup
        self.server_name, self.server_port = self.server_address[:2]

    def handle_error(self, request, client_address):
        LOG.warning("connection error: %s", sys.exc_info()[0].__name__)

    def server_close(self):
        super().server_close()
        self.store.close()


class _ProxyServer6(ProxyServer):
    address_family = socket.AF_INET6


def build_server(upstream, db_path, host="127.0.0.1", port=8787):
    """Create (but do not start) a proxy bound to a loopback address."""
    if host not in LOOPBACK_HOSTS:
        raise ValueError("refusing to bind a non-loopback host")
    store = TaskStore(db_path)
    try:
        cls = _ProxyServer6 if ":" in host else ProxyServer
        return cls((host, port), upstream, store, Path(db_path).parent / "models")
    except BaseException:
        store.close()
        raise


def parse_args(argv):
    parser = argparse.ArgumentParser(description="HumanTwin AI local generation proxy.")
    parser.add_argument("--host", default="127.0.0.1", help="loopback only: 127.0.0.1, ::1, localhost")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--upstream", choices=("fake", "meshy"), default="fake")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--fake-duration", type=float, default=6.0)
    parser.add_argument("--fake-scenario", choices=FakeUpstream.SCENARIOS, default="ok")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if args.host not in LOOPBACK_HOSTS:
        print("error: refusing to bind a non-loopback host; use 127.0.0.1, ::1 or localhost "
              "(the Android emulator reaches it via 10.0.2.2 or adb reverse).", file=sys.stderr)
        return 2
    if args.upstream == "meshy":
        key = os.environ.get("MESHY_API_KEY", "").strip()
        if not key:
            print("error: --upstream meshy requires the MESHY_API_KEY environment variable "
                  "(its value is never printed).", file=sys.stderr)
            return 2
        base_url = os.environ.get("MESHY_API_BASE_URL", DEFAULT_MESHY_BASE).strip()
        try:
            upstream = MeshyUpstream(key, base_url, allow_insecure_loopback=is_loopback_http(base_url))
        except ValueError:
            print("error: MESHY_API_BASE_URL must be an https URL (http only on 127.0.0.1).",
                  file=sys.stderr)
            return 2
        label = "real Meshy API, consumes credits"
    else:
        upstream = FakeUpstream(args.fake_duration, args.fake_scenario)
        label = f"simulated, sample model, scenario={args.fake_scenario}"
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        server = build_server(upstream, args.db, args.host, args.port)
    except OSError as err:
        print(f"error: could not start on {args.host}:{args.port} ({err.strerror or 'bind failed'}).",
              file=sys.stderr)
        return 1
    host, port = server.server_address[:2]
    shown = f"[{host}]" if ":" in host else host
    print(f"HumanTwin proxy: upstream={upstream.mode} ({label}) | listening on "
          f"http://{shown}:{port} | db={Path(args.db).resolve()} | records={upstream.scope}",
          flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
