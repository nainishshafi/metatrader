"""Unit tests for zmq_client.py (mocking pyzmq sockets)."""

from __future__ import annotations

import json
from unittest.mock import MagicMock

import pytest
import zmq

from zmq_client import ZmqBridgeError, ZmqMt5Client


def test_client_rejects_non_positive_timeout() -> None:
    with pytest.raises(ValueError, match="timeout_ms"):
        ZmqMt5Client(timeout_ms=0)


def test_request_returns_parsed_payload() -> None:
    client = ZmqMt5Client()
    mock_sock = MagicMock()
    mock_sock.recv_string.return_value = json.dumps({"ok": True, "status": "pong"})
    client._req = mock_sock

    res = client.ping()
    assert res == {"ok": True, "status": "pong"}
    mock_sock.send_string.assert_called_once_with(json.dumps({"action": "PING"}))


def test_request_raises_on_invalid_json() -> None:
    client = ZmqMt5Client()
    mock_sock = MagicMock()
    mock_sock.recv_string.return_value = "{not-json"
    client._req = mock_sock

    with pytest.raises(ZmqBridgeError, match="Invalid JSON"):
        client.ping()


def test_request_resets_socket_on_timeout() -> None:
    client = ZmqMt5Client(timeout_ms=100)
    mock_sock = MagicMock()
    mock_sock.recv_string.side_effect = zmq.Again()
    client._req = mock_sock

    with pytest.raises(ZmqBridgeError, match="Timeout"):
        client.ping()

    mock_sock.close.assert_called_once_with(linger=0)
    assert client._req is None
