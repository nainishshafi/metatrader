"""Unit tests for zmq_server.py (mocking MetaTrader5 IPC)."""

from __future__ import annotations

import sys
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

_mock_mt5 = MagicMock()
_mock_mt5.ORDER_TYPE_BUY = 0
_mock_mt5.ORDER_TYPE_SELL = 1
_mock_mt5.TRADE_ACTION_DEAL = 1
_mock_mt5.ORDER_TIME_GTC = 0
_mock_mt5.ORDER_FILLING_IOC = 1
_mock_mt5.TRADE_RETCODE_DONE = 10009
sys.modules.setdefault("MetaTrader5", _mock_mt5)

import zmq_server  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_mt5(monkeypatch: pytest.MonkeyPatch) -> None:
    _mock_mt5.reset_mock()
    _mock_mt5.symbol_select.return_value = True
    monkeypatch.setattr(zmq_server, "ALLOW_LIVE_TRADING", False)
    monkeypatch.setattr(zmq_server, "MAX_LOT_SIZE", 1.0)


def test_dispatch_ping() -> None:
    assert zmq_server.dispatch_command({"action": "PING"}) == {"ok": True, "status": "pong"}


def test_dispatch_unknown_action() -> None:
    res = zmq_server.dispatch_command({"action": "NOOP"})
    assert res["ok"] is False
    assert "Unknown action" in res["error"]


def test_dispatch_order_send_dry_run() -> None:
    _mock_mt5.symbol_info_tick.return_value = SimpleNamespace(ask=1.1005, bid=1.1003)
    _mock_mt5.order_check.return_value = SimpleNamespace(
        retcode=_mock_mt5.TRADE_RETCODE_DONE, comment="Done"
    )

    res = zmq_server.dispatch_command(
        {"action": "ORDER_SEND", "symbol": "EURUSD", "side": "BUY", "volume": 0.1}
    )
    assert res["ok"] is True
    assert res["dry_run"] is True
    _mock_mt5.order_send.assert_not_called()


def test_dispatch_order_send_rejects_excess_volume() -> None:
    res = zmq_server.dispatch_command(
        {"action": "ORDER_SEND", "symbol": "EURUSD", "side": "BUY", "volume": 5.0}
    )
    assert res["ok"] is False
    assert "out of allowed range" in res["error"]


def test_dispatch_rejects_malformed_numeric_params() -> None:
    res = zmq_server.dispatch_command(
        {"action": "ORDER_SEND", "symbol": "EURUSD", "side": "BUY", "volume": "not-a-number"}
    )
    assert res["ok"] is False
    assert "Invalid request parameters" in res["error"]
