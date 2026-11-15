"""Lightweight HTTP + file receiver for the MQL5 indicator bridge."""

from __future__ import annotations

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

DEFAULT_HOST = os.getenv("MQL5_BRIDGE_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.getenv("MQL5_BRIDGE_PORT", "8765"))
MAX_BODY_BYTES = 1_048_576  # 1 MiB


class IndicatorStore:
    """Thread-safe in-memory store for indicator snapshots pushed from MT5."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._snapshots: dict[tuple[str, str], dict[str, Any]] = {}

    def put(self, payload: dict[str, Any]) -> dict[str, Any]:
        raw_symbol = payload.get("symbol")
        raw_tf = payload.get("timeframe")
        if not isinstance(raw_symbol, str) or not isinstance(raw_tf, str):
            raise ValueError("'symbol' and 'timeframe' must be strings")
        symbol = raw_symbol.strip().upper()
        timeframe = raw_tf.strip().upper()
        if not symbol or not timeframe:
            raise ValueError("payload must include non-empty 'symbol' and 'timeframe'")
        with self._lock:
            self._snapshots[(symbol, timeframe)] = payload
        return payload

    def get(self, symbol: str, timeframe: str) -> dict[str, Any] | None:
        key = (symbol.strip().upper(), timeframe.strip().upper())
        with self._lock:
            return self._snapshots.get(key)

    def list_keys(self) -> list[dict[str, str]]:
        with self._lock:
            return [{"symbol": sym, "timeframe": tf} for sym, tf in sorted(self._snapshots)]


def read_indicator_file(path: str | Path) -> dict[str, Any]:
    """Load an indicator JSON snapshot written by RsiBridgeEA.mq5 to MQL5\\Files."""
    file_path = Path(path)
    if not file_path.is_file():
        raise FileNotFoundError(f"Indicator file not found: {file_path}")
    return json.loads(file_path.read_text(encoding="utf-8"))


def make_handler(store: IndicatorStore) -> type[BaseHTTPRequestHandler]:
    """Create an HTTP request handler bound to the given IndicatorStore."""

    class BridgeHandler(BaseHTTPRequestHandler):
        def _send_json(self, status: int, body: dict[str, Any]) -> None:
            raw = json.dumps(body).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            if parsed.path == "/health":
                self._send_json(200, {"ok": True, "available": store.list_keys()})
                return
            if parsed.path == "/indicator":
                qs = parse_qs(parsed.query)
                symbol = (qs.get("symbol") or [""])[0]
                timeframe = (qs.get("timeframe") or [""])[0]
                if not symbol or not timeframe:
                    self._send_json(400, {"ok": False, "error": "symbol and timeframe query params are required"})
                    return
                snap = store.get(symbol, timeframe)
                if snap is None:
                    self._send_json(404, {"ok": False, "error": f"No snapshot for {symbol.upper()} {timeframe.upper()}"})
                    return
                self._send_json(200, {"ok": True, "data": snap})
                return
            self._send_json(404, {"ok": False, "error": "Not found"})

        def do_POST(self) -> None:
            if urlparse(self.path).path != "/indicator":
                self._send_json(404, {"ok": False, "error": "Not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self._send_json(400, {"ok": False, "error": "Invalid Content-Length header"})
                return
            if length <= 0 or length > MAX_BODY_BYTES:
                status = 413 if length > MAX_BODY_BYTES else 400
                self._send_json(status, {"ok": False, "error": "Invalid or oversized request body"})
                return
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode("utf-8"))
                if not isinstance(payload, dict):
                    raise ValueError("JSON body must be an object")
                store.put(payload)
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                self._send_json(400, {"ok": False, "error": str(exc)})
                return
            self._send_json(200, {"ok": True})

        def log_message(self, format: str, *args: Any) -> None:
            return  # keep stdout/stderr clean

    return BridgeHandler


def create_server(
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    store: IndicatorStore | None = None,
) -> tuple[ThreadingHTTPServer, IndicatorStore]:
    """Instantiate the bridge HTTP server and its backing IndicatorStore."""
    active_store = store if store is not None else IndicatorStore()
    server = ThreadingHTTPServer((host, port), make_handler(active_store))
    return server, active_store


if __name__ == "__main__":
    srv, _ = create_server()
    print(f"MQL5 bridge server listening on http://{DEFAULT_HOST}:{DEFAULT_PORT}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.server_close()
