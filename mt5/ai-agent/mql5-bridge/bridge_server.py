"""Lightweight HTTP + file receiver for the MQL5 indicator bridge."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

DEFAULT_HOST = os.getenv("MQL5_BRIDGE_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.getenv("MQL5_BRIDGE_PORT", "8765"))
DEFAULT_DB_PATH = os.getenv("MQL5_BRIDGE_DB") or None
DEFAULT_INDICATOR = "DEFAULT"
MAX_BODY_BYTES = 1_048_576  # 1 MiB


def _encode_key_segment(segment: str) -> str:
    return segment.replace("%", "%25").replace(".", "%2E").replace("[", "%5B").replace("]", "%5D")


def _decode_key_segment(segment: str) -> str:
    return segment.replace("%5D", "]").replace("%5B", "[").replace("%2E", ".").replace("%25", "%")


def _flatten_metrics(value: Any, prefix: str = "") -> list[tuple[str, str, float | None, str | None]]:
    """Flatten a nested dict/list indicator payload into EAV (key, type, num, text) rows."""
    rows: list[tuple[str, str, float | None, str | None]] = []
    if isinstance(value, dict):
        if not value and prefix:
            rows.append((prefix, "empty_dict", None, None))
            return rows
        for k, v in value.items():
            seg = _encode_key_segment(str(k))
            next_prefix = f"{prefix}.{seg}" if prefix else seg
            rows.extend(_flatten_metrics(v, next_prefix))
        return rows
    if isinstance(value, list):
        if not value and prefix:
            rows.append((prefix, "empty_list", None, None))
            return rows
        for idx, item in enumerate(value):
            next_prefix = f"{prefix}[{idx}]"
            rows.extend(_flatten_metrics(item, next_prefix))
        return rows
    if value is None:
        rows.append((prefix, "null", None, None))
    elif isinstance(value, bool):
        rows.append((prefix, "bool", 1.0 if value else 0.0, "true" if value else "false"))
    elif isinstance(value, int):
        rows.append((prefix, "int", float(value), None))
    elif isinstance(value, float):
        rows.append((prefix, "float", value, None))
    else:
        rows.append((prefix, "str", None, str(value)))
    return rows


def _parse_metric_path(metric_key: str) -> list[str | int]:
    """Parse an EAV metric_key back into dict keys (str) and list indices (int)."""
    tokens: list[str | int] = []
    for part in metric_key.split("."):
        if "[" not in part:
            tokens.append(_decode_key_segment(part))
            continue
        head, *brackets = part.split("[")
        if head:
            tokens.append(_decode_key_segment(head))
        for b in brackets:
            tokens.append(int(b.rstrip("]")))
    return tokens


def _cast_metric_value(val_type: str, val_num: float | None, val_text: str | None) -> Any:
    if val_type == "null":
        return None
    if val_type == "bool":
        return bool(val_num)
    if val_type == "int":
        return int(val_num) if val_num is not None else 0
    if val_type == "float":
        return float(val_num) if val_num is not None else 0.0
    if val_type == "empty_dict":
        return {}
    if val_type == "empty_list":
        return []
    return val_text if val_text is not None else ""


def _unflatten_metrics(rows: list[tuple[str, str, float | None, str | None]]) -> dict[str, Any]:
    """Reconstruct a nested indicator payload dict from EAV metric rows."""
    root: dict[str, Any] = {}
    for metric_key, val_type, val_num, val_text in rows:
        tokens = _parse_metric_path(metric_key)
        if not tokens:
            continue
        cur: Any = root
        for i, tok in enumerate(tokens[:-1]):
            nxt = tokens[i + 1]
            if isinstance(tok, int):
                while len(cur) <= tok:
                    cur.append([] if isinstance(nxt, int) else {})
                if cur[tok] is None:
                    cur[tok] = [] if isinstance(nxt, int) else {}
                cur = cur[tok]
            else:
                if tok not in cur:
                    cur[tok] = [] if isinstance(nxt, int) else {}
                cur = cur[tok]
        leaf = tokens[-1]
        val = _cast_metric_value(val_type, val_num, val_text)
        if isinstance(leaf, int):
            while len(cur) <= leaf:
                cur.append(None)
            cur[leaf] = val
        else:
            cur[leaf] = val
    return root


def _extract_bar_time(payload: dict[str, Any]) -> int | None:
    latest = payload.get("latest")
    candidate = latest.get("time") if isinstance(latest, dict) else payload.get("time")
    if isinstance(candidate, bool):
        return None
    if isinstance(candidate, (int, float)):
        return int(candidate)
    return None


class IndicatorStore:
    """Thread-safe store for indicator snapshots (in-memory or SQLite Envelope + EAV)."""

    def __init__(self, db_path: str | Path | None = None) -> None:
        self._lock = threading.Lock()
        self._snapshots: dict[tuple[str, str, str], dict[str, Any]] = {}
        self._conn: sqlite3.Connection | None = None

        if db_path is not None:
            db_str = str(db_path)
            if db_str != ":memory:":
                Path(db_str).parent.mkdir(parents=True, exist_ok=True)
            self._conn = sqlite3.connect(db_str, check_same_thread=False)
            self._conn.execute("PRAGMA foreign_keys = ON")
            self._init_db()
            self._load_from_db()

    def _init_db(self) -> None:
        assert self._conn is not None
        with self._conn:
            self._conn.execute(
                """
                CREATE TABLE IF NOT EXISTS snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    symbol TEXT NOT NULL,
                    timeframe TEXT NOT NULL,
                    indicator TEXT NOT NULL,
                    bar_time INTEGER,
                    updated_at TEXT NOT NULL,
                    UNIQUE (symbol, timeframe, indicator)
                )
                """
            )
            self._conn.execute(
                """
                CREATE TABLE IF NOT EXISTS snapshot_metrics (
                    snapshot_id INTEGER NOT NULL,
                    metric_key TEXT NOT NULL,
                    val_type TEXT NOT NULL,
                    val_num REAL,
                    val_text TEXT,
                    PRIMARY KEY (snapshot_id, metric_key),
                    FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
                )
                """
            )
            self._conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_snapshot_metrics_key ON snapshot_metrics(metric_key)"
            )

    def _load_from_db(self) -> None:
        assert self._conn is not None
        snaps = self._conn.execute(
            "SELECT id, symbol, timeframe, indicator FROM snapshots"
        ).fetchall()
        metric_rows = self._conn.execute(
            "SELECT snapshot_id, metric_key, val_type, val_num, val_text FROM snapshot_metrics ORDER BY snapshot_id, metric_key"
        ).fetchall()
        grouped: dict[int, list[tuple[str, str, float | None, str | None]]] = {}
        for snap_id, mkey, vtype, vnum, vtext in metric_rows:
            grouped.setdefault(snap_id, []).append((mkey, vtype, vnum, vtext))
        for snap_id, symbol, timeframe, indicator in snaps:
            self._snapshots[(symbol, timeframe, indicator)] = _unflatten_metrics(
                grouped.get(snap_id, [])
            )

    @staticmethod
    def _normalize_key(symbol: Any, timeframe: Any, indicator: Any = None) -> tuple[str, str, str]:
        if not isinstance(symbol, str) or not isinstance(timeframe, str):
            raise ValueError("'symbol' and 'timeframe' must be strings")
        sym = symbol.strip().upper()
        tf = timeframe.strip().upper()
        if not sym or not tf:
            raise ValueError("payload must include non-empty 'symbol' and 'timeframe'")
        if indicator is None:
            ind = DEFAULT_INDICATOR
        elif isinstance(indicator, str):
            ind = indicator.strip().upper() or DEFAULT_INDICATOR
        else:
            raise ValueError("'indicator' must be a string")
        return sym, tf, ind

    def put(self, payload: dict[str, Any]) -> dict[str, Any]:
        symbol, timeframe, indicator = self._normalize_key(
            payload.get("symbol"),
            payload.get("timeframe"),
            payload.get("indicator"),
        )
        with self._lock:
            if self._conn is not None:
                now_iso = datetime.now(timezone.utc).isoformat()
                bar_time = _extract_bar_time(payload)
                metrics = _flatten_metrics(payload)
                with self._conn:
                    self._conn.execute(
                        """
                        INSERT INTO snapshots (symbol, timeframe, indicator, bar_time, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(symbol, timeframe, indicator) DO UPDATE SET
                            bar_time = excluded.bar_time,
                            updated_at = excluded.updated_at
                        """,
                        (symbol, timeframe, indicator, bar_time, now_iso),
                    )
                    row = self._conn.execute(
                        "SELECT id FROM snapshots WHERE symbol = ? AND timeframe = ? AND indicator = ?",
                        (symbol, timeframe, indicator),
                    ).fetchone()
                    assert row is not None
                    snap_id = row[0]
                    self._conn.execute(
                        "DELETE FROM snapshot_metrics WHERE snapshot_id = ?",
                        (snap_id,),
                    )
                    self._conn.executemany(
                        """
                        INSERT INTO snapshot_metrics (snapshot_id, metric_key, val_type, val_num, val_text)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        [(snap_id, k, vt, vn, vx) for k, vt, vn, vx in metrics],
                    )
            self._snapshots[(symbol, timeframe, indicator)] = payload
        return payload

    def get(self, symbol: str, timeframe: str, indicator: str | None = None) -> dict[str, Any] | None:
        sym = symbol.strip().upper()
        tf = timeframe.strip().upper()
        with self._lock:
            if indicator is not None and indicator.strip():
                return self._snapshots.get((sym, tf, indicator.strip().upper()))
            if (sym, tf, DEFAULT_INDICATOR) in self._snapshots:
                return self._snapshots[(sym, tf, DEFAULT_INDICATOR)]
            for (s, t, _), snap in self._snapshots.items():
                if s == sym and t == tf:
                    return snap
            return None

    def list_keys(self) -> list[dict[str, str]]:
        with self._lock:
            return [
                {"symbol": sym, "timeframe": tf, "indicator": ind}
                for sym, tf, ind in sorted(self._snapshots)
            ]

    def close(self) -> None:
        """Close the backing SQLite connection if one is open."""
        with self._lock:
            if self._conn is not None:
                self._conn.close()
                self._conn = None


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
                indicator = (qs.get("indicator") or [None])[0]
                if not symbol or not timeframe:
                    self._send_json(400, {"ok": False, "error": "symbol and timeframe query params are required"})
                    return
                snap = store.get(symbol, timeframe, indicator=indicator)
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
    db_path: str | Path | None = None,
) -> tuple[ThreadingHTTPServer, IndicatorStore]:
    """Instantiate the bridge HTTP server and its backing IndicatorStore."""
    active_store = store if store is not None else IndicatorStore(db_path=db_path)
    server = ThreadingHTTPServer((host, port), make_handler(active_store))
    return server, active_store


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MQL5 indicator HTTP bridge server")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bind host (default: MQL5_BRIDGE_HOST or 127.0.0.1)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Bind port (default: MQL5_BRIDGE_PORT or 8765)")
    parser.add_argument(
        "--db",
        default=DEFAULT_DB_PATH,
        help="Optional SQLite database path for persistent indicator storage (default: MQL5_BRIDGE_DB or in-memory)",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    srv, active_store = create_server(host=args.host, port=args.port, db_path=args.db)
    storage_desc = f"SQLite ({args.db})" if args.db else "in-memory"
    print(f"MQL5 bridge server listening on http://{args.host}:{args.port} [{storage_desc}]")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
        active_store.close()
