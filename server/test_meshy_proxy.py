"""Hermetic tests for server/meshy_proxy.py.

Run from the repository root:
    python3 -m unittest -v server/test_meshy_proxy.py

Every HTTP peer is an in-process server on 127.0.0.1. Nothing contacts Meshy or
any other external host, and the only "key" used is a dummy string.
"""

import base64
import http.client
import io
import json
import logging
import os
import select
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import meshy_proxy as proxy  # noqa: E402

PROXY_SCRIPT = Path(__file__).resolve().parent / "meshy_proxy.py"
KEY = "test-key-DO-NOT-LEAK"
SIGNED_TOKEN = "SIGNED-SECRET-TOKEN-4f1c"
RAW_ERROR = "RAW-UPSTREAM-ERROR-TEXT-9a7e"
LOG_STREAM = io.StringIO()


def setUpModule():
    logger = logging.getLogger("meshy_proxy")
    logger.addHandler(logging.StreamHandler(LOG_STREAM))
    logger.setLevel(logging.INFO)
    logger.propagate = False


def png(tag):
    return b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + tag.encode() * 8


def jpeg(tag):
    return b"\xff\xd8\xff\xe0" + b"\x00\x10JFIF" + tag.encode() * 8


def uri(mime, raw):
    return f"data:{mime};base64," + base64.b64encode(raw).decode("ascii")


def photo_set(tag="a"):
    return [uri("image/png", png(tag + "-front")),
            uri("image/jpeg", jpeg(tag + "-side")),
            uri("image/png", png(tag + "-back"))]


def glb(payload, extra_declared=0):
    """Bytes with a binary glTF 2.0 header (the proxy validates only the header)."""
    total = 12 + len(payload) + extra_declared
    return b"glTF" + (2).to_bytes(4, "little") + total.to_bytes(4, "little") + payload


class Reply:
    def __init__(self, status, headers, body):
        self.status, self.headers, self.body = status, headers, body

    def json(self):
        return json.loads(self.body.decode("utf-8"))

    def error(self):
        return self.json()["error"]


class QuietServer(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]

    def handle_error(self, request, client_address):
        pass


class ProxyHarness:
    """Runs a proxy in-process on an ephemeral loopback port."""

    def __init__(self, upstream, db_path):
        self.server = proxy.build_server(upstream, db_path, host="127.0.0.1", port=0)
        self.port = self.server.server_address[1]
        self.captured = []
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       kwargs={"poll_interval": 0.05}, daemon=True)
        self.thread.start()

    def request(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        try:
            conn.request(method, path, body=body, headers=headers or {})
            resp = conn.getresponse()
            data = resp.read()
            self.captured.append(str(resp.headers).encode() + data)
            return Reply(resp.status, resp.headers, data)
        finally:
            conn.close()

    def post_images(self, images, headers=None):
        body = json.dumps({"images": images}).encode()
        return self.request("POST", "/v1/generations", body,
                            {"Content-Type": "application/json", **(headers or {})})

    def get_task(self, task_id):
        return self.request("GET", f"/v1/generations/{task_id}")

    def get_model(self, task_id):
        return self.request("GET", f"/v1/generations/{task_id}/model.glb")

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class CountingFake(proxy.FakeUpstream):
    def __init__(self, *args, create_delay=0.0, **kwargs):
        super().__init__(*args, **kwargs)
        self.creates = self.gets = 0
        self.create_delay = create_delay
        self._count_lock = threading.Lock()

    def create(self, images):
        with self._count_lock:
            self.creates += 1
        time.sleep(self.create_delay)
        return super().create(images)

    def get(self, record):
        with self._count_lock:
            self.gets += 1
        return super().get(record)


class HarnessMixin:
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.db = Path(self._tmp.name) / "tasks.sqlite3"
        self.harnesses, self.stopped = [], []

    def tearDown(self):
        for harness in self.harnesses:
            harness.close()
        self._tmp.cleanup()

    def start(self, upstream):
        harness = ProxyHarness(upstream, self.db)
        self.harnesses.append(harness)
        return harness

    def stop(self, harness):
        harness.close()
        self.harnesses.remove(harness)
        self.stopped.append(harness)  # its captured replies are still checked for secrets


# ----------------------------------------------------------------------- fake mode


class FakeModeTests(HarnessMixin, unittest.TestCase):
    def test_health_reports_simulated_fake_upstream(self):
        h = self.start(CountingFake())
        r = h.request("GET", "/v1/health")
        self.assertEqual(r.status, 200)
        self.assertEqual(r.json(), {"ok": True, "upstream": "fake", "simulated": True})

    def test_same_images_reuse_one_task(self):
        up = CountingFake(duration=30)
        h = self.start(up)
        first = h.post_images(photo_set())
        self.assertEqual(first.status, 201)
        doc = first.json()
        self.assertEqual((doc["status"], doc["progress"], doc["reused"]), ("PENDING", 0, False))
        self.assertTrue(doc["simulated"])
        self.assertEqual(doc["poll_after_ms"], 1000)
        self.assertTrue(doc["task_id"].startswith("fake-"))
        second = h.post_images(photo_set())
        self.assertEqual(second.status, 200)
        self.assertEqual(second.json()["task_id"], doc["task_id"])
        self.assertTrue(second.json()["reused"])
        self.assertEqual(up.creates, 1)

    def test_different_order_is_a_different_task(self):
        up = CountingFake(duration=30)
        h = self.start(up)
        images = photo_set()
        a = h.post_images(images)
        b = h.post_images([images[2], images[1], images[0]])
        self.assertEqual((a.status, b.status), (201, 201))
        self.assertNotEqual(a.json()["task_id"], b.json()["task_id"])
        self.assertEqual(up.creates, 2)

    def test_photo_validation_rejects_bad_input(self):
        up = CountingFake()
        h = self.start(up)
        good = photo_set()
        oversize = uri("image/png", b"\x89PNG\r\n\x1a\n" + b"\0" * (proxy.MAX_IMAGE_BYTES - 7))
        cases = {
            "two images": good[:2],
            "four images": good + [good[0]],
            "bad base64": [good[0], "data:image/png;base64,@@not-base64@@", good[2]],
            "wrong mime": [good[0], uri("image/gif", b"GIF89a" + b"x" * 9), good[2]],
            "png labelled jpeg": [good[0], uri("image/jpeg", png("x")), good[2]],
            "jpeg labelled png": [uri("image/png", jpeg("x")), good[1], good[2]],
            "empty image": [good[0], "data:image/png;base64,", good[2]],
            "not a data uri": [good[0], "https://example.invalid/a.png", good[2]],
            "not a string": [good[0], 42, good[2]],
            "oversize image": [good[0], oversize, good[2]],
        }
        for name, images in cases.items():
            with self.subTest(name):
                r = h.post_images(images)
                self.assertEqual(r.status, 400)
                self.assertEqual(r.error()["code"], "invalid_photos")
                self.assertFalse(r.error()["retryable"])
        for name, body in {"malformed json": b"{not json", "array body": b"[]"}.items():
            with self.subTest(name):
                r = h.request("POST", "/v1/generations", body, {"Content-Type": "application/json"})
                self.assertEqual((r.status, r.error()["code"]), (400, "invalid_request"))
        r = h.request("POST", "/v1/generations", b"{}", {"Content-Type": "application/json"})
        self.assertEqual((r.status, r.error()["code"]), (400, "invalid_photos"))
        self.assertEqual(up.creates, 0)

    def test_request_guards(self):
        up = CountingFake()
        h = self.start(up)
        body = json.dumps({"images": photo_set()}).encode()
        r = h.request("POST", "/v1/generations", body, {"Content-Type": "text/plain"})
        self.assertEqual((r.status, r.error()["code"]), (415, "unsupported_media_type"))
        r = h.post_images(photo_set(), headers={"Origin": "https://evil.example"})
        self.assertEqual((r.status, r.error()["code"]), (403, "forbidden"))
        r = h.request("GET", "/v1/health", headers={"Origin": "null"})
        self.assertEqual(r.status, 403)
        r = h.request("GET", "/v2/anything")
        self.assertEqual((r.status, r.error()["code"]), (404, "not_found"))
        r = h.request("GET", "/v1/generations")
        self.assertEqual((r.status, r.headers["Allow"]), (405, "POST"))
        r = h.request("DELETE", "/v1/generations/fake-abc")
        self.assertEqual((r.status, r.headers["Allow"]), (405, "GET"))
        # Methods the framework does not know must not fall back to its HTML 501 page.
        r = h.request("HEAD", "/v1/health")
        self.assertEqual((r.status, r.headers["Allow"], r.body), (405, "GET", b""))
        self.assertTrue(r.headers["Content-Type"].startswith("application/json"))
        r = h.request("OPTIONS", "/v1/generations", headers={"Origin": "https://evil.example"})
        self.assertEqual((r.status, r.error()["code"]), (403, "forbidden"))
        for method, path, allow in (("OPTIONS", "/v1/generations", "POST"),
                                    ("BREW", "/v1/health", "GET")):
            with self.subTest(method):
                r = h.request(method, path)
                self.assertEqual((r.status, r.headers["Allow"], r.error()["code"]),
                                 (405, allow, "method_not_allowed"))
        self.assertEqual(up.creates, 0)

    def _raw_post(self, port, content_length):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        try:
            conn.putrequest("POST", "/v1/generations")
            conn.putheader("Content-Type", "application/json")
            if content_length is not None:
                conn.putheader("Content-Length", str(content_length))
            conn.endheaders()
            resp = conn.getresponse()
            return resp.status, json.loads(resp.read())["error"]["code"]
        finally:
            conn.close()

    def test_oversize_body_and_missing_length(self):
        h = self.start(CountingFake())
        self.assertEqual(self._raw_post(h.port, proxy.MAX_BODY_BYTES + 1), (413, "payload_too_large"))
        self.assertEqual(self._raw_post(h.port, "9" * 40), (413, "payload_too_large"))
        self.assertEqual(self._raw_post(h.port, None), (411, "length_required"))
        # latin-1 "²" passes str.isdigit() but int() rejects it: must be a 400, not a 500.
        for odd in ("²", "-1", "1e3"):
            with self.subTest(odd):
                self.assertEqual(self._raw_post(h.port, odd), (400, "invalid_request"))

    def test_fake_progression_and_sample_model(self):
        up = CountingFake(duration=0.6)
        h = self.start(up)
        task_id = h.post_images(photo_set()).json()["task_id"]
        seen, deadline = [], time.time() + 5
        while time.time() < deadline:
            r = h.get_task(task_id)
            self.assertEqual(r.status, 200)
            doc = r.json()
            self.assertNotIn("reused", doc)
            seen.append((doc["status"], doc["progress"]))
            if doc["status"] == "SUCCEEDED":
                break
            time.sleep(0.03)
        self.assertEqual(seen[-1], ("SUCCEEDED", 100))
        self.assertIn("IN_PROGRESS", [s for s, _ in seen])
        progress = [p for _, p in seen]
        self.assertEqual(progress, sorted(progress))
        gets = up.gets
        self.assertEqual(h.get_task(task_id).json()["status"], "SUCCEEDED")
        self.assertEqual(up.gets, gets, "terminal status must be served without upstream calls")
        model = h.get_model(task_id)
        self.assertEqual(model.status, 200)
        self.assertEqual(model.headers["Content-Type"], "model/gltf-binary")
        self.assertEqual(model.body, proxy.SAMPLE_GLB.read_bytes())
        self.assertEqual(int(model.headers["Content-Length"]), len(model.body))

    def test_model_before_success_is_not_ready(self):
        h = self.start(CountingFake(duration=30))
        task_id = h.post_images(photo_set()).json()["task_id"]
        r = h.get_model(task_id)
        self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                         (409, "model_not_ready", True))

    def test_unknown_or_malformed_task_ids(self):
        up = CountingFake(duration=30)
        h = self.start(up)
        for path in ("fake-" + "0" * 32, "bad%24id", "a" * 129, "..%2F..%2Fetc"):
            with self.subTest(path):
                for r in (h.get_task(path), h.get_model(path)):
                    self.assertEqual((r.status, r.error()["code"]), (404, "task_not_found"))
        self.assertEqual(up.gets, 0)

    def test_task_ids_are_scoped_to_upstream_mode(self):
        h = self.start(CountingFake(duration=30))
        task_id = h.post_images(photo_set()).json()["task_id"]
        self.stop(h)
        closed = socket.socket()
        closed.bind(("127.0.0.1", 0))
        port = closed.getsockname()[1]
        closed.close()
        meshy = proxy.MeshyUpstream(KEY, f"http://127.0.0.1:{port}", allow_insecure_loopback=True)
        h2 = self.start(meshy)
        self.assertEqual(h2.get_task(task_id).status, 404)

    def test_concurrent_identical_posts_create_once(self):
        up = CountingFake(duration=30, create_delay=0.3)
        h = self.start(up)
        barrier, results = threading.Barrier(2), []

        def worker():
            barrier.wait()
            results.append(h.post_images(photo_set()))

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(10)
        self.assertEqual(sorted(r.status for r in results), [200, 201])
        self.assertEqual(len({r.json()["task_id"] for r in results}), 1)
        self.assertEqual(up.creates, 1)

    def test_tasks_survive_restart(self):
        up = CountingFake(duration=0.2)
        h = self.start(up)
        task_id = h.post_images(photo_set()).json()["task_id"]
        self.stop(h)
        time.sleep(0.25)
        up2 = CountingFake(duration=0.2)
        h2 = self.start(up2)
        again = h2.post_images(photo_set())
        self.assertEqual((again.status, again.json()["task_id"], again.json()["reused"]),
                         (200, task_id, True))
        self.assertEqual(h2.get_task(task_id).json()["status"], "SUCCEEDED")
        self.assertEqual(up2.creates, 0)

    def test_fake_scenarios_keep_separate_records(self):
        # QA of failure scenarios on the default DB must not break the default demo.
        failed = CountingFake(duration=0.05, scenario="task-failed")
        h = self.start(failed)
        failed_id = h.post_images(photo_set()).json()["task_id"]
        time.sleep(0.1)
        self.assertEqual(h.get_task(failed_id).json()["status"], "FAILED")
        self.stop(h)
        h = self.start(CountingFake(scenario="upstream-unknown"))
        self.assertEqual(h.post_images(photo_set()).status, 502)
        self.stop(h)
        ok = CountingFake(duration=0.05)
        h = self.start(ok)
        r = h.post_images(photo_set())
        self.assertEqual((r.status, r.json()["reused"]), (201, False))
        self.assertNotEqual(r.json()["task_id"], failed_id)
        self.assertEqual(h.get_task(failed_id).status, 404)
        time.sleep(0.1)
        self.assertEqual(h.get_task(r.json()["task_id"]).json()["status"], "SUCCEEDED")
        self.assertEqual(h.request("GET", "/v1/health").json()["upstream"], "fake")
        self.stop(h)
        again = CountingFake(duration=0.05, scenario="task-failed")
        h = self.start(again)
        r = h.post_images(photo_set())
        self.assertEqual((r.status, r.json()["task_id"], r.json()["status"]),
                         (200, failed_id, "FAILED"))
        self.assertEqual((ok.creates, again.creates), (1, 0))

    def test_scenario_task_failed(self):
        h = self.start(CountingFake(duration=0.1, scenario="task-failed"))
        task_id = h.post_images(photo_set()).json()["task_id"]
        time.sleep(0.15)
        self.assertEqual(h.get_task(task_id).json()["status"], "FAILED")
        self.assertEqual(h.get_model(task_id).status, 409)

    def test_scenario_lost_create_response_then_reuse(self):
        up = CountingFake(duration=30, scenario="lost-create-response")
        h = self.start(up)
        with self.assertRaises((ConnectionError, http.client.BadStatusLine)):
            h.post_images(photo_set())
        again = h.post_images(photo_set())
        self.assertEqual(again.status, 200)
        self.assertTrue(again.json()["reused"])
        self.assertEqual(up.creates, 1)
        self.assertEqual(h.get_task(again.json()["task_id"]).status, 200)

    def test_scenario_upstream_unknown_never_resubmits(self):
        up = CountingFake(scenario="upstream-unknown")
        h = self.start(up)
        first = h.post_images(photo_set())
        self.assertEqual((first.status, first.error()["code"], first.error()["retryable"]),
                         (502, "submission_unknown", False))
        for _ in range(2):
            again = h.post_images(photo_set())
            self.assertEqual((again.status, again.error()["code"]), (409, "submission_unknown"))
        self.assertEqual(up.creates, 1)

    def test_scenario_flaky_poll(self):
        up = CountingFake(duration=30, scenario="flaky-poll")
        h = self.start(up)
        task_id = h.post_images(photo_set()).json()["task_id"]
        r = h.get_task(task_id)
        self.assertEqual((r.status, r.headers["Retry-After"], r.error()["retryable"]), (503, "1", True))
        self.assertEqual(h.get_task(task_id).status, 200)
        self.assertEqual(up.creates, 1)


# ---------------------------------------------------------------------- Meshy mode


class FakeMeshy:
    """In-process stand-in for Meshy's Multi-Image-to-3D API."""

    def __init__(self):
        self.lock = threading.Lock()
        self.requests = []  # (method, path, headers, body)
        self.create_mode, self.create_status, self.create_headers = "ok", 500, {}
        self.get_status, self.get_headers, self.get_sleep = None, {}, 0.0
        self.task = {"status": "PENDING", "progress": 0, "glb": ""}
        self.model_mode = "ok"
        self.model_bytes = glb(bytes(range(200)))
        self.next_id = 0
        outer = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.0"

            def log_message(self, *args):
                pass

            def do_GET(self):
                outer.handle(self)

            do_POST = do_GET

        self.httpd = QuietServer(("127.0.0.1", 0), Handler)
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, kwargs={"poll_interval": 0.05},
                         daemon=True).start()

    def model_url(self):
        return f"{self.base}/assets/model.glb?X-Signature={SIGNED_TOKEN}"

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def count(self, method, prefix):
        with self.lock:
            return sum(1 for m, p, _, _ in self.requests if m == method and p.startswith(prefix))

    @staticmethod
    def reply(h, status, doc=None, headers=None, body=None):
        body = body if body is not None else json.dumps(doc).encode()
        h.send_response(status)
        for name, value in (headers or {}).items():
            h.send_header(name, value)
        h.send_header("Content-Length", str(len(body)))
        h.end_headers()
        h.wfile.write(body)

    def handle(self, h):
        length = int(h.headers.get("Content-Length") or 0)
        body = h.rfile.read(length) if length else b""
        path = urllib.parse.urlsplit(h.path).path
        with self.lock:
            self.requests.append((h.command, path, h.headers, body))
        api = proxy.MESHY_PATH
        if h.command == "POST" and path == api:
            return self.handle_create(h)
        if h.command == "GET" and path.startswith(api + "/"):
            return self.handle_get(h, path.rsplit("/", 1)[1])
        if h.command == "GET" and path == "/assets/model.glb":
            return self.handle_model(h)
        return self.reply(h, 404, {"message": RAW_ERROR})

    def handle_create(self, h):
        mode = self.create_mode
        if mode == "sleep":
            time.sleep(0.8)  # longer than the proxy's create timeout; the task IS created
        elif mode == "status":
            return self.reply(h, self.create_status, {"message": RAW_ERROR}, self.create_headers)
        elif mode == "malformed":
            return self.reply(h, 200, {"unexpected": RAW_ERROR})
        elif mode == "reset":
            h.close_connection = True
            return None
        with self.lock:
            self.next_id += 1
            task_id = f"meshy-task-{self.next_id}"
        return self.reply(h, 202, {"result": task_id})

    def handle_get(self, h, task_id):
        time.sleep(self.get_sleep)
        if self.get_status:
            return self.reply(h, self.get_status, {"message": RAW_ERROR}, self.get_headers)
        task = dict(self.task)
        return self.reply(h, 200, {
            "id": task_id, "status": task["status"], "progress": task["progress"],
            "model_urls": {"glb": task["glb"]}, "task_error": {"message": RAW_ERROR},
        })

    def handle_model(self, h):
        mode = self.model_mode
        if mode == "redirect_insecure":
            return self.reply(h, 302, {}, {"Location": "http://example.invalid/model.glb"})
        if mode == "status500":
            return self.reply(h, 500, {"message": RAW_ERROR})
        if mode == "declared_oversize":
            return self.reply(h, 200, body=b"glTF" + b"\0" * 5000)
        if mode == "streamed_oversize":  # no Content-Length: body ends at close
            h.send_response(200)
            h.end_headers()
            h.wfile.write(b"glTF" + b"\0" * 5000)
            return None
        if mode == "not_gltf":
            return self.reply(h, 200, body=b"<html>" + RAW_ERROR.encode())
        if mode == "bad_header":  # complete transfer, but the GLB header disagrees
            return self.reply(h, 200, body=glb(b"\0" * 40, extra_declared=8))
        if mode in ("truncated", "truncated_no_length"):  # CDN drops mid-transfer
            h.send_response(200)
            if mode == "truncated":
                h.send_header("Content-Length", str(len(self.model_bytes)))
            h.end_headers()
            h.wfile.write(self.model_bytes[:len(self.model_bytes) // 2])
            return None
        if mode == "odd_length":  # latin-1 "²" is str.isdigit() but not int()-able
            h.send_response(200)
            h.send_header("Content-Length", "²")
            h.end_headers()
            h.wfile.write(self.model_bytes)
            return None
        if mode == "trickle":  # each byte arrives well within any per-recv timeout
            h.send_response(200)
            h.send_header("Content-Length", str(2 * 1024 * 1024))
            h.end_headers()
            try:
                h.wfile.write(self.model_bytes[:12])
                for _ in range(60):
                    time.sleep(0.05)
                    h.wfile.write(b"\0")
            except OSError:
                pass
            return None
        if mode == "slow":
            time.sleep(0.8)
        return self.reply(h, 200, body=self.model_bytes)


class MeshyModeTests(HarnessMixin, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.meshy = FakeMeshy()
        self.log_start = len(LOG_STREAM.getvalue())

    def captured_log(self):
        return LOG_STREAM.getvalue()[self.log_start:]

    def tearDown(self):
        try:
            captured = self.captured_log().encode("utf-8")
            for harness in self.harnesses + self.stopped:
                captured += b"".join(harness.captured)
            for secret in (KEY, SIGNED_TOKEN, RAW_ERROR, self.meshy.model_url()):
                self.assertNotIn(secret.encode(), captured, "secret leaked to a response or log")
            with self.meshy.lock:
                for method, path, headers, _ in self.meshy.requests:
                    if path.startswith("/assets/"):
                        self.assertIsNone(headers.get("Authorization"), "key sent to model host")
        finally:
            self.meshy.close()
            super().tearDown()

    def upstream(self, **overrides):
        options = dict(create_timeout=0.4, get_timeout=0.4, download_timeout=2.0,
                       allow_insecure_loopback=True)
        options.update(overrides)
        return proxy.MeshyUpstream(KEY, self.meshy.base, **options)

    def creates(self):
        return self.meshy.count("POST", proxy.MESHY_PATH)

    def succeeded_task(self, h):
        task_id = h.post_images(photo_set()).json()["task_id"]
        self.meshy.task = {"status": "SUCCEEDED", "progress": 100, "glb": self.meshy.model_url()}
        self.assertEqual(h.get_task(task_id).json()["status"], "SUCCEEDED")
        return task_id

    def test_create_request_shape(self):
        h = self.start(self.upstream())
        images = photo_set()
        r = h.post_images(images)
        self.assertEqual(r.status, 201)
        self.assertEqual(r.json(), {"task_id": "meshy-task-1", "status": "PENDING", "progress": 0,
                                    "simulated": False, "poll_after_ms": 5000, "reused": False})
        self.assertEqual(h.request("GET", "/v1/health").json()["simulated"], False)
        with self.meshy.lock:
            [(method, path, headers, body)] = self.meshy.requests
        self.assertEqual(headers["Authorization"], "Bearer " + KEY)
        self.assertTrue(headers["Content-Type"].startswith("application/json"))
        self.assertEqual(json.loads(body), {
            "image_urls": images, "ai_model": "meshy-7.1", "geometry_resolution": "standard",
            "should_texture": True, "should_remesh": True, "target_polycount": 30000,
            "target_formats": ["glb"],
        })
        self.assertEqual(h.post_images(images).json()["reused"], True)
        self.assertEqual(self.creates(), 1)
        log = self.captured_log()
        self.assertIn("POST /v1/generations 201", log)
        self.assertIn("reused=true", log)

    def assert_unknown_then_blocked(self, h):
        first = h.post_images(photo_set())
        self.assertEqual((first.status, first.error()["code"], first.error()["retryable"]),
                         (502, "submission_unknown", False))
        second = h.post_images(photo_set())
        self.assertEqual((second.status, second.error()["code"]), (409, "submission_unknown"))
        self.assertEqual(self.creates(), 1, "an ambiguous create must never be re-submitted")

    def test_create_timeout_is_submission_unknown(self):
        self.meshy.create_mode = "sleep"
        self.assert_unknown_then_blocked(self.start(self.upstream()))

    def test_create_server_error_is_submission_unknown(self):
        self.meshy.create_mode, self.meshy.create_status = "status", 500
        self.assert_unknown_then_blocked(self.start(self.upstream()))

    def test_create_malformed_success_is_submission_unknown(self):
        self.meshy.create_mode = "malformed"
        self.assert_unknown_then_blocked(self.start(self.upstream()))

    def test_create_connection_closed_is_submission_unknown(self):
        self.meshy.create_mode = "reset"
        self.assert_unknown_then_blocked(self.start(self.upstream()))

    def test_definitive_rejections_delete_the_attempt(self):
        h = self.start(self.upstream())
        expected = {400: (422, "photos_rejected"), 422: (422, "photos_rejected"),
                    401: (502, "service_auth"), 403: (502, "service_auth")}
        for upstream_status, (status, code) in expected.items():
            with self.subTest(upstream_status):
                self.meshy.create_mode, self.meshy.create_status = "status", upstream_status
                images = photo_set(f"reject-{upstream_status}")
                before = self.creates()
                r = h.post_images(images)
                self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                                 (status, code, False))
                scope = h.server.upstream.scope
                self.assertIsNone(h.server.store.by_hash(scope, self._digest(images)))
                self.assertEqual(self.creates(), before + 1)

    @staticmethod
    def _digest(images):
        return proxy.input_hash([proxy.decode_photo(item) for item in images])

    def test_quota_error_allows_exactly_one_later_create(self):
        h = self.start(self.upstream())
        self.meshy.create_mode, self.meshy.create_status = "status", 402
        r = h.post_images(photo_set())
        self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                         (502, "service_quota", False))
        self.meshy.create_mode = "ok"
        self.assertEqual(h.post_images(photo_set()).status, 201)
        self.assertEqual(h.post_images(photo_set()).status, 200)
        self.assertEqual(self.creates(), 2)

    def test_rate_limited_create(self):
        h = self.start(self.upstream())
        self.meshy.create_mode, self.meshy.create_status = "status", 429
        for sent, expected in (("7", "7"), ("soon", "5")):
            with self.subTest(retry_after=sent):
                self.meshy.create_headers = {"Retry-After": sent}
                r = h.post_images(photo_set())
                self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                                 (503, "service_busy", True))
                self.assertEqual(r.headers["Retry-After"], expected)

    def test_connection_refused_create_is_retryable(self):
        closed = socket.socket()
        closed.bind(("127.0.0.1", 0))
        port = closed.getsockname()[1]
        closed.close()
        up = proxy.MeshyUpstream(KEY, f"http://127.0.0.1:{port}", allow_insecure_loopback=True)
        h = self.start(up)
        for _ in range(2):  # the attempt row is deleted, so a retry is not blocked
            r = h.post_images(photo_set())
            self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                             (503, "service_unavailable", True))

    def test_stale_creating_row_becomes_submission_unknown(self):
        images = photo_set()
        up = self.upstream()
        store = proxy.TaskStore(self.db)
        store.insert_creating(up.scope, self._digest(images))  # simulated crash mid-create
        store.close()
        h = self.start(up)
        self.assertEqual(h.server.store.by_hash(up.scope, self._digest(images))["state"],
                         "submission_unknown")
        r = h.post_images(images)
        self.assertEqual((r.status, r.error()["code"]), (409, "submission_unknown"))
        self.assertEqual(self.creates(), 0)

    def test_polling_errors_never_create(self):
        h = self.start(self.upstream())
        task_id = h.post_images(photo_set()).json()["task_id"]
        cases = [
            (429, {"Retry-After": "3"}, 503, "service_busy", "3"),
            (500, {}, 503, "service_unavailable", "5"),
            (503, {}, 503, "service_unavailable", "5"),
            (401, {}, 502, "service_auth", None),
            (402, {}, 502, "service_quota", None),
            (404, {}, 502, "upstream_error", None),
        ]
        for upstream_status, headers, status, code, retry_after in cases:
            with self.subTest(upstream_status):
                self.meshy.get_status, self.meshy.get_headers = upstream_status, headers
                r = h.get_task(task_id)
                self.assertEqual((r.status, r.error()["code"]), (status, code))
                self.assertEqual(r.headers.get("Retry-After"), retry_after)
                self.assertEqual(r.error()["retryable"], status == 503)
        self.meshy.get_status = None
        self.meshy.get_sleep = 0.8
        r = h.get_task(task_id)
        self.assertEqual((r.status, r.error()["code"]), (503, "service_unavailable"))
        self.meshy.get_sleep = 0.0
        self.meshy.task = {"status": "WEIRD", "progress": 5, "glb": ""}
        r = h.get_task(task_id)
        self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                         (502, "upstream_invalid", True))
        for raw, clamped in ((150, 100), (-4, 0), ("x", 0)):
            self.meshy.task = {"status": "IN_PROGRESS", "progress": raw, "glb": ""}
            self.assertEqual(h.get_task(task_id).json()["progress"], clamped)
        self.assertEqual(self.creates(), 1)

    def test_succeeded_task_downloads_model(self):
        h = self.start(self.upstream())
        task_id = h.post_images(photo_set()).json()["task_id"]
        self.assertEqual(h.get_model(task_id).status, 409)
        task_id = self.succeeded_task(h)
        polls = self.meshy.count("GET", proxy.MESHY_PATH + "/")
        self.assertEqual(h.get_task(task_id).json()["progress"], 100)
        self.assertEqual(self.meshy.count("GET", proxy.MESHY_PATH + "/"), polls)
        model = h.get_model(task_id)
        self.assertEqual((model.status, model.body), (200, self.meshy.model_bytes))
        self.assertEqual(model.headers["Content-Type"], "model/gltf-binary")
        self.assertEqual(self.meshy.count("GET", "/assets/"), 1)
        # Retries and a proxy restart are served from the cache: no second download.
        polls = self.meshy.count("GET", proxy.MESHY_PATH + "/")
        self.assertEqual(h.get_model(task_id).body, self.meshy.model_bytes)
        self.stop(h)
        h = self.start(self.upstream())
        self.assertEqual(h.get_model(task_id).body, self.meshy.model_bytes)
        self.assertEqual(self.meshy.count("GET", "/assets/"), 1)
        self.assertEqual(self.meshy.count("GET", proxy.MESHY_PATH + "/"), polls)
        self.assertEqual(self.creates(), 1)

    def test_retry_during_slow_download_reuses_it(self):
        h = self.start(self.upstream())
        task_id = self.succeeded_task(h)
        self.meshy.model_mode = "slow"
        conn = http.client.HTTPConnection("127.0.0.1", h.port, timeout=0.3)
        try:
            with self.assertRaises(TimeoutError):  # the app gave up waiting for headers
                conn.request("GET", f"/v1/generations/{task_id}/model.glb")
                conn.getresponse()
        finally:
            conn.close()
        r = h.get_model(task_id)  # waits for the in-flight download, then reuses it
        self.assertEqual((r.status, r.body), (200, self.meshy.model_bytes))
        self.assertEqual(self.meshy.count("GET", "/assets/"), 1)

    def test_interrupted_model_download_is_retryable(self):
        h = self.start(self.upstream())
        task_id = self.succeeded_task(h)
        for mode in ("truncated", "truncated_no_length"):
            with self.subTest(mode):
                self.meshy.model_mode = mode
                r = h.get_model(task_id)
                self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                                 (503, "service_unavailable", True))
        self.meshy.model_mode = "odd_length"  # unparsable length: read to close, then verify
        r = h.get_model(task_id)
        self.assertEqual((r.status, r.body), (200, self.meshy.model_bytes))

    def test_model_download_has_a_total_deadline(self):
        h = self.start(self.upstream(download_timeout=0.5))
        task_id = self.succeeded_task(h)
        self.meshy.model_mode = "trickle"
        started = time.monotonic()
        r = h.get_model(task_id)
        self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                         (503, "service_unavailable", True))
        self.assertLess(time.monotonic() - started, 1.5)

    def test_records_are_scoped_to_the_endpoint(self):
        self.assertEqual(proxy.MeshyUpstream(KEY).scope, "meshy")
        self.assertEqual(proxy.MeshyUpstream(KEY, "https://API.meshy.ai:443/").scope, "meshy")
        h = self.start(self.upstream())
        first_id = h.post_images(photo_set()).json()["task_id"]
        self.assertNotEqual(h.server.upstream.scope, "meshy")
        self.stop(h)
        other = FakeMeshy()
        self.addCleanup(other.close)
        other.next_id = 100
        h = self.start(proxy.MeshyUpstream(KEY, other.base, create_timeout=0.4, get_timeout=0.4,
                                           allow_insecure_loopback=True))
        r = h.post_images(photo_set())
        self.assertEqual((r.status, r.json()["task_id"], r.json()["reused"]),
                         (201, "meshy-task-101", False))
        self.assertEqual(h.get_task(first_id).status, 404)
        self.assertEqual(other.count("POST", proxy.MESHY_PATH), 1)
        self.assertEqual(other.count("GET", proxy.MESHY_PATH + "/"), 0)
        self.assertEqual(self.creates(), 1)

    def test_invalid_models_are_rejected(self):
        h = self.start(self.upstream(max_model_bytes=1024))
        task_id = self.succeeded_task(h)
        for mode in ("not_gltf", "bad_header", "declared_oversize", "streamed_oversize",
                     "redirect_insecure"):
            with self.subTest(mode):
                self.meshy.model_mode = mode
                r = h.get_model(task_id)
                self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                                 (502, "model_invalid", False))
        self.meshy.model_mode = "ok"
        self.meshy.task["glb"] = "http://example.invalid/model.glb"  # rejected, never fetched
        r = h.get_model(task_id)
        self.assertEqual((r.status, r.error()["code"]), (502, "model_invalid"))

    def test_model_download_server_error_is_retryable(self):
        h = self.start(self.upstream())
        task_id = self.succeeded_task(h)
        self.meshy.model_mode = "status500"
        r = h.get_model(task_id)
        self.assertEqual((r.status, r.error()["code"], r.error()["retryable"]),
                         (503, "service_unavailable", True))
        self.meshy.model_mode = "ok"
        self.assertEqual(h.get_model(task_id).status, 200)
        self.assertEqual(self.creates(), 1)

    def test_base_url_must_be_https_unless_loopback_testing(self):
        with self.assertRaises(ValueError):
            proxy.MeshyUpstream(KEY, "http://api.example.invalid")
        with self.assertRaises(ValueError):
            proxy.MeshyUpstream(KEY, self.meshy.base)  # http without the test flag
        with self.assertRaises(ValueError):
            proxy.MeshyUpstream("", proxy.DEFAULT_MESHY_BASE)


# --------------------------------------------------------------------------- CLI


class CliTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.db = str(Path(self._tmp.name) / "cli.sqlite3")
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("MESHY_")}
        self.env["PYTHONDONTWRITEBYTECODE"] = "1"

    def tearDown(self):
        self._tmp.cleanup()

    def run_cli(self, *args, env=None):
        return subprocess.run([sys.executable, str(PROXY_SCRIPT), "--db", self.db, *args],
                              env=env or self.env, capture_output=True, text=True, timeout=10)

    def first_line(self, *args, env=None):
        proc = subprocess.Popen([sys.executable, str(PROXY_SCRIPT), "--db", self.db, "--port", "0",
                                 *args], env=env or self.env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
        try:
            ready, _, _ = select.select([proc.stdout], [], [], 5)
            self.assertTrue(ready, "proxy did not print a startup line")
            return proc.stdout.readline()
        finally:
            proc.terminate()
            _, err = proc.communicate(timeout=5)
            self.assertNotIn(KEY, err)

    def test_refuses_non_loopback_host(self):
        result = self.run_cli("--host", "0.0.0.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("loopback", result.stderr)

    def test_meshy_mode_requires_key(self):
        result = self.run_cli("--upstream", "meshy")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MESHY_API_KEY", result.stderr)

    def test_startup_lines_never_print_the_key(self):
        line = self.first_line()
        self.assertIn("upstream=fake", line)
        self.assertIn("simulated", line)
        env = dict(self.env, MESHY_API_KEY=KEY, MESHY_API_BASE_URL="http://127.0.0.1:9")
        line = self.first_line("--upstream", "meshy", env=env)
        self.assertIn("upstream=meshy", line)
        self.assertNotIn(KEY, line)


if __name__ == "__main__":
    unittest.main()
