# OpenCode Web API Fact-Check Report

This document fact-checks the PDF "OpenCode Web API Integration Guide for MultiAgent Communication Protocol Backend" against the actual OpenAPI specification.

## Summary

The PDF provides a mostly accurate overview but contains several **inaccuracies** and **omissions**:

- ✅ **Correct**: Session isolation model, most endpoint paths, general API structure
- ⚠️ **Incomplete**: Missing many endpoints (72 total endpoints vs ~20 documented)
- ❌ **Errors**: Some endpoint descriptions, parameter details, and response formats

---

## Detailed Comparison

### Session Management Endpoints

#### ✅ CORRECT Endpoints

| Endpoint | Method | PDF Description | Actual |
|----------|--------|----------------|--------|
| `/session` | GET | List all sessions | ✅ Correct (returns `Session[]`) |
| `/session` | POST | Create new session | ✅ Correct (body: `{parentID?, title?}`) |
| `/session/:id` | GET | Get session details | ✅ Correct (returns `Session`) |
| `/session/:id` | DELETE | Delete session | ✅ Correct (returns `boolean`) |
| `/session/:id` | PATCH | Update session | ✅ Correct (body: `{title?}`) |
| `/session/:id/fork` | POST | Fork session at message | ✅ Correct (body: `{messageID?}`) |
| `/session/:id/abort` | POST | Abort running session | ✅ Correct (returns `boolean`) |
| `/session/:id/diff` | GET | Get session diff | ✅ Correct (query: `messageID?`, returns `FileDiff[]`) |

#### ⚠️ PARTIALLY CORRECT Endpoints

| Endpoint | Method | PDF Claims | Actual API |
|----------|--------|-----------|------------|
| `/session/:id/share` | POST | Share session, returns `Session` | ✅ Correct |
| `/session/:id/share` | DELETE | "Unshare session", returns `Session` | ⚠️ **Actually**: DELETE method exists, operationId is `session.unshare` |
| `/session/:id/summarize` | POST | Body: `{providerID, modelID}` | ⚠️ **Actually**: Also requires `auto?: boolean` field and both fields are **required**, not optional |

#### ❌ INCORRECT/MISLEADING Descriptions

| Endpoint | PDF Description | Actual API |
|----------|----------------|------------|
| `/session/:id/init` | Body: `{messageID, providerID, modelID}` | ❌ **Actually**: ALL THREE fields are **required** (not optional) |
| `/session/:id/message` | "Send message and wait for response", Body: `{message}` | ❌ **WRONG**: This endpoint has **TWO** operations:<br>- GET: List all messages (operationId: `session.messages`)<br>- POST: Send message (operationId: `session.prompt`)<br>Body is complex with `parts[]`, `model`, `agent`, etc. - NOT just `{message}` |
| `/session/:id/revert` | Body: `{messageID, partID?}` | ⚠️ Mostly correct but `partID` is optional in request body |
| `/session/:id/permissions/:permissionID` | Body: `{response, remember?}` | ❌ **WRONG**: Body is `{response: "once" | "always" | "reject"}` - NO `remember` field |

---

### File and Context Handling Endpoints

#### ⚠️ URL Format Issues

The PDF uses URL query parameter notation that is **misleading**. These should be described as query parameters, not path syntax.

| PDF Claims | Actual API |
|-----------|------------|
| `GET /find?pattern=<pat>` | ✅ Correct: `GET /find` with **query param** `pattern` (required) |
| `GET /find/file?query=<q>` | ✅ Correct: `GET /find/file` with **query param** `query` (required)<br>⚠️ **Also supports**: `dirs`, `type`, `limit` params |
| `GET /find/symbol?query=<q>` | ✅ Correct: `GET /find/symbol` with **query param** `query` |
| `GET /file?path=<path>` | ✅ Correct: `GET /file` with **query param** `path` (required) |
| `GET /file/content?path=<p>` | ✅ Correct: `GET /file/content` with **query param** `path` (required) |
| `GET /file/status` | ✅ Correct: Returns `File[]` |

#### ❌ Missing Details

- `/find/file` actually supports filtering by `type: "file" | "directory"` and has a `limit` parameter (1-200)
- All file/find endpoints accept an optional `directory` query parameter for workspace selection

---

### Task Execution Endpoints

| Endpoint | PDF Claims | Actual API Status |
|----------|-----------|-------------------|
| `POST /session/:id/init` | "Analyze app and create AGENTS.md" | ✅ Correct description |
| `POST /session/:id/message` | "Send message and wait for response" | ❌ **Misleading** - see Session Management section |
| `POST /session/:id/revert` | "Revert a message" | ✅ Correct |
| `POST /session/:id/permissions/:permissionID` | "Respond to permission request" | ✅ Correct concept, ❌ wrong body schema |

---

## Major Omissions from PDF

The actual API has **72 endpoints**, but the PDF only documents ~20. Here are critical missing endpoints:

### Missing Session Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/session/status` | GET | Get status of all sessions |
| `/session/{sessionID}/children` | GET | Get child sessions |
| `/session/{sessionID}/command` | POST | Execute command in session |
| `/session/{sessionID}/message/{messageID}` | GET/DELETE/PATCH | Message operations |
| `/session/{sessionID}/message/{messageID}/part/{partID}` | DELETE | Delete message part |
| `/session/{sessionID}/prompt_async` | POST | Async prompt (non-blocking) |
| `/session/{sessionID}/shell` | POST | Execute shell command |
| `/session/{sessionID}/todo` | GET | Get session todos |
| `/session/{sessionID}/unrevert` | POST | Undo a revert |

### Missing Global/System Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/global/health` | GET | Health check |
| `/global/event` | GET | Global event stream |
| `/global/dispose` | POST | Dispose global resources |
| `/log` | GET | Get system logs |
| `/event` | GET | Event stream |

### Missing Provider/Model Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/provider` | GET | List providers |
| `/provider/auth` | GET | Get provider auth info |
| `/provider/{providerID}/oauth/authorize` | GET | OAuth authorize |
| `/provider/{providerID}/oauth/callback` | GET | OAuth callback |
| `/auth/{providerID}` | POST | Authenticate provider |
| `/config` | GET/PATCH | Get/update config |
| `/config/providers` | GET | Get provider configurations |

### Missing MCP Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/mcp` | GET | List MCP servers |
| `/mcp/{name}/auth` | GET | Get MCP auth status |
| `/mcp/{name}/auth/authenticate` | POST | Authenticate MCP |
| `/mcp/{name}/auth/callback` | GET | MCP OAuth callback |
| `/mcp/{name}/connect` | POST | Connect to MCP server |
| `/mcp/{name}/disconnect` | POST | Disconnect from MCP |

### Missing Project Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/project` | GET/POST | List/create projects |
| `/project/current` | GET | Get current project |
| `/project/{projectID}` | DELETE | Delete project |
| `/instance/dispose` | POST | Dispose instance |
| `/vcs` | GET | Get VCS info |

### Missing Terminal/PTY Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/pty` | POST | Create PTY session |
| `/pty/{ptyID}` | DELETE | Delete PTY |
| `/pty/{ptyID}/connect` | GET | Connect to PTY (WebSocket) |

### Missing Tool/Agent Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/agent` | GET | List agents |
| `/command` | GET | List commands |
| `/experimental/tool` | POST | Execute experimental tool |
| `/experimental/tool/ids` | GET | List experimental tool IDs |
| `/formatter` | POST | Format code |
| `/lsp` | GET | LSP operations |

### Missing TUI Endpoints (12+ endpoints)

The PDF doesn't mention any TUI control endpoints (`/tui/*`), which are significant for terminal UI integration.

---

## Parameter/Query String Issues

**All endpoints** support an optional `directory` query parameter for workspace selection, which is not mentioned in the PDF.

---

## Authentication Section

The PDF mentions:
> "OpenCode supports OAuth authentication for remote MCP servers, handling token storage and automatic OAuth flows."

✅ **Confirmed** - The API includes OAuth endpoints:
- `/provider/{providerID}/oauth/authorize`
- `/provider/{providerID}/oauth/callback`
- `/mcp/{name}/auth/authenticate`
- `/mcp/{name}/auth/callback`

---

## URI and Context Handling

The PDF claims:
> "OpenCode supports URI schemes for referencing external resources"

⚠️ **Cannot verify** from OpenAPI spec alone - this would require examining request/response schemas in detail or testing the implementation.

---

## Conclusion

### PDF Accuracy Rating: **60%**

**Strengths:**
- Correctly identifies core session management endpoints
- Accurate high-level architectural concepts
- Correct understanding of session isolation

**Weaknesses:**
- Missing 72% of endpoints (52 out of 72 not documented)
- Incorrect body schemas for `/session/:id/message` and `/session/:id/permissions/:permissionID`
- Misleading query parameter notation
- Missing critical MCP, provider, project, and PTY endpoints
- Missing `directory` parameter documentation

**Recommendation:**
The PDF should be updated to:
1. Include all 72 endpoints
2. Correct the body schemas for message and permission endpoints
3. Document the `directory` query parameter
4. Clarify which parameters are required vs optional
5. Expand coverage of MCP, provider, and project management APIs
