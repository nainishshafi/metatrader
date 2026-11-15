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
    assert store.list_keys() == [{"symbol": "EURUSD", "timeframe": "H1"}]


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
        assert health == {"ok": True, "available": [{"symbol": "EURUSD", "timeframe": "H1"}]}

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
