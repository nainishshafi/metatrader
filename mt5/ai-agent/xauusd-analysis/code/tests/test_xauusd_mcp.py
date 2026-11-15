"""Unit tests for xauusd-analysis/code/mcp_server.py."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import mcp_server


def test_get_xauusd_snapshot_reads_valid_file(tmp_path: Path) -> None:
    sample = {
        "symbol": "XAUUSD.p",
        "timeframe": "M15",
        "bid": 3882.0,
        "ask": 3882.15,
        "hma": {"period": 21, "value": 3880.12, "trend": 1.0},
        "autofib": {"present": True, "levels": {"61.8": 3874.5}},
    }
    fpath = tmp_path / "xauusd_bridge_XAUUSD.p_M15.json"
    fpath.write_text(json.dumps(sample), encoding="utf-8")

    res = mcp_server.get_xauusd_snapshot("XAUUSD.p", "M15", file_path=str(fpath))
    assert res["ok"] is True
    assert res["data"] == sample


def test_get_xauusd_snapshot_handles_missing_and_corrupt_files(tmp_path: Path) -> None:
    missing = mcp_server.get_xauusd_snapshot("XAUUSD.p", "M15", file_path=str(tmp_path / "missing.json"))
    assert missing["ok"] is False

    bad = tmp_path / "bad.json"
    bad.write_text("{not-json", encoding="utf-8")
    corrupt = mcp_server.get_xauusd_snapshot("XAUUSD.p", "M15", file_path=str(bad))
    assert corrupt["ok"] is False
    assert "Invalid bridge JSON" in corrupt["error"]


def test_get_xauusd_snapshot_rejects_invalid_inputs() -> None:
    with pytest.raises(ValueError, match="symbol"):
        mcp_server.get_xauusd_snapshot("   ", "M15")

    with pytest.raises(ValueError, match="Unsupported timeframe"):
        mcp_server.get_xauusd_snapshot("XAUUSD.p", "INVALID")


def test_get_xauusd_snapshot_preserves_h4_candle_fields(tmp_path: Path) -> None:
    sample = {
        "symbol": "XAUUSD.p",
        "timeframe": "M15",
        "bid": 3882.0,
        "ask": 3882.15,
        "hma": {
            "present": True,
            "period": 21,
            "value": 3874.19,
            "trend": 1.0,
            "candles_in_trend": 1,
            "flip_candle": {
                "found": True,
                "bars_ago": 0,
                "time": 1763222400,
                "hma_value": 3874.19,
                "open": 3877.26,
                "high": 3882.41,
                "low": 3875.55,
                "close": 3882.0,
            },
        },
        "autofib": {"present": True, "levels": {"61.8": 3891.3, "100.0": 3905.97, "161.8": 3929.72}},
        "h4_candle": {
            "present": True,
            "last_h4": {"time": 1763208000, "open": 3900.0, "high": 3905.97, "low": 3872.0, "close": 3878.5},
            "current_h4": {"time": 1763222400, "open": 3878.5, "high": 3883.0, "low": 3867.56, "close": 3882.0},
            "took_prev_low": True,
            "going_up": True,
            "bullish_sweep_reversal": True,
            "took_prev_high": False,
            "going_down": False,
            "bearish_sweep_reversal": False,
        },
    }
    fpath = tmp_path / "xauusd_bridge_XAUUSD.p_M15.json"
    fpath.write_text(json.dumps(sample), encoding="utf-8")

    res = mcp_server.get_xauusd_snapshot("XAUUSD.p", "M15", file_path=str(fpath))
    assert res["ok"] is True
    hma = res["data"]["hma"]
    assert hma["candles_in_trend"] == 1
    assert hma["flip_candle"]["bars_ago"] == 0
    h4 = res["data"]["h4_candle"]
    assert h4["present"] is True
    assert h4["last_h4"]["close"] == 3878.5
    assert h4["bullish_sweep_reversal"] is True
    assert h4["bearish_sweep_reversal"] is False
