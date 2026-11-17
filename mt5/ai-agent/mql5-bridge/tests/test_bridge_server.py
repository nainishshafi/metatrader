"""Unit and HTTP integration tests for bridge_server.py."""

from __future__ import annotations

import http.client
import json
import threading
from pathlib import Path

import pytest

import bridge_server


def test_indicator_store_put_get_and_validation() -> None:
    store = bridge_server.IndicatorStore()
    with pytest.raises(ValueError, match="symbol"):
        store.put({"symbol": "", "timeframe": "H1"})
    with pytest.raises(ValueError, match="strings"):
        store.put({"symbol": None, "timeframe": "H1"})

    payload = {
        "indicator": "RSI",
        "symbol": "EURUSD",
        "timeframe": "H1",
        "period": 14,
        "latest": {"time": 1700000000, "close": 1.085, "rsi": 54.321},
        "values": [{"time": 1700000000, "close": 1.085, "rsi": 54.321}],
    }
    store.put(payload)
    assert store.get("eurusd", "h1") == payload
    assert store.list_keys() == [{"symbol": "EURUSD", "timeframe": "H1", "indicator": "RSI"}]


def test_read_indicator_file(tmp_path: Path) -> None:
    sample = {"indicator": "RSI", "symbol": "XAUUSD", "timeframe": "M15", "latest": {"rsi": 61.5}}
    fpath = tmp_path / "rsi_bridge_XAUUSD_M15.json"
    fpath.write_text(json.dumps(sample), encoding="utf-8")

    assert bridge_server.read_indicator_file(fpath) == sample
    with pytest.raises(FileNotFoundError):
        bridge_server.read_indicator_file(tmp_path / "missing.json")


def test_http_post_and_get_indicator() -> None:
    server, _ = bridge_server.create_server(host="127.0.0.1", port=0)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        payload = {
            "indicator": "RSI",
            "symbol": "EURUSD",
            "timeframe": "H1",
            "period": 14,
            "latest": {"time": 1700003600, "close": 1.09, "rsi": 58.12},
            "values": [{"time": 1700003600, "close": 1.09, "rsi": 58.12}],
        }
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        conn.request(
            "POST",
            "/indicator",
            body=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        post_resp = conn.getresponse()
        assert post_resp.status == 200
        assert json.loads(post_resp.read().decode("utf-8")) == {"ok": True}

        conn.request("GET", "/indicator?symbol=EURUSD&timeframe=H1")
        get_resp = conn.getresponse()
        assert get_resp.status == 200
        body = json.loads(get_resp.read().decode("utf-8"))
        assert body["ok"] is True
        assert body["data"]["latest"]["rsi"] == 58.12

        conn.request("GET", "/health")
        health_resp = conn.getresponse()
        assert health_resp.status == 200
        health = json.loads(health_resp.read().decode("utf-8"))
        assert health == {"ok": True, "available": [{"symbol": "EURUSD", "timeframe": "H1", "indicator": "RSI"}]}

        # Error-path checks: 400 on null symbol, invalid Content-Length, missing params; 404 on unknown symbol/route
        conn.request(
            "POST",
            "/indicator",
            body=json.dumps({"symbol": None, "timeframe": "H1"}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        assert conn.getresponse().status == 400

        conn.request(
            "POST",
            "/indicator",
            body=b"{}",
            headers={"Content-Type": "application/json", "Content-Length": "abc"},
        )
        assert conn.getresponse().status == 400

        conn.request(
            "POST",
            "/indicator",
            body=b"{",
            headers={"Content-Type": "application/json"},
        )
        assert conn.getresponse().status == 400

        conn.request(
            "POST",
            "/indicator",
            body=b"{}",
            headers={
                "Content-Type": "application/json",
                "Content-Length": str(bridge_server.MAX_BODY_BYTES + 1),
            },
        )
        assert conn.getresponse().status == 413

        conn.request("GET", "/indicator")
        assert conn.getresponse().status == 400

        conn.request("GET", "/indicator?symbol=GBPUSD&timeframe=H1")
        assert conn.getresponse().status == 404

        conn.request("GET", "/unknown")
        assert conn.getresponse().status == 404
        conn.close()
    finally:
        server.shutdown()
        server.server_close()


def test_indicator_store_sqlite_eav_heterogeneous_persistence(tmp_path: Path) -> None:
    import sqlite3

    db_file = tmp_path / "nested" / "bridge.sqlite"
    rsi_old = {"indicator": "RSI", "symbol": "XAUUSD", "timeframe": "M15", "latest": {"time": 1700000000, "rsi": 48.0}}
    rsi_new = {
        "indicator": "RSI",
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "period": 14,
        "latest": {"time": 1700000900, "rsi": 55.2},
        "values": [{"time": 1700000000, "rsi": 48.0}, {"time": 1700000900, "rsi": 55.2}],
    }
    hma_snap = {
        "indicator": "HMA",
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "ready": True,
        "trend": 1.0,
        "flip_candle": {"found": True, "bars_ago": 3, "hma_value": 2642.15},
    }
    fib_snap = {
        "indicator": "AutoFib",
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "channel_present": False,
        "levels": {"0.0": 2600.0, "61.8": 2661.8, "161.8": 2761.8},
    }

    store1 = bridge_server.IndicatorStore(db_path=db_file)
    try:
        store1.put(rsi_old)
        store1.put(rsi_new)
        store1.put(hma_snap)
        store1.put(fib_snap)
    finally:
        store1.close()

    assert db_file.is_file()

    # Verify pure relational EAV queryability directly in SQLite
    with sqlite3.connect(str(db_file)) as conn:
        rows = conn.execute(
            """
            SELECT s.symbol, s.timeframe, s.indicator, m.val_num
            FROM snapshots s
            JOIN snapshot_metrics m ON m.snapshot_id = s.id
            WHERE m.metric_key = 'latest.rsi' AND m.val_num > 50
            """
        ).fetchall()
        assert rows == [("XAUUSD", "M15", "RSI", 55.2)]

    store2 = bridge_server.IndicatorStore(db_path=db_file)
    try:
        assert store2.get("xauusd", "m15", indicator="RSI") == rsi_new
        assert store2.get("xauusd", "m15", indicator="hma") == hma_snap
        assert store2.get("xauusd", "m15", indicator="autofib") == fib_snap
        assert store2.list_keys() == [
            {"symbol": "XAUUSD", "timeframe": "M15", "indicator": "AUTOFIB"},
            {"symbol": "XAUUSD", "timeframe": "M15", "indicator": "HMA"},
            {"symbol": "XAUUSD", "timeframe": "M15", "indicator": "RSI"},
        ]
    finally:
        store2.close()


def test_http_post_and_get_with_sqlite(tmp_path: Path) -> None:
    db_file = tmp_path / "http_bridge.db"
    server1, store1 = bridge_server.create_server(host="127.0.0.1", port=0, db_path=db_file)
    port1 = server1.server_address[1]
    thread1 = threading.Thread(target=server1.serve_forever, daemon=True)
    thread1.start()

    payload = {
        "indicator": "RSI",
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "latest": {"time": 1700007200, "close": 2650.5, "rsi": 63.4},
    }
    try:
        conn = http.client.HTTPConnection("127.0.0.1", port1, timeout=3)
        conn.request(
            "POST",
            "/indicator",
            body=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        assert conn.getresponse().status == 200
        conn.close()
    finally:
        server1.shutdown()
        server1.server_close()
        store1.close()

    server2, store2 = bridge_server.create_server(host="127.0.0.1", port=0, db_path=db_file)
    port2 = server2.server_address[1]
    thread2 = threading.Thread(target=server2.serve_forever, daemon=True)
    thread2.start()
    try:
        conn = http.client.HTTPConnection("127.0.0.1", port2, timeout=3)
        conn.request("GET", "/indicator?symbol=XAUUSD&timeframe=M15")
        resp = conn.getresponse()
        assert resp.status == 200
        body = json.loads(resp.read().decode("utf-8"))
        assert body == {"ok": True, "data": payload}
        conn.close()
    finally:
        server2.shutdown()
        server2.server_close()
        store2.close()
