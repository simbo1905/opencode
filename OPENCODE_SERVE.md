# OpenCode Serve Command Investigation Report

## Executive Summary

The `opencode serve` command starts a **headless HTTP server** that exposes a comprehensive OpenAPI 3.1 specification. This is the "lower-level" interface compared to `opencode web`, which simply adds UI formatting, network discovery display, and auto-launches a browser.

Both commands use the identical `Server.listen()` function and expose the **same APIs** - the difference is purely in their startup presentation and browser integration.

---

## Command Comparison

| Aspect | `opencode serve` | `opencode web` |
|--------|------------------|----------------|
| **Output** | Simple console log | Styled UI with OpenCode logo |
| **Browser** | No auto-launch | Auto-opens browser via `open` package |
| **Network Discovery** | No display | Shows all available network IPs |
| **mDNS Display** | Not shown | Shows `opencode.local` if enabled |
| **Use Case** | Headless automation, CI/CD, IDE plugins | Interactive development, user-facing access |
| **APIs Exposed** | Full REST + WebSocket API | Same full REST + WebSocket API |

---

## Lower-Level / TUI Interfaces Exposed by `opencode serve`

The server exposes several **lower-level interfaces** that enable programmatic control and terminal integration:

### 1. PTY (Pseudo-Terminal) API

The PTY API is the primary "low-level" interface for terminal interaction. It allows creating and managing pseudo-terminal sessions via HTTP/REST and WebSocket.

**Endpoints:**

| Method | Path | Operation ID | Description |
|--------|------|--------------|-------------|
| `GET` | `/pty` | `pty.list` | List all active PTY sessions |
| `POST` | `/pty` | `pty.create` | Create a new PTY session |
| `GET` | `/pty/{ptyID}` | `pty.get` | Get PTY session info |
| `PUT` | `/pty/{ptyID}` | `pty.update` | Update PTY session (title, resize) |
| `DELETE` | `/pty/{ptyID}` | `pty.remove` | Terminate and remove PTY session |
| `GET` | `/pty/{ptyID}/connect` | `pty.connect` | **WebSocket** connection for real-time I/O |

**PTY Schema:**

```json
{
  "id": "pty_xxxxx",
  "title": "Terminal 1234",
  "command": "/bin/zsh",
  "args": ["-l"],
  "cwd": "/path/to/project",
  "status": "running",
  "pid": 12345
}
```

**Create Input:**

```json
{
  "command": "/bin/zsh",
  "args": ["-l"],
  "cwd": "/path/to/project",
  "title": "My Terminal",
  "env": { "CUSTOM_VAR": "value" }
}
```

**Update Input:**

```json
{
  "title": "New Title",
  "size": { "rows": 24, "cols": 80 }
}
```

**PTY Events (SSE):**

| Event Type | Payload |
|------------|---------|
| `pty.created` | `{ info: Pty }` |
| `pty.updated` | `{ info: Pty }` |
| `pty.exited` | `{ id: string, exitCode: number }` |
| `pty.deleted` | `{ id: string }` |

---

### 2. TUI Control API

The TUI Control API allows external programs to drive the OpenCode TUI remotely. This is used by IDE plugins.

**Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/tui/append-prompt` | Append text to the TUI prompt |
| `POST` | `/tui/submit-prompt` | Submit the current prompt |
| `POST` | `/tui/clear-prompt` | Clear the prompt |
| `POST` | `/tui/execute-command` | Execute a slash command |
| `POST` | `/tui/show-toast` | Show a toast notification |
| `POST` | `/tui/open-help` | Open help dialog |
| `POST` | `/tui/open-sessions` | Open session selector |
| `POST` | `/tui/open-themes` | Open theme selector |
| `POST` | `/tui/open-models` | Open model selector |
| `GET` | `/tui/control/next` | Wait for next control request |
| `POST` | `/tui/control/response` | Respond to a control request |

The `/tui/control/next` and `/tui/control/response` endpoints implement a **request-response queue** that allows bidirectional communication between external clients and the TUI.

---

### 3. Events API (Server-Sent Events)

Real-time event streaming for monitoring all server activities:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/event` | Main SSE stream for all events |
| `GET` | `/global/event` | Global events stream |

The first event on `/event` is always `server.connected`, followed by bus events including PTY events, session events, message events, etc.

---

### 4. Attach Command

The `opencode attach <url>` command connects a TUI to a running `opencode serve` instance:

```bash
opencode serve --port 4096 --hostname 0.0.0.0

opencode attach http://localhost:4096 --session <sessionID>
```

This architecture enables:
- Running the server on a remote machine
- Multiple TUI clients connecting to one server
- IDE plugins controlling the TUI programmatically

---

## Documentation Locations

| Documentation | Location |
|--------------|----------|
| **OpenAPI Spec (live)** | `http://<host>:<port>/doc` |
| **PTY API HTML Docs** | `OPENAPI_PTY.html` |
| **Core API HTML Docs** | `OPENAPI_CORE.html` |
| **MCP API HTML Docs** | `OPENAPI_MCP.html` |
| **OpenAPI JSON** | `openapi.json` |
| **SDK OpenAPI JSON** | `packages/sdk/openapi.json` |
| **Server Documentation** | `packages/web/src/content/docs/server.mdx` |
| **CLI Documentation** | `packages/web/src/content/docs/cli.mdx` |
| **TUI Documentation** | `packages/web/src/content/docs/tui.mdx` |

---

## Implementation Details

### Source Files

| Component | File Path |
|-----------|-----------|
| Serve Command | `packages/opencode/src/cli/cmd/serve.ts` |
| Web Command | `packages/opencode/src/cli/cmd/web.ts` |
| Server Implementation | `packages/opencode/src/server/server.ts` |
| PTY Module | `packages/opencode/src/pty/index.ts` |
| TUI Routes | `packages/opencode/src/server/tui.ts` |
| Attach Command | `packages/opencode/src/cli/cmd/tui/attach.ts` |
| Network Options | `packages/opencode/src/cli/network.ts` |

### PTY Implementation

The PTY module uses `bun-pty` for native pseudo-terminal support:

- Sessions are stored in instance state with active process handles
- WebSocket connections enable real-time bidirectional I/O
- Output is buffered when no WebSocket clients are connected
- Multiple clients can subscribe to the same PTY session
- Terminal resize is supported via the update endpoint

---

## CLI Flags

Both `serve` and `web` commands accept the same network options:

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--port` | number | `0` (random) | Port to listen on |
| `--hostname` | string | `127.0.0.1` | Hostname to bind to |
| `--mdns` | boolean | `false` | Enable mDNS service discovery |
| `--cors` | string[] | `[]` | Additional CORS origins |

Example:

```bash
opencode serve --port 4096 --hostname 0.0.0.0 --cors http://localhost:5173
```

---

## Typical Use Cases

### 1. IDE Plugin Integration

IDE plugins connect to the server to:
- Pre-fill prompts via `/tui/append-prompt`
- Execute commands via `/tui/execute-command`
- Show notifications via `/tui/show-toast`

### 2. Headless Automation

Run OpenCode in CI/CD or automation scripts:

```bash
opencode serve --port 4096

curl -X POST http://localhost:4096/session \
  -H "Content-Type: application/json" \
  -d '{"title": "Automated Session"}'
```

### 3. Remote Development

Run server on a remote machine and attach locally:

```bash
ssh remote-server "opencode serve --port 4096 --hostname 0.0.0.0"

opencode attach http://remote-server:4096
```

### 4. Terminal Embedding

Create PTY sessions for embedded terminal experiences:

```bash
curl -X POST http://localhost:4096/pty \
  -H "Content-Type: application/json" \
  -d '{"command": "/bin/zsh", "title": "Embedded Terminal"}'

wscat -c ws://localhost:4096/pty/<ptyID>/connect
```

---

## Summary

The `opencode serve` command is the **foundational headless server** that exposes:

1. **PTY API** - Full pseudo-terminal management with WebSocket I/O
2. **TUI Control API** - Remote control of the Terminal UI
3. **Session/Message APIs** - Complete AI session management
4. **Events API** - Real-time SSE event streaming
5. **File/Config APIs** - Project and configuration management

The comprehensive OpenAPI 3.1 specification is available at `/doc` on any running server instance.
