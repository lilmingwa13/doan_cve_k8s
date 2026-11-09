"""Local-only credential observer used by the Kubernetes lab.

It accepts only ``LAB_GITHUB_*`` fixture credentials.  The raw bearer value is
used transiently to calculate a fingerprint and is never logged, returned, or
persisted.  This lets the report prove which synthetic credential reached the
receiving in-cluster component without leaking any real secret.
"""

from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
import time


EVENTS: list[dict] = []
MAX_EVENTS = 50


def hash20(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:20]


def actor(value: str) -> str:
    parts = value.split("_")
    if len(parts) >= 3 and parts[0] == "LAB" and parts[2] in {"A", "B"}:
        return parts[2]
    return "unknown"


class Handler(BaseHTTPRequestHandler):
    server_version = "GitHubCredentialSink/1.0"

    def log_message(self, _format: str, *_args) -> None:
        # Do not let BaseHTTPRequestHandler emit request headers or bodies.
        return

    def send_json(self, status: int, body: dict) -> None:
        encoded = json.dumps(body, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:
        if self.path == "/healthz":
            self.send_json(HTTPStatus.OK, {"status": "ok", "service": "github-credential-sink", "events": len(EVENTS)})
            return
        if self.path == "/events":
            self.send_json(HTTPStatus.OK, {"count": len(EVENTS), "events": EVENTS})
            return
        self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/observe":
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length < 1 or length > 16_384:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid body length"})
            return
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid JSON"})
            return

        authorization = self.headers.get("Authorization", "")
        token = authorization.removeprefix("Bearer ").strip()
        if not token.startswith("LAB_GITHUB_"):
            self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "only LAB_GITHUB_* synthetic credentials are accepted"})
            return

        requester = str(body.get("requesterSession", "unknown"))
        token_owner = actor(token)
        record = {
            "eventId": str(body.get("eventId", "")),
            "observedAtUnix": int(time.time()),
            "requesterSession": requester,
            "credentialOwner": token_owner,
            "credentialSha256_20": hash20(token),
            "credentialSource": str(body.get("credentialSource", "unknown")),
            "repository": str(body.get("repository", "")),
            "querySha256_20": str(body.get("querySha256_20", "")),
            "labMode": str(body.get("labMode", "")),
            "receiver": "github-credential-sink",
            "crossSessionCredentialUse": requester in {"A", "B"} and token_owner in {"A", "B"} and requester != token_owner,
        }
        EVENTS.append(record)
        del EVENTS[:-MAX_EVENTS]
        self.send_json(HTTPStatus.CREATED, record)


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
