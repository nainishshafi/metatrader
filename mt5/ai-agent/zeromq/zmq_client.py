"""Standalone ZeroMQ client bridge for communicating with MetaTrader 5 (ZmqBridgeEA.mq5)."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Iterator

import zmq
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().with_name(".env"))

DEFAULT_CMD_ENDPOINT = os.getenv("ZMQ_CMD_ENDPOINT", "tcp://127.0.0.1:5555")
DEFAULT_TICK_ENDPOINT = os.getenv("ZMQ_TICK_ENDPOINT", "tcp://127.0.0.1:5556")
DEFAULT_TIMEOUT_MS = int(os.getenv("ZMQ_TIMEOUT_MS", "5000"))


class ZmqBridgeError(RuntimeError):
    """Raised when the ZeroMQ bridge fails or returns an error payload."""


class ZmqMt5Client:
    """Synchronous REQ/REP + PUB/SUB ZeroMQ client for ZmqBridgeEA.mq5."""

    def __init__(
        self,
        cmd_endpoint: str = DEFAULT_CMD_ENDPOINT,
        tick_endpoint: str = DEFAULT_TICK_ENDPOINT,
        timeout_ms: int = DEFAULT_TIMEOUT_MS,
    ) -> None:
        if timeout_ms <= 0:
            raise ValueError("timeout_ms must be greater than 0")
        self.cmd_endpoint = cmd_endpoint
        self.tick_endpoint = tick_endpoint
        self.timeout_ms = timeout_ms
        self._ctx = zmq.Context.instance()
        self._req: zmq.Socket | None = None

    def _ensure_req(self) -> zmq.Socket:
        if self._req is not None:
            return self._req
        sock = self._ctx.socket(zmq.REQ)
        sock.setsockopt(zmq.LINGER, 0)
        sock.setsockopt(zmq.RCVTIMEO, self.timeout_ms)
        sock.setsockopt(zmq.SNDTIMEO, self.timeout_ms)
        sock.connect(self.cmd_endpoint)
        self._req = sock
        return sock

    def _reset_req(self) -> None:
        if self._req is not None:
            self._req.close(linger=0)
            self._req = None

    def request(self, action: str, **params: Any) -> dict[str, Any]:
        """Send a JSON command to the MT5 ZeroMQ EA and return the parsed response."""
        payload = {"action": action, **params}
        sock = self._ensure_req()
        try:
            sock.send_string(json.dumps(payload))
            raw = sock.recv_string()
        except zmq.Again as exc:
            # REQ socket must be recreated after a send/recv timeout
            self._reset_req()
            raise ZmqBridgeError(
                f"Timeout ({self.timeout_ms}ms) waiting for MT5 ZMQ EA at {self.cmd_endpoint}"
            ) from exc
        except zmq.ZMQError as exc:
            self._reset_req()
            raise ZmqBridgeError(f"ZeroMQ communication error: {exc}") from exc

        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ZmqBridgeError(f"Invalid JSON response from MT5 ZMQ EA: {raw!r}") from exc

        if not data.get("ok", False):
            raise ZmqBridgeError(data.get("error", "Unknown error from MT5 ZMQ EA"))
        return data

    def ping(self) -> dict[str, Any]:
        return self.request("PING")

    def get_account_info(self) -> dict[str, Any]:
        return self.request("ACCOUNT_INFO")

    def get_tick(self, symbol: str) -> dict[str, Any]:
        return self.request("TICK", symbol=symbol)

    def get_positions(self, symbol: str | None = None) -> dict[str, Any]:
        params = {"symbol": symbol} if symbol else {}
        return self.request("POSITIONS", **params)

    def send_market_order(
        self,
        symbol: str,
        side: str,
        volume: float,
        sl: float = 0.0,
        tp: float = 0.0,
        comment: str = "ZMQ-Agent",
    ) -> dict[str, Any]:
        return self.request(
            "ORDER_SEND",
            symbol=symbol,
            side=side.upper(),
            volume=float(volume),
            sl=float(sl),
            tp=float(tp),
            comment=comment,
        )

    def close_position(self, ticket: int) -> dict[str, Any]:
        return self.request("CLOSE_POSITION", ticket=int(ticket))

    def stream_ticks(self, symbol: str = "") -> Iterator[dict[str, Any]]:
        """Yield live tick dictionaries published by ZmqBridgeEA.mq5."""
        sub = self._ctx.socket(zmq.SUB)
        sub.setsockopt(zmq.LINGER, 0)
        sub.setsockopt_string(zmq.SUBSCRIBE, symbol)
        sub.connect(self.tick_endpoint)
        try:
            while True:
                msg = sub.recv_string()
                _, _, json_part = msg.partition(" ")
                if json_part:
                    yield json.loads(json_part)
        finally:
            sub.close(linger=0)

    def close(self) -> None:
        self._reset_req()

    def __enter__(self) -> "ZmqMt5Client":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="MT5 ZeroMQ Bridge CLI")
    parser.add_argument("--ping", action="store_true", help="Ping the MT5 ZMQ EA")
    parser.add_argument("--account", action="store_true", help="Fetch account info")
    parser.add_argument("--positions", action="store_true", help="Fetch open positions")
    parser.add_argument("--stream", metavar="SYMBOL", help="Stream live ticks ('' for all)")
    args = parser.parse_args()

    with ZmqMt5Client() as client:
        if args.ping:
            print(json.dumps(client.ping(), indent=2))
        if args.account:
            print(json.dumps(client.get_account_info(), indent=2))
        if args.positions:
            print(json.dumps(client.get_positions(), indent=2))
        if args.stream is not None:
            print(f"Streaming ticks from {client.tick_endpoint} (Ctrl+C to stop)...")
            try:
                for tick in client.stream_ticks(args.stream):
                    print(json.dumps(tick))
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
