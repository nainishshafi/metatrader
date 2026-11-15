# MetaTrader 5 AI Agent & Model Integration Concepts

This guide explains the core architectural patterns and concepts for connecting AI agents, Large Language Models (LLMs), and machine learning models to MetaTrader 5 (MT5).

---

## 1. Core Architectural Challenge

MetaTrader 5 is a Windows desktop trading terminal whose native automation language (MQL5) runs inside the terminal's sandboxed event loop. External AI agents and LLMs typically run either:
* In external desktop/IDE clients or Python processes, or
* On remote Linux/cloud servers.

Integrating AI with MT5 therefore requires choosing **where the model lives** and **which communication boundary** connects it to market data, account state, and order execution.

---

## 2. Integration Patterns

### 2.1 Model Context Protocol (MCP) — Standardized Tool Bridge
MCP is an open client-server protocol that lets an AI client discover and invoke structured **Tools** (actions), **Resources** (read-only context), and **Prompts** (reusable workflows) exposed by a server.

* **Custom Python MCP Server:**
  * A local Python process acts as an MCP server over `stdio` or SSE/HTTP.
  * The server wraps the official `MetaTrader5` Python library, which communicates with the running MT5 terminal over local Inter-Process Communication (IPC).
  * Useful when you want full control over tool schemas, custom risk validation, or domain-specific workflows.
* **Native Platform MCP:**
  * Modern MT5 builds expose built-in MCP servers directly from the terminal and MetaEditor, grouped by domain:
    * **Terminal:** Account info, open positions, order history, charts, indicators, and order execution.
    * **Market Data:** Symbol specifications, OHLCV history, news, and Economic Calendar events.
    * **MetaEditor & Strategy Tester:** MQL5 code generation, compilation, and backtest/optimization analysis.
  * Can be used with a built-in assistant, custom API keys, or external MCP clients.
* **Vision-Augmented MCP (Chart Screenshots):**
  * Pairs an MCP server with a companion MQL5 Expert Advisor (EA) that captures live chart images (including custom indicators and drawings) so multimodal/vision LLMs can analyze visual chart structure alongside numerical data.

### 2.2 Direct `WebRequest()` from MQL5 (Inline Cloud Calls)
MQL5 provides a built-in `WebRequest()` function for making HTTP/HTTPS calls directly from an Expert Advisor or script.

* **How it works:** The EA serializes recent bars, indicator values, and account state into a JSON payload, sends a `POST` request to an LLM API endpoint, and parses the structured JSON decision returned by the model.
* **Characteristics:** Self-contained inside MT5 with no external Python runtime needed, but subject to network/API latency and requires explicit URL whitelisting in terminal settings.

### 2.3 ZeroMQ Socket Bridges (Low-Latency Event Streams)
ZeroMQ (`ZMQ`) is an asynchronous messaging library used to build decoupled, high-throughput pipelines between MQL5 and Python.

* **How it works:** An EA loaded with an MQL5 ZeroMQ wrapper binds or connects sockets to stream live ticks and bar events to a Python AI agent, and receives execution instructions asynchronously.
* **Characteristics:** Very low overhead and suited for event-driven or latency-sensitive multi-agent systems, at the cost of managing socket lifecycles and serialization logic.

### 2.4 REST API Bridges (Cross-OS & Cloud-Decoupled)
A lightweight HTTP server (e.g., FastAPI or Flask) runs on the Windows host alongside MT5, wrapping the `MetaTrader5` Python library into REST endpoints (such as `/account`, `/rates`, `/order`).

* **Characteristics:** Decouples the Windows-bound MT5 terminal from AI agents running in Linux containers, cloud services, or separate machines.

### 2.5 Direct Python Tool-Calling (No MCP Layer)
When building a single, self-contained Python agent using an agent SDK or orchestration framework, the MCP protocol layer can be omitted. Functions from the `MetaTrader5` Python library are registered directly as native Python tools/functions for the LLM to call.

### 2.6 Native ONNX Inference in MQL5 (Local Predictive ML)
Open Neural Network Exchange (ONNX) allows predictive machine learning and deep learning models—trained externally in Python—to execute directly inside MQL5 without external API calls.

* **How it works:** A trained model is exported to `.onnx`, placed in the terminal's `MQL5/Files` directory, and loaded into an EA using native `OnnxCreate()` and `OnnxRun()` functions.
* **Characteristics:** Deterministic, millisecond-level inference with zero network latency; ideal for numerical forecasting, classification, and reinforcement learning policies rather than natural-language reasoning.

---

## 3. Choosing an Approach

| Pattern | Latency | Setup Complexity | Primary Strength |
| :--- | :--- | :--- | :--- |
| **Native MT5 MCP** | Moderate | Minimal | Built-in terminal, MetaEditor, and Strategy Tester integration |
| **Custom Python MCP** | Moderate | Medium | Full control over custom tools, schemas, and client portability |
| **MQL5 `WebRequest()`** | Moderate–Slow | Low | Self-contained EA with no external processes |
| **ZeroMQ Bridge** | Very Low | Medium–High | Real-time, event-driven, high-throughput Python pipelines |
| **REST API Bridge** | Moderate | Medium | Connecting Linux/Docker/cloud agents to Windows MT5 |
| **Direct Python Library** | Low | Low | Simplest path for a single custom Python agent |
| **Native MQL5 ONNX** | Instant | Medium | Ultra-fast local ML inference inside EAs |

---

## 4. Safety & Risk Guardrails

* **Progressive Permissions:** Start in read-only analysis mode, move to human-in-the-loop trade confirmation, and only enable autonomous execution after thorough validation.
* **Deterministic Risk Enforcement:** Enforce maximum lot sizes, slippage/deviation limits, and stop-loss requirements in code (via pre-trade validation such as `order_check` / `OrderCheck`) rather than relying on LLM prompt instructions.
* **Demo Validation:** Test all connectivity, serialization, and edge-case error handling on a demo account before touching live funds.
* **Terminal Controls:** Only enable algorithmic trading and URL whitelisting for explicitly required endpoints.

---

## 5. Implementations in This Repository

* **MCP Server (`MetaTrader5` Python IPC):** [`mt5/ai-agent/mcp/README.md`](../mt5/ai-agent/mcp/README.md)
* **ZeroMQ Socket Bridge (`zmq_server.py` + `zmq_client.py`):** [`mt5/ai-agent/zeromq/README.md`](../mt5/ai-agent/zeromq/README.md)

