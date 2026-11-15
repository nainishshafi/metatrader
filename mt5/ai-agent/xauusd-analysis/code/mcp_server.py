"""Standalone MCP server exposing XAU/USD data exclusively from XauusdBridgeEA.mq5."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import MCPServer

DEFAULT_SYMBOL = os.getenv("XAUUSD_SYMBOL", "XAUUSD.p")
MAX_BRIDGE_FILE_BYTES = 1_048_576  # 1 MiB
VALID_TIMEFRAMES = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"}

mcp = MCPServer("xauusd-analysis-mcp")


def _find_bridge_file(symbol: str, timeframe: str) -> Path | None:
    appdata = os.getenv("APPDATA")
    if not appdata:
        return None
    terminals_dir = Path(appdata) / "MetaQuotes" / "Terminal"
    if not terminals_dir.is_dir():
        return None
    filename = f"xauusd_bridge_{symbol.strip()}_{timeframe.strip().upper()}.json"
    matches = sorted(
        terminals_dir.glob(f"*/MQL5/Files/{filename}"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    return matches[0] if matches else None


@mcp.tool()
def get_market_snapshot(
    symbol: str = DEFAULT_SYMBOL,
    timeframe: str = "M15",
    file_path: str = "",
) -> dict[str, Any]:
    """Read the MT5 snapshot (spot, HMA nrp, AutoFibAutoTrend, H4 CustomCandle) for any symbol from XauusdBridgeEA.mq5."""
    clean_symbol = symbol.strip()
    if not clean_symbol:
        raise ValueError("symbol must be a non-empty string")
    clean_tf = timeframe.strip().upper()
    if clean_tf not in VALID_TIMEFRAMES:
        raise ValueError(f"Unsupported timeframe '{timeframe}'. Use: {', '.join(sorted(VALID_TIMEFRAMES))}")

    target = Path(file_path) if file_path.strip() else _find_bridge_file(clean_symbol, clean_tf)
    if target is None or not target.is_file():
        return {
            "ok": False,
            "error": f"Bridge file not found for {clean_symbol} {clean_tf}. Attach XauusdBridgeEA.mq5 in MT5.",
        }
    if target.stat().st_size > MAX_BRIDGE_FILE_BYTES:
        raise ValueError(f"Bridge file exceeds {MAX_BRIDGE_FILE_BYTES} bytes")

    try:
        data = json.loads(target.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return {"ok": False, "error": f"Invalid bridge JSON in {target}: {exc}"}
    return {"ok": True, "file": str(target), "data": data}


@mcp.tool()
def get_xauusd_snapshot(
    symbol: str = DEFAULT_SYMBOL,
    timeframe: str = "M15",
    file_path: str = "",
) -> dict[str, Any]:
    """Backward-compatible alias for get_market_snapshot."""
    return get_market_snapshot(symbol=symbol, timeframe=timeframe, file_path=file_path)


@mcp.prompt()
def market_full_analysis_prompt(symbol: str = DEFAULT_SYMBOL, timeframe: str = "M15") -> str:
    """Prompt template for a full technical, macro, options, and sentiment report for any symbol."""
    return (
        f"Produce a comprehensive {symbol} ({timeframe}) analysis report:\n"
        f"1. Call `get_market_snapshot(symbol=\"{symbol}\", timeframe=\"{timeframe}\")` to read live MT5 spot, HMA nrp (with flip candle), AutoFibAutoTrend, and H4 CustomCandle.\n"
        "2. Search the web for 50-day/100-day moving averages, S1-S3/R1-R3 intraday levels, and decision bands.\n"
        "3. Search the web for Fed policy expectations, US 10Y yields, DXY, and upcoming GDP/PCE/CPI/ECI/PMI/central bank catalysts.\n"
        "4. Search the web for options expiries, call/put OI concentrations, and pin/magnet strikes.\n"
        "5. Search the web for retail & investor sentiment and client positioning.\n"
        "6. Present top-of-report BUY/SELL probabilities, a reachable levels table, and a driver breakdown."
    )


@mcp.prompt()
def xauusd_full_analysis_prompt(symbol: str = DEFAULT_SYMBOL) -> str:
    """Backward-compatible alias for market_full_analysis_prompt."""
    return market_full_analysis_prompt(symbol=symbol, timeframe="M15")


if __name__ == "__main__":
    mcp.run()
