# Test Pyramid — MCP Email Server

## Why a Pyramid?

The Testing Pyramid (Fowler, 2012) is a strategic model for building a healthy test
suite. The core idea: write many fast, cheap tests at the bottom; fewer slower tests
in the middle; very few expensive end-to-end tests at the top.

In TDD the pyramid keeps the red-green-refactor loop tight. Most feedback comes from
unit tests that run in milliseconds. Integration tests catch boundary bugs that units
miss. E2E tests exist only for critical flows where nothing else gives confidence.

The layers are a rule of thumb, not a rigid boundary. We test by what is easy and
effective at each level. Some things straddle layers. The goal is fast feedback and
sustainable maintenance, not ceremony.

When `test-full` runs it goes **up the pyramid**: units first, then offline module
harnesses, then online harnesses that hit real APIs. If units fail, the rest is
skipped — no point running slow tests on broken logic.

## Two Commands

```bash
make test-fast    # Unit + offline module tests (~2 seconds, no API keys)
make test-full    # Everything including real LLM and JMAP calls (~30 seconds, needs .env)
```

That's it. No other targets to remember.

---

## Tier 1: Unit Tests (busted specs)

**Location:** `spec/`
**Runner:** `busted spec/`
**Runtime:** Plain LuaJIT (no lunet)
**Network:** None
**Speed:** < 1 second

Pure logic tests. No I/O, no sockets, no external services.

| File                 | Module              | What it covers                                           |
| -------------------- | ------------------- | -------------------------------------------------------- |
| `session_spec.lua`   | `app/session.lua`   | OpRef/ParentRef chain, divergence detection, log queries |
| `traversal_spec.lua` | `app/traversal.lua` | Param validation, query building, bounds computation     |
| `actions_spec.lua`   | `app/approval.lua`  | Gate/approve/revoke, scopes (once/session/always)        |
| `ledger_spec.lua`    | `app/ledger.lua`    | Schedule/execute/cancel, revalidation, idempotency       |
| `llm_spec.lua`       | `app/llm.lua`       | Config validation, error paths (no httpc in test env)    |

**Naming:** `<module>_spec.lua`

---

## Tier 2: Module Tests (lunet harnesses)

**Location:** `test/`
**Runner:** `lunet-run test/test_<module>.lua`
**Runtime:** lunet (LuaJIT + libuv + httpc)
**Network:** Some need API keys, some don't
**Speed:** 5-30 seconds depending on network

Each harness is a single Lua file that uses `lunet.spawn()` to exercise one subsystem
with real I/O or controlled stubs. Prints structured pass/fail output. Exits 0 or 1.

### Existing

| File                    | Tests                                    | Boundary      | Network |
| ----------------------- | ---------------------------------------- | ------------- | ------- |
| `test_httpc_models.lua` | Raw httpc calls to Mistral/Groq/Together | `lunet.httpc` | Yes     |

### Planned (not yet implemented)

#### Offline (no API keys needed)

| File                            | Tests                                  | Boundary                              |
| ------------------------------- | -------------------------------------- | ------------------------------------- |
| `test_mcp_jsonrpc.lua`          | MCP JSON-RPC protocol dispatch         | `app/rpc.lua` with stub deps          |
| `test_session_divergence.lua`   | Divergence detection + recovery        | `app/session.lua` + `app/tools.lua`   |
| `test_traversal_pagination.lua` | Explicit continuation chains           | `app/traversal.lua` + `app/tools.lua` |
| `test_approval_sequences.lua`   | Multi-step approval gate flows         | `app/approval.lua` + `app/tools.lua`  |
| `test_ledger_lifecycle.lua`     | Delayed action schedule/execute/cancel | `app/ledger.lua` + `app/tools.lua`    |

These will use `test/stub_jmap.lua` — a deterministic canned JMAP client with the same
interface as `jmap.new()` but no network.

#### Online (needs API keys in .env)

| File                     | Tests                                  | Boundary       |
| ------------------------ | -------------------------------------- | -------------- |
| `test_summarisation.lua` | Email classification via real LLM      | `app/llm.lua`  |
| `test_jmap_session.lua`  | JMAP session discovery + mailbox query | `app/jmap.lua` |

**Naming:** `test_<module>.lua`

---

## Tier 3: Integration Tests (future)

**Location:** `test/`
**Naming:** `integ_<scenario>.lua`
**Network:** Full (JMAP + LLM)

End-to-end: MCP server running, client sends JSON-RPC, validates full triage workflow.
Deferred until HTTP/SSE transport is implemented.

---

## Shared Test Utilities

| File                 | Purpose                                  |
| -------------------- | ---------------------------------------- |
| `test/stub_jmap.lua` | Canned JMAP client for offline harnesses |

---

## ASAN / Leak Detection

For debugging C-level issues in the lunet runtime, build lunet in debug+asan mode:

```bash
cd vendor/lunet
xmake f -c -m debug --lunet_trace=y --asan=y -y
xmake build lunet-bin && xmake build lunet-httpc
```

Then run any module test with:

```bash
ASAN_OPTIONS=detect_leaks=1 lunet-run test/test_<module>.lua
```

This is a developer workflow, not a CI target. The Makefile does not expose it — you
opt in by rebuilding lunet with asan and running manually.

---

## Makefile

```makefile
LUNET_RUN ?= ../../vendor/lunet-mcp-sse/deps/lunet/build/macosx/arm64/release/lunet-run

.PHONY: test-fast test-full

test-fast:
	busted spec/
	$(LUNET_RUN) test/test_mcp_jsonrpc.lua
	$(LUNET_RUN) test/test_session_divergence.lua
	$(LUNET_RUN) test/test_traversal_pagination.lua
	$(LUNET_RUN) test/test_approval_sequences.lua
	$(LUNET_RUN) test/test_ledger_lifecycle.lua

test-full: test-fast
	$(LUNET_RUN) test/test_httpc_models.lua
	$(LUNET_RUN) test/test_summarisation.lua
	$(LUNET_RUN) test/test_jmap_session.lua
```

Two targets. Fast runs in CI without secrets. Full runs locally with `.env`.

---

## Architectural Note: Extract `app/rpc.lua`

To make the MCP JSON-RPC handler testable without starting the full server, extract
from `app/main.lua`:

- Tool schema definitions (the `tools` table)
- `handle_mcp_request(request, dispatchers)` function
- `make_dispatchers(sessions, jmap_client, llm_client, approvals, ledger)` factory

This lets `test_mcp_jsonrpc.lua` call `handle_mcp_request` directly with stub
dispatchers. `main.lua` becomes a thin startup wrapper.

---

## File Layout

```
packages/mcp-email-server/
├── app/                           # Application modules
├── docs/
│   ├── rfc.md                     # Protocol specification
│   └── TEST_PYRAMID.md            # This document
├── spec/                          # Tier 1: unit tests (busted, pure Lua)
│   ├── session_spec.lua
│   ├── traversal_spec.lua
│   ├── actions_spec.lua
│   ├── ledger_spec.lua
│   └── llm_spec.lua
├── test/                          # Tier 2: module tests (lunet harnesses)
│   ├── stub_jmap.lua              # Shared canned JMAP stub
│   ├── test_httpc_models.lua      # Online: LLM provider connectivity
│   ├── test_summarisation.lua     # Online: LLM classification
│   ├── test_jmap_session.lua      # Online: JMAP session flow
│   ├── test_mcp_jsonrpc.lua       # Offline: MCP protocol round-trips
│   ├── test_approval_sequences.lua # Offline: approval gate flows
│   ├── test_ledger_lifecycle.lua  # Offline: delayed action lifecycle
│   ├── test_traversal_pagination.lua # Offline: explicit continuation
│   └── test_session_divergence.lua   # Offline: divergence + recovery
├── Makefile
└── README.md
```
