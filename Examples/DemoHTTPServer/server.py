#!/usr/bin/env python3
"""Loopback demo server for IdentityFlow's HTTP provider contract.

This is intentionally independent from the Swift Wire types. It uses only Python's
standard library so serialization and URLSession behavior are exercised across a
real HTTP socket without adding an SDK runtime dependency.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import socket
import socketserver
import ssl
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse


MAX_EVIDENCE_BYTES = 3_000_000


def iso8601(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


@dataclass
class SessionRecord:
    token: str
    expires_at: datetime
    scenario: str
    approve_after_polls: int = 0
    consent_version: str | None = None
    evidence: dict[str, str] = field(default_factory=dict)
    digests: dict[str, str] = field(default_factory=dict)
    submission_key: str | None = None
    submission_payload: dict[str, str] | None = None
    reference: str | None = None
    cancelled: bool = False
    polls_since_submission: int = 0


class Store:
    def __init__(self, lose_submission_response_once: bool = False) -> None:
        self.lock = threading.Lock()
        self.sessions: dict[str, SessionRecord] = {}
        self.lose_submission_response_once = lose_submission_response_once
        self.did_lose_submission_response = False
        self.stats = {
            "consentWrites": 0,
            "evidenceRequests": 0,
            "evidenceWrites": 0,
            "submissionRequests": 0,
            "logicalSubmissions": 0,
            "lostSubmissionResponses": 0,
        }

    def create_session(self, payload: dict[str, Any]) -> tuple[str, SessionRecord]:
        scenario = payload.get("scenario", "approve")
        if scenario not in {"approve", "reject", "hold", "approveAfterPolls"}:
            raise ValueError("unsupportedScenario")
        lifetime = float(payload.get("lifetimeSeconds", 900))
        polls = int(payload.get("approveAfterPolls", 0))
        session_id = str(uuid.uuid4())
        record = SessionRecord(
            token=f"demo-{uuid.uuid4()}",
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=lifetime),
            scenario=scenario,
            approve_after_polls=max(0, polls),
        )
        self.sessions[session_id] = record
        return session_id, record

    @staticmethod
    def resolved_state(record: SessionRecord) -> str:
        if record.cancelled:
            return "cancelled"
        if record.submission_key is None:
            return "awaitingConsent" if record.consent_version is None else "awaitingEvidence"
        if record.scenario == "approve":
            return "approved"
        if record.scenario == "reject":
            return "rejected"
        if record.scenario == "approveAfterPolls":
            return "approved" if record.polls_since_submission >= record.approve_after_polls else "submitted"
        return "submitted"


class DemoHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], store: Store) -> None:
        self.store = store
        super().__init__(address, DemoHandler)

    def server_bind(self) -> None:
        # HTTPServer performs a reverse-DNS lookup while binding. That can stall an offline
        # developer machine for tens of seconds and is unnecessary for a loopback demo.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


class DemoHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "IdentityFlowDemo/0.1"
    sys_version = ""

    @property
    def store(self) -> Store:
        return self.server.store  # type: ignore[attr-defined,no-any-return]

    def log_message(self, format: str, *args: Any) -> None:
        return

    def read_body(self) -> bytes:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        return self.rfile.read(max(0, length))

    def read_json(self) -> dict[str, Any] | None:
        try:
            value = json.loads(self.read_body().decode("utf-8"))
            return value if isinstance(value, dict) else None
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

    def send_bytes(self, status: int, body: bytes = b"", content_type: str | None = None) -> None:
        self.send_response(status)
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def send_json(self, status: int, value: dict[str, Any]) -> None:
        self.send_bytes(
            status,
            json.dumps(value, separators=(",", ":")).encode("utf-8"),
            "application/json",
        )

    def send_error_code(self, status: int, code: str) -> None:
        self.send_json(status, {"code": code})

    def route(self) -> list[str]:
        return [part for part in urlparse(self.path).path.split("/") if part]

    def authorized_record(self, parts: list[str]) -> tuple[str, SessionRecord] | None:
        if len(parts) < 2 or parts[0] != "sessions":
            self.send_error_code(404, "notFound")
            return None
        session_id = parts[1]
        record = self.store.sessions.get(session_id)
        if record is None:
            self.send_error_code(404, "notFound")
            return None
        if self.headers.get("Authorization") != f"Bearer {record.token}":
            self.send_error_code(401, "unauthorized")
            return None
        return session_id, record

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parts = self.route()
        if parts == ["__test__", "stats"]:
            with self.store.lock:
                self.send_json(200, dict(self.store.stats))
            return
        if parts == ["__test__", "shutdown"]:
            self.send_bytes(204)
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return

        with self.store.lock:
            authorized = self.authorized_record(parts)
            if authorized is None:
                return
            _, record = authorized
            if len(parts) != 2:
                self.send_error_code(404, "notFound")
                return
            if datetime.now(timezone.utc) >= record.expires_at:
                state = "expired"
            else:
                if record.submission_key is not None:
                    record.polls_since_submission += 1
                state = self.store.resolved_state(record)
            self.send_json(
                200,
                {
                    "state": state,
                    "expiresAt": iso8601(record.expires_at),
                    "reference": record.reference,
                    "receivedEvidence": record.evidence,
                    "submissionKey": record.submission_key,
                },
            )

    def do_PUT(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parts = self.route()
        with self.store.lock:
            authorized = self.authorized_record(parts)
            if authorized is None:
                return
            _, record = authorized
            if datetime.now(timezone.utc) >= record.expires_at:
                self.send_error_code(410, "expired")
                return

            if len(parts) == 3 and parts[2] == "consent":
                payload = self.read_json()
                version = payload.get("disclosureVersion") if payload else None
                if not isinstance(version, str) or not version:
                    self.send_error_code(400, "malformedRequest")
                    return
                if record.consent_version not in {None, version}:
                    self.send_error_code(409, "consentConflict")
                    return
                if record.consent_version is None:
                    self.store.stats["consentWrites"] += 1
                record.consent_version = version
                self.send_bytes(204)
                return

            if len(parts) == 4 and parts[2] == "evidence" and parts[3] in {"front", "back"}:
                self.store.stats["evidenceRequests"] += 1
                if record.consent_version is None:
                    self.send_error_code(409, "consentRequired")
                    return
                if self.headers.get_content_type() != "image/jpeg":
                    self.send_error_code(415, "unsupportedMedia")
                    return
                body = self.read_body()
                if len(body) > MAX_EVIDENCE_BYTES:
                    self.send_error_code(413, "evidenceTooLarge")
                    return
                evidence_id = self.headers.get("X-Evidence-Id")
                digest = self.headers.get("X-Evidence-Digest")
                try:
                    normalized_id = str(uuid.UUID(evidence_id or ""))
                except ValueError:
                    self.send_error_code(400, "malformedRequest")
                    return
                if digest != hashlib.sha256(body).hexdigest():
                    self.send_error_code(400, "digestMismatch")
                    return
                side = parts[3]
                if record.evidence.get(side) == normalized_id:
                    if record.digests.get(side) != digest:
                        self.send_error_code(409, "digestConflict")
                        return
                    self.send_bytes(204)
                    return
                record.evidence[side] = normalized_id
                record.digests[side] = digest
                self.store.stats["evidenceWrites"] += 1
                self.send_bytes(204)
                return

            self.send_error_code(404, "notFound")

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parts = self.route()
        if parts == ["sessions"]:
            payload = self.read_json()
            if payload is None:
                self.send_error_code(400, "malformedRequest")
                return
            with self.store.lock:
                try:
                    session_id, record = self.store.create_session(payload)
                except (TypeError, ValueError):
                    self.send_error_code(400, "unsupportedScenario")
                    return
                self.send_json(
                    201,
                    {"id": session_id, "token": record.token, "expiresAt": iso8601(record.expires_at)},
                )
            return

        should_drop_response = False
        with self.store.lock:
            authorized = self.authorized_record(parts)
            if authorized is None:
                return
            _, record = authorized
            if datetime.now(timezone.utc) >= record.expires_at:
                self.send_error_code(410, "expired")
                return

            if len(parts) == 3 and parts[2] == "submission":
                self.store.stats["submissionRequests"] += 1
                payload = self.read_json()
                key = self.headers.get("Idempotency-Key")
                try:
                    normalized_key = str(uuid.UUID(key or ""))
                    front = str(uuid.UUID(str(payload["frontEvidenceID"]))) if payload else ""
                    back = str(uuid.UUID(str(payload["backEvidenceID"]))) if payload else ""
                except (KeyError, TypeError, ValueError):
                    self.send_error_code(400, "malformedRequest")
                    return
                normalized_payload = {"frontEvidenceID": front, "backEvidenceID": back}
                if record.evidence.get("front") != front or record.evidence.get("back") != back:
                    self.send_error_code(409, "evidenceIncomplete")
                    return
                if record.submission_key is not None:
                    if record.submission_key != normalized_key or record.submission_payload != normalized_payload:
                        self.send_error_code(409, "submissionConflict")
                        return
                else:
                    record.submission_key = normalized_key
                    record.submission_payload = normalized_payload
                    record.reference = f"demo-ref-{str(uuid.uuid4())[:8]}"
                    self.store.stats["logicalSubmissions"] += 1
                should_drop_response = (
                    self.store.lose_submission_response_once
                    and not self.store.did_lose_submission_response
                )
                if should_drop_response:
                    self.store.did_lose_submission_response = True
                    self.store.stats["lostSubmissionResponses"] += 1
                else:
                    self.send_json(
                        202,
                        {"reference": record.reference, "state": "submitted"},
                    )

            elif len(parts) == 3 and parts[2] == "cancel":
                record.cancelled = True
                self.send_bytes(204)
            else:
                self.send_error_code(404, "notFound")
                return

        if should_drop_response:
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.connection.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the IdentityFlow loopback demo HTTP server")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--lose-submission-response-once", action="store_true")
    parser.add_argument("--tls-cert", help="PEM certificate chain for optional local HTTPS")
    parser.add_argument("--tls-key", help="PEM private key for optional local HTTPS")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if bool(args.tls_cert) != bool(args.tls_key):
        raise SystemExit("--tls-cert and --tls-key must be supplied together")
    server = DemoHTTPServer(
        ("127.0.0.1", args.port),
        Store(lose_submission_response_once=args.lose_submission_response_once),
    )
    scheme = "http"
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    host, port = server.server_address[:2]
    print(json.dumps({"baseURL": f"{scheme}://{host}:{port}"}), flush=True)
    try:
        server.serve_forever(poll_interval=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
