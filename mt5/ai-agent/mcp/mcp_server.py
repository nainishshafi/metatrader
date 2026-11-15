"""Standalone FastMCP server exposing MetaTrader 5 via the official Python package."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import MetaTrader5 as mt5
from dotenv import load_dotenv
from mcp.server.mcpserver import MCPServer

load_dotenv(Path(__file__).resolve().with_name(".env"))


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


DEFAULT_MAGIC = int(os.getenv("MT5_DEFAULT_MAGIC", "202611"))
MAX_LOT_SIZE = float(os.getenv("MT5_MAX_LOT_SIZE", "1.0"))
DEFAULT_DEVIATION = int(os.getenv("MT5_DEFAULT_DEVIATION", "20"))
ALLOW_LIVE_TRADING = _env_bool("MT5_ALLOW_LIVE_TRADING", False)

mcp = MCPServer("mt5-mcp-server")

_TIMEFRAME_MAP = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
    "W1": mt5.TIMEFRAME_W1,
    "MN1": mt5.TIMEFRAME_MN1,
}


def _init_mt5() -> None:
    if not mt5.initialize():
        raise RuntimeError(f"MetaTrader5 initialize() failed: {mt5.last_error()}")


def _validate_order_params(symbol: str, side: str, volume: float, sl: float, tp: float) -> tuple[str, str]:
    clean_symbol = symbol.strip()
    if not clean_symbol:
        raise ValueError("symbol must be a non-empty string")
    norm_side = side.strip().upper()
    if norm_side not in {"BUY", "SELL"}:
        raise ValueError("side must be 'BUY' or 'SELL'")
    if volume <= 0:
        raise ValueError("volume must be greater than 0")
    if volume > MAX_LOT_SIZE:
        raise ValueError(f"volume {volume} exceeds MT5_MAX_LOT_SIZE ({MAX_LOT_SIZE})")
    if sl < 0 or tp < 0:
        raise ValueError("sl and tp must be >= 0")
    return clean_symbol, norm_side


# ---------------------------------------------------------------------------
# MCP Resources
# ---------------------------------------------------------------------------


@mcp.resource("mt5://account/summary")
def resource_account_summary() -> str:
    """Current MetaTrader 5 account summary as JSON."""
    return json.dumps(get_account_info(), indent=2)


@mcp.resource("mt5://positions/open")
def resource_open_positions() -> str:
    """Currently open MetaTrader 5 positions as JSON."""
    return json.dumps(get_open_positions(), indent=2)


# ---------------------------------------------------------------------------
# MCP Tools
# ---------------------------------------------------------------------------


@mcp.tool()
def get_account_info() -> dict[str, Any]:
    """Retrieve MetaTrader 5 account balance, equity, margin, and leverage."""
    _init_mt5()
    try:
        info = mt5.account_info()
        if info is None:
            raise RuntimeError(f"account_info() failed: {mt5.last_error()}")
        return info._asdict()
    finally:
        mt5.shutdown()


@mcp.tool()
def get_symbol_tick(symbol: str) -> dict[str, Any]:
    """Get the latest bid/ask/last tick for a trading symbol (e.g., EURUSD)."""
    _init_mt5()
    try:
        if not mt5.symbol_select(symbol, True):
            raise RuntimeError(f"Failed to select symbol {symbol}: {mt5.last_error()}")
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            raise RuntimeError(f"symbol_info_tick({symbol}) failed: {mt5.last_error()}")
        return tick._asdict()
    finally:
        mt5.shutdown()


@mcp.tool()
def get_rates(symbol: str, timeframe: str = "H1", count: int = 50) -> list[dict[str, Any]]:
    """Fetch recent OHLCV bars for a symbol."""
    if count <= 0 or count > 5000:
        raise ValueError("count must be between 1 and 5000")
    tf_val = _TIMEFRAME_MAP.get(timeframe.upper())
    if tf_val is None:
        raise ValueError(f"Unsupported timeframe '{timeframe}'. Use: {', '.join(_TIMEFRAME_MAP)}")

    _init_mt5()
    try:
        rates = mt5.copy_rates_from_pos(symbol, tf_val, 0, count)
        if rates is None:
            raise RuntimeError(f"copy_rates_from_pos failed: {mt5.last_error()}")
        return [
            {
                "time": int(r["time"]),
                "open": float(r["open"]),
                "high": float(r["high"]),
                "low": float(r["low"]),
                "close": float(r["close"]),
                "tick_volume": int(r["tick_volume"]),
            }
            for r in rates
        ]
    finally:
        mt5.shutdown()


@mcp.tool()
def get_open_positions(symbol: str | None = None) -> list[dict[str, Any]]:
    """List open MetaTrader 5 positions, optionally filtered by symbol."""
    _init_mt5()
    try:
        positions = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
        if positions is None:
            return []
        return [p._asdict() for p in positions]
    finally:
        mt5.shutdown()


@mcp.tool()
def place_market_order(
    symbol: str,
    side: str,
    volume: float,
    sl: float = 0.0,
    tp: float = 0.0,
    comment: str = "MCP-Agent",
) -> dict[str, Any]:
    """Place a BUY or SELL market order with MT5_MAX_LOT_SIZE and MT5_ALLOW_LIVE_TRADING guardrails."""
    norm_symbol, norm_side = _validate_order_params(symbol, side, volume, sl, tp)
    _init_mt5()
    try:
        if not mt5.symbol_select(norm_symbol, True):
            raise RuntimeError(f"Failed to select symbol {norm_symbol}: {mt5.last_error()}")
        tick = mt5.symbol_info_tick(norm_symbol)
        if tick is None:
            raise RuntimeError(f"No tick available for {norm_symbol}")

        order_type = mt5.ORDER_TYPE_BUY if norm_side == "BUY" else mt5.ORDER_TYPE_SELL
        price = tick.ask if norm_side == "BUY" else tick.bid

        request: dict[str, Any] = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": norm_symbol,
            "volume": float(volume),
            "type": order_type,
            "price": float(price),
            "deviation": DEFAULT_DEVIATION,
            "magic": DEFAULT_MAGIC,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        if sl > 0:
            request["sl"] = float(sl)
        if tp > 0:
            request["tp"] = float(tp)

        check = mt5.order_check(request)
        if check is None or check.retcode != mt5.TRADE_RETCODE_DONE:
            msg = check.comment if check else str(mt5.last_error())
            code = check.retcode if check else -1
            return {"ok": False, "stage": "order_check", "retcode": code, "error": msg}

        if not ALLOW_LIVE_TRADING:
            return {
                "ok": True,
                "dry_run": True,
                "message": "MT5_ALLOW_LIVE_TRADING is false; order_check passed without execution.",
                "request": request,
            }

        res = mt5.order_send(request)
        if res is None or res.retcode != mt5.TRADE_RETCODE_DONE:
            msg = res.comment if res else str(mt5.last_error())
            code = res.retcode if res else -1
            return {"ok": False, "stage": "order_send", "retcode": code, "error": msg}

        return {
            "ok": True,
            "dry_run": False,
            "order": res.order,
            "deal": res.deal,
            "price": res.price,
            "volume": res.volume,
        }
    finally:
        mt5.shutdown()


@mcp.tool()
def close_position(ticket: int) -> dict[str, Any]:
    """Close an open MetaTrader 5 position by ticket number."""
    if ticket <= 0:
        raise ValueError("ticket must be a positive integer")
    if not ALLOW_LIVE_TRADING:
        return {
            "ok": False,
            "dry_run": True,
            "error": "MT5_ALLOW_LIVE_TRADING is false; refusing to close position.",
        }

    _init_mt5()
    try:
        positions = mt5.positions_get(ticket=ticket)
        if not positions:
            return {"ok": False, "error": f"Position {ticket} not found"}
        pos = positions[0]
        tick = mt5.symbol_info_tick(pos.symbol)
        if tick is None:
            return {"ok": False, "error": f"No tick for {pos.symbol}"}

        close_type = mt5.ORDER_TYPE_SELL if pos.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
        price = tick.bid if pos.type == mt5.ORDER_TYPE_BUY else tick.ask
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": pos.symbol,
            "volume": pos.volume,
            "type": close_type,
            "position": pos.ticket,
            "price": price,
            "deviation": DEFAULT_DEVIATION,
            "magic": DEFAULT_MAGIC,
            "comment": "MCP-Close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        res = mt5.order_send(request)
        if res is None or res.retcode != mt5.TRADE_RETCODE_DONE:
            msg = res.comment if res else str(mt5.last_error())
            return {"ok": False, "error": msg}
        return {"ok": True, "ticket": ticket, "deal": res.deal, "price": res.price}
    finally:
        mt5.shutdown()


# ---------------------------------------------------------------------------
# MCP Prompts
# ---------------------------------------------------------------------------


@mcp.prompt()
def risk_audit_prompt(max_risk_percent: float = 2.0) -> str:
    """Template instructing the AI agent to audit open MT5 risk exposure."""
    return (
        "Inspect the current MetaTrader 5 account summary and all open positions. "
        f"Check whether any single position risks more than {max_risk_percent}% of equity, "
        "flag any positions missing a stop-loss, and summarize net exposure by symbol."
    )


if __name__ == "__main__":
    mcp.run()
