"""Pure-Python ZeroMQ REP/PUB server bridging MetaTrader 5 IPC to remote/external agents."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

import MetaTrader5 as mt5
import zmq
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().with_name(".env"))


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


CMD_ENDPOINT = os.getenv("ZMQ_CMD_ENDPOINT", "tcp://127.0.0.1:5555")
TICK_ENDPOINT = os.getenv("ZMQ_TICK_ENDPOINT", "tcp://127.0.0.1:5556")
POLL_INTERVAL_MS = int(os.getenv("ZMQ_POLL_INTERVAL_MS", "50"))
PUB_SYMBOLS = [s.strip() for s in os.getenv("ZMQ_PUB_SYMBOLS", "EURUSD").split(",") if s.strip()]

DEFAULT_MAGIC = int(os.getenv("MT5_DEFAULT_MAGIC", "202611"))
MAX_LOT_SIZE = float(os.getenv("MT5_MAX_LOT_SIZE", "1.0"))
DEFAULT_DEVIATION = int(os.getenv("MT5_DEFAULT_DEVIATION", "20"))
ALLOW_LIVE_TRADING = _env_bool("MT5_ALLOW_LIVE_TRADING", False)


def _ok(**data: Any) -> dict[str, Any]:
    return {"ok": True, **data}


def _err(message: str) -> dict[str, Any]:
    return {"ok": False, "error": message}


def _handle_account_info() -> dict[str, Any]:
    info = mt5.account_info()
    if info is None:
        return _err(f"account_info() failed: {mt5.last_error()}")
    return _ok(**info._asdict())


def _handle_tick(symbol: str) -> dict[str, Any]:
    sym = symbol.strip()
    if not sym:
        return _err("symbol must be a non-empty string")
    if not mt5.symbol_select(sym, True):
        return _err(f"Failed to select symbol {sym}: {mt5.last_error()}")
    tick = mt5.symbol_info_tick(sym)
    if tick is None:
        return _err(f"symbol_info_tick({sym}) failed: {mt5.last_error()}")
    return _ok(symbol=sym, **tick._asdict())


def _handle_positions(symbol: str | None) -> dict[str, Any]:
    positions = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
    items = [p._asdict() for p in positions] if positions else []
    return _ok(count=len(items), positions=items)


def _handle_order_send(req: dict[str, Any]) -> dict[str, Any]:
    symbol = str(req.get("symbol", "")).strip()
    side = str(req.get("side", "")).strip().upper()
    volume = float(req.get("volume", 0.0))
    sl = float(req.get("sl", 0.0))
    tp = float(req.get("tp", 0.0))
    comment = str(req.get("comment", "ZMQ-Agent"))

    if not symbol:
        return _err("symbol must be a non-empty string")
    if side not in {"BUY", "SELL"}:
        return _err("side must be BUY or SELL")
    if volume <= 0 or volume > MAX_LOT_SIZE:
        return _err(f"volume {volume} out of allowed range (0, {MAX_LOT_SIZE}]")
    if sl < 0 or tp < 0:
        return _err("sl and tp must be >= 0")

    if not mt5.symbol_select(symbol, True):
        return _err(f"Failed to select symbol {symbol}: {mt5.last_error()}")
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return _err(f"No tick available for {symbol}")

    order_type = mt5.ORDER_TYPE_BUY if side == "BUY" else mt5.ORDER_TYPE_SELL
    price = tick.ask if side == "BUY" else tick.bid

    mt5_req: dict[str, Any] = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": volume,
        "type": order_type,
        "price": float(price),
        "deviation": DEFAULT_DEVIATION,
        "magic": DEFAULT_MAGIC,
        "comment": comment,
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    if sl > 0:
        mt5_req["sl"] = sl
    if tp > 0:
        mt5_req["tp"] = tp

    check = mt5.order_check(mt5_req)
    if check is None or check.retcode != mt5.TRADE_RETCODE_DONE:
        msg = check.comment if check else str(mt5.last_error())
        return _err(f"order_check failed: {msg}")

    if not ALLOW_LIVE_TRADING:
        return _ok(
            dry_run=True,
            message="MT5_ALLOW_LIVE_TRADING is false; order_check passed without execution.",
            request=mt5_req,
        )

    res = mt5.order_send(mt5_req)
    if res is None or res.retcode != mt5.TRADE_RETCODE_DONE:
        msg = res.comment if res else str(mt5.last_error())
        return _err(f"order_send failed: {msg}")

    return _ok(dry_run=False, order=res.order, deal=res.deal, price=res.price, volume=res.volume)


def _handle_close_position(req: dict[str, Any]) -> dict[str, Any]:
    ticket = int(req.get("ticket", 0))
    if ticket <= 0:
        return _err("ticket must be a positive integer")
    if not ALLOW_LIVE_TRADING:
        return _err("MT5_ALLOW_LIVE_TRADING is false; refusing to close position.")

    positions = mt5.positions_get(ticket=ticket)
    if not positions:
        return _err(f"Position {ticket} not found")
    pos = positions[0]
    tick = mt5.symbol_info_tick(pos.symbol)
    if tick is None:
        return _err(f"No tick for {pos.symbol}")

    close_type = mt5.ORDER_TYPE_SELL if pos.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
    price = tick.bid if pos.type == mt5.ORDER_TYPE_BUY else tick.ask
    mt5_req = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": pos.symbol,
        "volume": pos.volume,
        "type": close_type,
        "position": pos.ticket,
        "price": price,
        "deviation": DEFAULT_DEVIATION,
        "magic": DEFAULT_MAGIC,
        "comment": "ZMQ-Close",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    res = mt5.order_send(mt5_req)
    if res is None or res.retcode != mt5.TRADE_RETCODE_DONE:
        msg = res.comment if res else str(mt5.last_error())
        return _err(f"close failed: {msg}")
    return _ok(ticket=ticket, deal=res.deal, price=res.price)


def dispatch_command(req: dict[str, Any]) -> dict[str, Any]:
    """Dispatch a parsed JSON command dictionary to MetaTrader 5."""
    action = str(req.get("action", "")).strip().upper()
    try:
        if action == "PING":
            return _ok(status="pong")
        if action == "ACCOUNT_INFO":
            return _handle_account_info()
        if action == "TICK":
            return _handle_tick(str(req.get("symbol", "")))
        if action == "POSITIONS":
            sym = req.get("symbol")
            return _handle_positions(str(sym) if sym else None)
        if action == "ORDER_SEND":
            return _handle_order_send(req)
        if action == "CLOSE_POSITION":
            return _handle_close_position(req)
    except (ValueError, TypeError) as exc:
        return _err(f"Invalid request parameters: {exc}")
    return _err(f"Unknown action: {action}")


def run_server() -> None:
    """Bind REP and PUB sockets and serve MT5 over ZeroMQ until interrupted."""
    if not mt5.initialize():
        raise RuntimeError(f"MetaTrader5 initialize() failed: {mt5.last_error()}")

    ctx = zmq.Context.instance()
    rep = ctx.socket(zmq.REP)
    pub = ctx.socket(zmq.PUB)
    rep.setsockopt(zmq.LINGER, 0)
    pub.setsockopt(zmq.LINGER, 0)
    rep.bind(CMD_ENDPOINT)
    pub.bind(TICK_ENDPOINT)

    poller = zmq.Poller()
    poller.register(rep, zmq.POLLIN)
    last_tick_times: dict[str, int] = {}

    print(f"MT5 ZeroMQ server running. REP={CMD_ENDPOINT} PUB={TICK_ENDPOINT}")
    try:
        while True:
            events = dict(poller.poll(max(10, POLL_INTERVAL_MS)))
            if rep in events:
                raw = rep.recv_string()
                try:
                    req = json.loads(raw)
                    resp = dispatch_command(req)
                except json.JSONDecodeError as exc:
                    resp = _err(f"Invalid JSON request: {exc}")
                rep.send_string(json.dumps(resp))

            for sym in PUB_SYMBOLS:
                tick = mt5.symbol_info_tick(sym)
                if tick is None:
                    continue
                if last_tick_times.get(sym) == tick.time_msc:
                    continue
                last_tick_times[sym] = tick.time_msc
                payload = json.dumps(
                    {"symbol": sym, "bid": tick.bid, "ask": tick.ask, "time": tick.time}
                )
                try:
                    pub.send_string(f"{sym} {payload}", flags=zmq.NOBLOCK)
                except zmq.Again:
                    pass
    except KeyboardInterrupt:
        pass
    finally:
        rep.close(linger=0)
        pub.close(linger=0)
        mt5.shutdown()
        time.sleep(0.05)


if __name__ == "__main__":
    run_server()
