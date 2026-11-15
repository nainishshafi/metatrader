"""Unit tests for mcp_server.py (mocking MetaTrader5 IPC)."""

from __future__ import annotations

import sys
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

# Stub MetaTrader5 and mcp.server.fastmcp if not installed in the test environment
_mock_mt5 = MagicMock()
_mock_mt5.TIMEFRAME_M1 = 1
_mock_mt5.TIMEFRAME_M5 = 5
_mock_mt5.TIMEFRAME_M15 = 15
_mock_mt5.TIMEFRAME_M30 = 30
_mock_mt5.TIMEFRAME_H1 = 16385
_mock_mt5.TIMEFRAME_H4 = 16388
_mock_mt5.TIMEFRAME_D1 = 16408
_mock_mt5.TIMEFRAME_W1 = 32769
_mock_mt5.TIMEFRAME_MN1 = 49153
_mock_mt5.ORDER_TYPE_BUY = 0
_mock_mt5.ORDER_TYPE_SELL = 1
_mock_mt5.TRADE_ACTION_DEAL = 1
_mock_mt5.ORDER_TIME_GTC = 0
_mock_mt5.ORDER_FILLING_IOC = 1
_mock_mt5.TRADE_RETCODE_DONE = 10009
sys.modules.setdefault("MetaTrader5", _mock_mt5)

import mcp_server  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_mt5_mock(monkeypatch: pytest.MonkeyPatch) -> None:
    _mock_mt5.reset_mock()
    _mock_mt5.initialize.return_value = True
    _mock_mt5.symbol_select.return_value = True
    monkeypatch.setattr(mcp_server, "ALLOW_LIVE_TRADING", False)
    monkeypatch.setattr(mcp_server, "MAX_LOT_SIZE", 1.0)


def test_validate_order_params_rejects_invalid_inputs() -> None:
    with pytest.raises(ValueError, match="symbol"):
        mcp_server._validate_order_params("   ", "BUY", 0.1, 0.0, 0.0)

    with pytest.raises(ValueError, match="side"):
        mcp_server._validate_order_params("EURUSD", "HOLD", 0.1, 0.0, 0.0)

    with pytest.raises(ValueError, match="greater than 0"):
        mcp_server._validate_order_params("EURUSD", "BUY", 0.0, 0.0, 0.0)

    with pytest.raises(ValueError, match="MT5_MAX_LOT_SIZE"):
        mcp_server._validate_order_params("EURUSD", "BUY", 2.5, 0.0, 0.0)

    with pytest.raises(ValueError, match="sl and tp"):
        mcp_server._validate_order_params("EURUSD", "BUY", 0.1, -1.0, 0.0)


def test_place_market_order_dry_run_passes_order_check() -> None:
    _mock_mt5.symbol_info_tick.return_value = SimpleNamespace(ask=1.1005, bid=1.1003)
    _mock_mt5.order_check.return_value = SimpleNamespace(
        retcode=_mock_mt5.TRADE_RETCODE_DONE, comment="Done"
    )

    res = mcp_server.place_market_order("EURUSD", "buy", 0.1)
    assert res["ok"] is True
    assert res["dry_run"] is True
    _mock_mt5.order_send.assert_not_called()
    _mock_mt5.shutdown.assert_called_once()


def test_close_position_rejects_non_positive_ticket() -> None:
    with pytest.raises(ValueError, match="positive integer"):
        mcp_server.close_position(0)


def test_close_position_blocks_when_live_trading_disabled() -> None:
    res = mcp_server.close_position(12345)
    assert res["ok"] is False
    assert res["dry_run"] is True
