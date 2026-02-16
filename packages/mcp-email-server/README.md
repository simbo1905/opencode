# MCP Email Server

An MCP (Model Context Protocol) email server written in Lua using the [lunet](https://github.com/lua-lunet/lunet) runtime with native HTTPS support via `lunet.httpc`.

## Features

- **Session Management**: Append-only operation log with divergence detection (OpRef/ParentRef)
- **JMAP Client**: Native HTTPS email access via `lunet.httpc`
- **Email Classification**: Multi-model routing (Mistral, Groq, Together)
- **Approval Gates**: User approval for sends/deletes with configurable scopes
- **Action Ledger**: Delayed/scheduled actions with execution-time revalidation
- **Pluggable Categories**: Configurable triage categories
- **Investigation Tools**: Sender history, domain lookup, phishing detection

## Configuration

The server uses a centralized `app/config.lua` for all provider settings, API endpoints, and operational parameters.

### config.lua Structure

```lua
return {
  -- LLM Provider Configuration
  providers = {
    mistral = {
      name = "Mistral",
      url = "https://api.mistral.ai/v1/chat/completions",
      api_key_env = "MISTRAL_API_KEY",
      models = {
        small = "mistral-small-latest",
        large = "mistral-large-latest",
      },
      default_model = "small",
    },
    groq = {
      name = "Groq",
      url = "https://api.groq.com/openai/v1/chat/completions",
      api_key_env = "GROQ_API_KEY",
      models = {
        llama_70b = "llama-3.3-70b-versatile",
        llama_8b = "llama-3.1-8b-instant",
      },
      default_model = "llama_70b",
    },
    together = {
      name = "Together",
      url = "https://api.together.xyz/v1/chat/completions",
      api_key_env = "TOGETHER_API_KEY",
      models = {
        mixtral = "mistralai/Mixtral-8x7B-Instruct-v0.1",
      },
      default_model = "mixtral",
    },
  },

  -- JMAP Configuration
  jmap = {
    url_env = "JMAP_URL",
    username_env = "JMAP_USERNAME",
    password_env = "JMAP_PASSWORD",
    timeout_ms = 30000,
  },

  -- Server Configuration
  server = {
    host = "127.0.0.1",
    port = 8080,
  },

  -- Request Defaults
  http = {
    timeout_ms = 15000,
    max_body_bytes = 10 * 1024 * 1024, -- 10 MiB
  },
}
```

### Environment Variables

Create a `.env` file in the project root with your API keys:

```bash
# LLM Providers
MISTRAL_API_KEY=your_mistral_key_here
GROQ_API_KEY=your_groq_key_here
TOGETHER_API_KEY=your_together_key_here

# JMAP (Fastmail, etc.)
JMAP_URL=https://api.fastmail.com/.well-known/jmap
JMAP_USERNAME=your_email@example.com
JMAP_PASSWORD=your_app_password_here
```

The `.env` file is loaded by the test harnesses (e.g. `test/test_httpc_models.lua`).
The application itself reads environment variables via `os.getenv()` — set them in
your shell or use a process supervisor that loads `.env` for you.

### Why config.lua?

Following the **single source of truth** principle from Markdown-Driven Development:

1. **No duplication**: Provider URLs, models, and timeouts defined once
2. **Easy testing**: Tests use the same config as production
3. **Type safety**: Lua tables provide structure validation at load time
4. **Flexibility**: Override via environment variables (e.g., `MISTRAL_API_URL`)
5. **Discoverability**: All available providers and models in one place

This pattern is inspired by [lunet-realworld-example-app](https://github.com/lua-lunet/lunet-realworld-example-app).

## Building

### Prerequisites

- [xmake](https://xmake.io/) build system
- libcurl (for HTTPS support)
- LuaJIT 2.1+

### Build Steps

```bash
# Initialize submodules
git submodule update --init --recursive

# Build lunet with httpc extension
cd vendor/lunet
xmake f -m release --lunet_trace=n --lunet_verbose_trace=n -y
xmake build lunet-bin
xmake build lunet-httpc

# Build lunet-mcp-sse transport layer
cd ../lunet-mcp-sse
make build

# Return to project root
cd ../..
```

## Testing

### Run httpc Provider Tests

Test that `lunet.httpc` can successfully call all three LLM providers:

```bash
cd packages/mcp-email-server
../../vendor/lunet-mcp-sse/deps/lunet/build/macosx/arm64/release/lunet-run test/test_httpc_models.lua
```

Expected output:

```
=== lunet.httpc Model Provider Test Rig ===
Testing Mistral, Groq, Together with completion + continuation

[Mistral] Testing completion
[Mistral] Status: 200
[Mistral] Response: Why don't skeletons fight each other? They don't have the guts!
[Mistral] OK
...
Total: 6 pass, 0 fail (out of 6 tests)
```

### Run Busted Unit Tests

```bash
cd packages/mcp-email-server
busted spec/
```

Expected: 171 successes, 0 failures, 0 pending.

## Architecture

### Session Management (`app/session.lua`)

Implements RFC §5.1–5.3:

- Unique SessionID per client connection
- Append-only operation log with OpRef/ParentRef chain
- Divergence detection: returns intervening operations on stale ParentRef
- Transparent log access for debugging

### JMAP Client (Planned: `app/jmap.lua`)

Native HTTPS client using `lunet.httpc`:

- Session auth flow
- Mailbox listing and message retrieval
- Efficient pagination with explicit time window anchors
- No opaque cursors (per RFC §4.2)

### MCP Tools

1. **list_messages**: Explicit time window traversal, no implicit state
2. **classify_email**: Multi-model routing (small for classification, large for orchestration)
3. **reply/forward/archive/trash/delete**: With approval gates
4. **investigate_sender/domain/phishing**: Context gathering for decisions

### Multi-Model Routing

- **Mistral Small**: Fast email classification
- **Mistral Large**: High-stakes decisions, orchestration
- **Groq Llama 70B**: Alternative high-throughput provider
- **Together Mixtral**: Fallback/experimentation

## Development Workflow

This project follows **Markdown-Driven Development**:

1. **Docs first**: Write `SKILL.md` and RFC before code
2. **Tests second**: Write busted specs with pending stubs
3. **Implement third**: Make tests pass
4. **Review checkpoints**: Code review after major milestones

See `.opencode/skill/mcp-email-triage/SKILL.md` for the full prompt templates and structured output schemas.

## Status

- ✅ Steps 1–8f: RFC, docs, session.lua (15/15 tests passing), httpc test rig (6/6 passing)
- 🚧 Step 8g–8k: Config centralization (in progress)
- ⏳ Steps 9–20: JMAP client, MCP tools, approval gates, action ledger, integration test

## References

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [lunet Runtime](https://github.com/lua-lunet/lunet)
- [lunet-mcp-sse](https://github.com/lua-lunet/lunet-mcp-sse)
- [Busted Testing Framework](https://lunarmodules.github.io/busted/)
- [JMAP RFC 8620](https://www.rfc-editor.org/rfc/rfc8620.html)
