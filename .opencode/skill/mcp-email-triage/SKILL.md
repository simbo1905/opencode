# MCP Email Triage and Action Workflow

Transparent, session-based email triage using MCP with explicit continuation, operation log integrity, and conservative approvals for destructive/outbound actions.

## Overview

This skill orchestrates email summarization, categorization, risk assessment, and user-approved follow-up actions against a JMAP mailbox via an MCP server. The design prioritizes safety under LLM resets, context compaction, and multi-device concurrency by enforcing transparent session semantics and explicit continuation parameters.

---

## Primary Model Prompt Template

```
You are an email triage assistant helping the user manage their inbox.

CRITICAL PRINCIPLES:
1. Every mailbox traversal uses EXPLICIT anchors (timestamps, message IDs, time windows). Never rely on hidden continuation state.
2. Always include ParentRef when making requests that depend on prior tool state.
3. Treat the session log as the source of truth. If divergence is detected, stop and consult the log.
4. Propose actions with clear evidence and always request explicit user approval for destructive or outbound actions.

WORKFLOW:
1. Retrieve a bounded slice of messages using explicit time/ID anchors
2. Summarize subjects and key metadata
3. Invoke the lightweight classifier to categorize messages
4. Investigate suspicious items (phishing, unusual senders)
5. Present categorized list with risk flags and evidence
6. Propose safe-by-default next actions
7. Request user approval before executing destructive or outbound actions
8. For continuation: use the explicit bounds returned by the prior request

USER CONTEXT:
- Categories available: ${CATEGORIES}
- Known contacts: ${CONTACTS}
- User preferences: ${PREFERENCES}
- Default approval scope: per-message (user can change to per-session or always)

When the user says "next page" or "continue", translate that into an explicit anchored request using bounds from the prior response. Do not assume implicit continuation.

Ask for clarification if ambiguous; consult the session log if uncertain.
```

## Lightweight Classification Prompt Template

```
You are a fast, structured email classifier. Categorize the following email based on ONLY headers, subject, and optional snippet. Return structured JSON.

INPUT:
- From: ${from}
- To: ${to}
- Subject: ${subject}
- Snippet: ${snippet}
- User context: ${user_context}

OUTPUT SCHEMA (see below)

CATEGORIES:
${CATEGORIES_JSON}

RISK BINS (use if applicable):
- spam: obvious bulk/commercial
- phishing-suspected: suspicious sender, urgency, unusual requests
- unsolicited: unexpected but not malicious

Return ONLY the JSON object. No explanation.
```

---

## Structured Output Schemas

### List/Query Response

```json
{
  "sessionId": "sess_abc123",
  "opRef": "opref_42",
  "parentRef": "opref_41",
  "operation": "list_messages",
  "bounds": {
    "startTimestamp": 1702000000000,
    "endTimestamp": 1702086400000,
    "startMessageId": "msg_1001",
    "endMessageId": "msg_1050",
    "direction": "descending",
    "count": 50
  },
  "messages": [
    {
      "messageId": "msg_1050",
      "from": "alice@example.com",
      "subject": "Q4 Planning",
      "timestamp": 1702086300000,
      "snippet": "Let's discuss Q4 roadmap...",
      "flags": ["unseen"]
    }
  ],
  "divergenceDetected": false,
  "notes": "50 messages returned; next request should use endMessageId as anchor"
}
```

### Classification Response

```json
{
  "sessionId": "sess_abc123",
  "opRef": "opref_43",
  "parentRef": "opref_42",
  "operation": "classify_messages",
  "classified": [
    {
      "messageId": "msg_1050",
      "category": "work",
      "riskBin": null,
      "confidence": 0.98,
      "evidence": "From known colleague, work domain, familiar subject pattern"
    }
  ],
  "divergenceDetected": false
}
```

### Action Proposal Response

```json
{
  "sessionId": "sess_abc123",
  "opRef": "opref_44",
  "operation": "propose_actions",
  "proposedActions": [
    {
      "messageId": "msg_1045",
      "actionType": "move",
      "target": "Archive",
      "executionMode": "immediate",
      "approvalRequired": false,
      "reasoning": "Automated archive: low-priority bulk email"
    },
    {
      "messageId": "msg_1042",
      "actionType": "send",
      "draftId": "draft_xyz",
      "executionMode": "ask",
      "approvalRequired": true,
      "approvalScope": ["once", "session", "always"],
      "reasoning": "Outbound action requires explicit approval"
    }
  ]
}
```

### Session Log Entry

```json
{
  "sessionId": "sess_abc123",
  "opRef": "opref_45",
  "parentRef": "opref_44",
  "timestamp": 1702086500000,
  "operation": "archive_message",
  "parameters": {
    "messageId": "msg_1040",
    "parentRef": "opref_44"
  },
  "result": {
    "status": "success",
    "messageNewState": "archived",
    "timestamp": 1702086500000
  }
}
```

### Action Ledger Entry

```json
{
  "ledgerId": "ledger_001",
  "sessionId": "sess_abc123",
  "originOpRef": "opref_46",
  "actionType": "send",
  "target": "bob@example.com",
  "executionMode": "delayed",
  "delaySpec": "2024-12-15T09:00:00Z",
  "status": "pending",
  "approval": {
    "required": true,
    "scope": "once",
    "approverResponse": "approved",
    "approvalTime": 1702086600000
  },
  "executionOpRef": null,
  "executionTime": null
}
```

### Divergence Response

```json
{
  "sessionId": "sess_abc123",
  "operation": "divergence_detected",
  "currentHeadOpRef": "opref_50",
  "callerParentRef": "opref_44",
  "divergence": {
    "reason": "session has advanced; caller's ParentRef is stale",
    "operationsBetween": [
      {
        "opRef": "opref_45",
        "operation": "classify_messages",
        "timestamp": 1702086500000
      },
      {
        "opRef": "opref_46",
        "operation": "archive_message",
        "timestamp": 1702086510000
      }
    ]
  },
  "recoveryAdvice": "Review intervening operations, or start fresh request with currentHeadOpRef as new ParentRef"
}
```

---

## Example Transcript: End-to-End Triage

### Exchange 1: Initial Retrieval

**User:** "Show me recent emails from the past day."

**Model:** Calls `list_messages` with explicit anchor:

```
time_window_start: now - 24h
time_window_end: now
limit: 20
parentRef: null (first call)
```

**Tool returns:** 20 messages, bounds, opRef="opref_1", including messages from Alice, Bob, spam, and one phishing-suspected.

### Exchange 2: Classification

**Model:** Invokes lightweight classifier on the 20 messages.

**Classifier returns:** Each message assigned a category (work, personal, spam, phishing-suspected) with evidence. opRef="opref_2", parentRef="opref_1".

### Exchange 3: Investigation

**Model:** Requests investigation of the phishing-suspected message:

```
messageId: msg_005
operation: lookup_sender_history
parentRef: opref_2
```

**Tool returns:** "This sender has not been seen before; domain is new; contains urgent language and unusual request." opRef="opref_3".

### Exchange 4: Proposal

**Model to User:**

```
📋 **Email Triage Summary**

**Work** (5 messages):
- Q4 Planning (Alice)
- Status Update (Bob)
→ Recommend: Mark read, keep in Inbox

**Personal** (8 messages):
- Birthday reminder (Mom)
- Event invite (Friend)
→ Recommend: Keep

**Spam** (6 messages):
→ Recommend: Archive

**⚠️ Phishing-Suspected** (1 message):
- "URGENT: Verify your account" (unknown@suspicious.com)
- Evidence: New sender, domain mismatch, urgency, account verification request
→ Recommend: Move to spam, delete after 30 days
```

### Exchange 5: User Approval

**User:** "Archive the spam, move phishing to spam folder. I'll handle the work emails myself."

**Model:** Requests approval for destructive actions:

```
Action: move message msg_005 to Spam
Approval required: yes
Scope options: [once, session, always]
```

**User:** "Once is fine."

### Exchange 6: Execution

**Model:** Executes actions with ParentRef from prior state (opref_3):

```
operation: move_message
messageId: msg_005
target: Spam
parentRef: opref_3
executionMode: immediate
```

**Tool returns:** Success, opRef="opref_4".

### Exchange 7: Continuation

**User:** "Show me the next batch."

**Model:** Uses explicit anchor from prior response:

```
list_messages
time_window_start: opref_1.bounds.endTimestamp
time_window_end: now - 24h (earlier than before)
limit: 20
parentRef: opref_4
```

**Tool returns:** Next 20 messages, new opRef="opref_5".

### Exchange 8: Delayed Action

**User:** "Send a reply to Bob tomorrow morning at 9 AM."

**Model:** Drafts reply, requests approval:

```
operation: send_message
target: bob@example.com
draftId: draft_xyz
executionMode: delayed
delaySpec: "2024-12-15T09:00:00Z"
parentRef: opref_5
approvalRequired: true
```

**User:** "Review the draft first."

**Model shows draft content.**

**User:** "Approved, session scope."

**Tool:** Schedules action, returns opRef="opref_6" and ledgerId="ledger_001" (status: pending).

### Exchange 9: Recovery After Reset

**Model:** Loses context (compaction or reset). User resumes: "What's pending?"

**Model:** Calls:

```
operation: list_pending_actions
sessionId: sess_abc123
```

**Tool returns:** Ledger showing "Send to bob@example.com, scheduled for 2024-12-15T09:00:00Z, status: pending, originOpRef: opref_6".

**Model:** Reconstructs context and continues safely.

---

## Configuration

### Environment Variables

```bash
# Email categories (comma-separated)
MCP_EMAIL_CATEGORIES="work,personal,family,school,medical,auto,finance,spam,unsolicited,phishing-suspected"

# Default approval scope (once, session, always)
MCP_EMAIL_DEFAULT_APPROVAL_SCOPE="once"

# Whether hard-delete is allowed (false by default)
MCP_EMAIL_ALLOW_HARD_DELETE="false"

# Lightweight classifier model (Mistral)
MCP_EMAIL_CLASSIFIER_MODEL="mistral-small-latest"

# Primary orchestration model (Mistral)
MCP_EMAIL_PRIMARY_MODEL="mistral-large-latest"

# Model provider (mistral, groq, together)
MCP_MODEL_PROVIDER="mistral"

# JMAP server endpoint
MCP_JMAP_URL="https://jmap.example.com"

# Session log durability (memory, sqlite)
MCP_SESSION_LOG_DURABILITY="sqlite"
```

### Runtime Stack

This MCP server runs on [Lunet](https://github.com/lua-lunet/lunet) — a LuaJIT + libuv coroutine runtime. The reference implementation is based on [lunet-mcp-sse](https://github.com/lua-lunet/lunet-mcp-sse).

- **Language**: Lua (LuaJIT)
- **Runtime**: Lunet (coroutine-based, libuv event loop)
- **Build**: xmake
- **HTTPS calls**: curl subprocess (no TLS in lunet yet)
- **Memory**: ~7 MB RSS at runtime
- **Docker image**: ~171 MB

```
vendor/
├── lunet/              # Lunet runtime (git submodule)
└── lunet-mcp-sse/      # MCP SSE reference impl (git submodule, branch codex/lunet-v0.2.3-xmake-upgrade)
    └── app/main.lua    # Single-file MCP server to extend
```

### Known Contacts and Preferences

```json
{
  "contacts": [
    { "email": "alice@work.com", "name": "Alice Chen", "relationship": "colleague" },
    { "email": "bob@work.com", "name": "Bob Smith", "relationship": "manager" }
  ],
  "categories": {
    "work": { "autoArchiveOlder": "30d", "trustLevel": "high" },
    "spam": { "autoArchiveOlder": "7d", "trustLevel": "low" }
  },
  "actionDefaults": {
    "archive": { "approvalRequired": false },
    "send": { "approvalRequired": true, "defaultScope": "once" },
    "delete": { "approvalRequired": true, "defaultScope": "once" }
  }
}
```

---

## Testing Expectations

1. **Explicit Continuation Stability**: Same request with same anchors yields same results.
2. **ParentRef Divergence**: Tool detects and reports divergence; host can recover.
3. **Idempotency**: Replaying an action with same ParentRef and messageId is safe.
4. **Prompt Injection Defense**: Email content is treated as data, not instructions.
5. **Multi-Model Handoff**: Lightweight classifier can operate independently; primary model can resume with full context.
6. **Delayed Action Ledger**: Pending actions survive host restarts and can be resumed.

---

## References

- Full RFC: `packages/mcp-email-server/docs/rfc.md`
- MCP Spec: https://modelcontextprotocol.io/
- JMAP Spec: https://jmap.io/
- Mistral API: https://docs.mistral.ai/
- Groq Console: https://console.groq.com/
- Together API: https://docs.together.ai/
