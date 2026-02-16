# RFC: Transparent Session-Based MCP Email Triage and Action Workflow

## 1. Status and scope

This document specifies an experimental, testable workflow for managing email with an MCP-accessible tool, an interactive agent host, and multiple models. The workflow supports summarization, categorization, risk triage (including phishing suspicion), and user-approved follow-up actions (archive, mark read, move, delete-to-trash, draft replies, send replies). The design explicitly addresses time-travel resets, context compaction, crashes, restarts, and multi-device concurrency by enforcing transparent session semantics and explicit continuation parameters.

This document intentionally avoids over-prescribing internal algorithms, storage, transport, model vendors, or UI layout. It defines required behaviors, invariants, and interface-level expectations sufficient to implement interoperable prototypes and iterate safely.

## 2. Conventions and normative language

The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", and "MAY" are to be interpreted as normative requirements.

A "tool" in this document is an MCP-exposed service that performs operations against an external mail store and auxiliary lookups, and returns structured results.

A "host" is an interactive agent runtime that can call MCP tools, invoke one or more models, present results to a user, and receive user approvals.

## 3. Problem statement

Email is a stateful, shared dataset that changes over time and may be mutated by many independent clients (phone, webmail, desktop, other agents, automations). An LLM-driven host is not a reliable state container because it can be compacted, restarted, forked, or explicitly reverted to a prior point in time ("time travel"), including reverting conversational and local file state. Therefore, any design that assumes the host's conversational state is always aligned with tool state is fundamentally unsafe.

At the same time, a tool that hides implicit continuation state ("continue where I left off") will eventually surprise the host and user, causing missed items, repeated items, or unintended destructive actions.

This RFC resolves the mismatch by requiring explicit continuation parameters on all mailbox traversal operations, and by making any tool-maintained state transparent, queryable, and integrity-checked via per-session immutable logs.

## 4. Architectural overview

The system comprises four independent state domains:

1. **External mail store**: a shared authoritative database accessed through a mail protocol (e.g., JMAP) and modified by multiple clients.

2. **MCP mail tool**: an MCP server that exposes mail and lookup operations and maintains per-session immutable operation logs for transparency, recovery, and ordering checks.

3. **Agent host**: an interactive runtime coordinating tools, models, and user interaction; it may lose memory, fork, or revert.

4. **Models**: at minimum a primary (heavy-duty) model for orchestration and user interaction, plus one or more secondary (lightweight) models for classification and summarization, optionally escalating to stronger models when uncertainty is high.

The host performs "round-trip" interaction: it calls tools, receives results, asks the user to confirm or clarify, optionally calls additional tools or models, and returns updated outputs and action proposals.

## 5. Session model and immutable operation logs

### 5.1 Sessions are first-class and multi-tenant

The tool MUST support multiple concurrent sessions. A session is identified by a session identifier (SessionID) allocated by the tool. Sessions are not assumed to map one-to-one to a host instance, device, or model; multiple host instances MAY operate under the same SessionID if explicitly configured, and multiple SessionIDs MAY exist simultaneously for the same mailbox.

The tool MUST maintain a linear, append-only operation log per SessionID. The log MUST NOT branch within a SessionID. Branching, forking, or divergent host histories is handled by creating a new SessionID or by explicit reconciliation, not by branching the tool log.

### 5.2 Operation references and integrity

Each tool response MUST return an opaque operation reference (OpRef) representing that log entry, and MUST include a compact summary of what was attempted and observed (including relevant time bounds and message identifiers as applicable).

Each tool request that mutates tool-maintained session context or performs actions that depend on a prior view MUST include an explicit "as-of" reference (ParentRef). ParentRef asserts the caller's understanding of the session log position. The tool MUST compare ParentRef against the current head of the session log:

- If ParentRef matches the head, the tool MAY proceed and append a new operation.

- If ParentRef does not match the head, the tool MUST NOT silently proceed. It MUST return a deterministic "session divergence" result that includes the current head OpRef and sufficient log metadata for the caller to recover, resync, or start a new session.

The internal representation of OpRef/ParentRef MAY be a monotonic counter, a hash chain, or any other integrity mechanism; the tool MUST treat it as an ordering and coherence contract.

### 5.3 Transparency endpoints

The tool MUST expose operations that allow the host to retrieve, within a SessionID, a compact view of recent operations, including their OpRefs, operation types, parameters (redacted where necessary), and summaries of results. This includes at least: the last N operations, the current session head OpRef, and any known traversal anchors derived from prior list/query results.

This facility exists explicitly to recover from time-travel resets, compaction, crashes, multi-model handoffs, and user-forced truncation of host state.

## 6. Explicit continuation and pagination semantics

### 6.1 No implicit "continue"

Mailbox traversal operations MUST be explicit. The tool MUST NOT implement hidden continuation state that changes the meaning of an otherwise identical list/query request. There is no "continue" command whose semantics depend on opaque server-side cursors that the host did not supply.

Instead, every list/query request MUST include explicit continuation parameters describing the desired slice of the mailbox. Examples of acceptable explicit parameters include a time window, an anchor message identifier, an order direction, and a limit. The specific parameterization is an implementation choice, but the invariants are:

- The request fully specifies the intended range relative to explicit anchors.

- The response includes the explicit anchors that were actually used and the resulting bounds of returned items (e.g., min/max timestamps, min/max message IDs).

- The response includes sufficient data for the host to construct the next request without relying on hidden tool state.

### 6.2 Host behavior when the user says "continue"

When a user requests continuation using ambiguous language ("next page", "continue", "keep going"), the host MUST translate that into an explicit traversal request anchored on known bounds. If the host cannot reliably determine the anchor due to compaction, reset, or fork, it SHOULD consult the tool's session log transparency endpoints, infer the last observed bounds, and then issue an explicit anchored request.

The tool MAY offer convenience metadata such as "last observed page bounds" per session, but it MUST be treated as advisory data that the host then incorporates into explicit requests.

## 7. Multi-model workflow: summarize, categorize, investigate, return

### 7.1 Primary orchestration model

The primary model is responsible for user interaction, orchestration, and proposing actions. It calls the MCP tool to retrieve email metadata, invokes secondary models for summarization/categorization, and presents results and action proposals to the user.

### 7.2 Secondary classification model

A lightweight model is responsible for categorizing emails given limited inputs. It MUST be able to operate with only header-level data and small snippets, plus optional user-provided preferences and contact hints. It SHOULD produce structured outputs suitable for deterministic rendering and follow-up actions.

The system MUST support selecting different models for different phases. The categorization phase MUST be designed to work with a weaker/cheaper model, optionally escalating to stronger models only for ambiguous or high-risk cases.

### 7.3 Pluggable categories and user preference injection

Categorization MUST be driven by a pluggable category set configured outside the model, such as environment variables, configuration files, or tool-provided resources. Categories are user-defined and may include domain-specific groupings (e.g., development, school, medical, family), as well as risk-oriented bins (spam, unsolicited, phishing-suspected).

The host MAY provide the classifier with lightweight user context such as "who people are" (contact nicknames, known relationships, known organizations) and user preferences (what counts as actionable, what can be auto-archived). This context MUST be treated as guidance, not authoritative truth.

### 7.4 Optional investigation via follow-on tool calls

The classifier (or a dedicated investigation step) MAY initiate additional tool calls to improve risk assessment. Examples include checking whether a sender has been previously seen, whether a domain matches known correspondents, and whether content resembles common phishing patterns. These lookups MUST be logged under the current SessionID, with ParentRef enforcement, and MUST return explainable evidence summaries rather than opaque "trust me" labels.

### 7.5 Return contract to the primary model

The final output returned to the user MUST include: a categorized list of messages, the traversal bounds used, any notable risk flags with brief evidence, and a set of suggested next actions that are safe-by-default.

## 8. Action model: approvals, safety, and reversibility

### 8.1 User-in-the-loop for destructive and outbound actions

Actions that are destructive or externally visible MUST require explicit user approval. This includes, at minimum, sending emails and any irreversible deletion. The host MUST present a clear action proposal before execution and MUST capture the user's approval scope.

Approval scopes MUST support the following intents: approve once; approve for the current session; approve always (persistent) where appropriate. Persistent approvals MUST be revocable and discoverable.

### 8.2 Fine-grained approval for sending

Generating or sending messages on the user's behalf MUST be conservative. Sending SHOULD default to "approve one at a time" for each outbound message, with the user reviewing the final content. Draft creation MAY be less restricted than sending, but still SHOULD be explicit and logged.

### 8.3 Safe delete semantics

Delete operations SHOULD be implemented as reversible moves (e.g., moving to a trash or "delete after N days" mailbox) rather than hard deletes. If hard delete exists, it MUST be behind the strongest approval gates and SHOULD be disabled by default.

All actions MUST be recorded in the session log with message identifiers and resulting mailbox/state changes sufficient for recovery (including locating moved messages).

### 8.4 Idempotency and replay safety

Given time-travel resets and retries, the tool SHOULD provide idempotency behavior for actions where feasible, and MUST prevent ambiguous replays from silently applying twice. ParentRef mismatch handling is a primary defense; message-state preconditions are an additional defense.

## 9. Concurrency with external clients and multi-device reality

The external mail store MUST be treated as concurrently mutable by clients outside the tool. Therefore:

- List/query results are snapshots that can become stale.

- Actions may conflict with external changes (message already moved, deleted, marked read).

- The tool MUST surface conflicts explicitly and SHOULD provide enough detail for the host to resolve them (e.g., "already in target mailbox", "message not found", "state token changed").

The tool's session log is not a claim of exclusivity over the mailbox. It is a transparent record of what the tool attempted and observed, used to keep host behavior coherent under resets and forks.

## 10. Observability, recovery, and auditability

The tool MUST provide a compact, queryable record of recent operations per session. Each operation record SHOULD include: operation type; explicit parameters; mail store identifiers involved; observed result bounds; and any warnings or conflicts.

This record MUST enable recovery from scenarios including: the host reverting to an earlier conversational point; the host switching models mid-task; the host restarting; a user disputing an action ("undo that"); and partial completion where some messages were already moved or deleted-to-trash.

The tool MAY persist logs durably (e.g., local database) to survive restarts. If durability is implemented, the tool MUST make durability behavior explicit and SHOULD provide retention and privacy controls.

## 11. Prompting, skills, and test harness expectations

The system SHOULD package workflow guidance as reusable artifacts that the host can load, including: prompt templates for the primary model; prompt templates for the lightweight classifier; structured output schemas; and example transcripts that demonstrate the expected round-trip behavior (retrieve → summarize → categorize → propose actions → request approvals → execute → continue with explicit anchors).

These artifacts MUST reinforce the invariants of explicit continuation, session log integrity via ParentRef, and conservative approvals. They MUST treat tool session state as queryable evidence, not as implicit control flow.

A test harness SHOULD validate that the same mailbox traversal request with the same explicit anchors yields stable, explainable results, and that recovery from divergence (ParentRef mismatch) is deterministic.

## 12. Acceptance scenarios

An implementation conforming to this RFC MUST support, at minimum, the following scenario class end-to-end:

A user requests mail triage. The host retrieves a bounded page of recent messages using explicit anchors, summarizes subjects and metadata, categorizes messages into user-configured categories plus risk bins, optionally investigates suspicious items via additional lookups, returns a categorized list with evidence and traversal bounds, then supports follow-up user commands to archive, mark read, move, delete-to-trash, flag for follow-up, draft a reply, and send a reply with appropriate approvals. The user can request "next page" continuation, and the host issues a new explicit anchored request. If the host is reset to an earlier state and repeats or diverges, the tool detects ParentRef mismatch, exposes the session log, and enables safe resynchronization without silent repeated destructive actions.

## 13. Security and safety considerations

Because tool outputs can contain untrusted content (including prompt injection attempts embedded in emails), the host and tool MUST treat email content as data, not instructions. The tool SHOULD minimize content returned by default (headers and short snippets) and only retrieve full bodies when explicitly requested and justified. Credentials and account access MUST be least-privilege, and all externally visible or destructive actions MUST be gated by explicit, logged approvals with clear scope.

The session log transparency mechanism is a safety feature, not merely observability: it enables deterministic recovery under resets, prevents silent continuation surprises, and supports post-incident audit and undo workflows where possible.

---

## Appendix A: State Transparency in Tooling (No Implicit State)

In modern agent workflows — like distributed systems — LLMs can compact, truncate, or even reset history to prior states, similar to time-travel in version control. Meanwhile, the tool interacts with a stable external state (like a JMAP mailbox) and must maintain its session's history as immutable logs, much like distributed systems track state with vector clocks. Therefore:

- The tool will not hide state. Instead, it tracks each session's commands as an immutable log of actions (e.g., "last processed timestamp," "last message ID").

- Every action must explicitly state where it continues from (e.g., "process from timestamp X"), never implicitly.

- If the model loses context (due to compaction or time resets), it can query the tool's session log (e.g., "what was the last processed timestamp?").

- The tool will track session integrity by requiring a session ID and the last known command ID (like Git referencing prior hashes).

This ensures conversational ordering and consistency, even if the LLM is reset. If there's a mismatch, the tool will signal it, ensuring explicit recovery (e.g., "last command doesn't match; here's what was done previously"). In essence, we enforce distributed system-like integrity so the model always understands its state, even after resets.

---

## Addendum: Delayed and Scheduled Actions

### A1. Additions to terminology

The following terms are added:

**Action Execution Mode**
A per-action timing directive with the values:

- **ask**: propose an action plan to the user; do not execute or schedule.
- **immediate**: execute as soon as required approvals are satisfied.
- **delayed**: schedule execution for a later time according to an explicit delay specification.

**Delay Specification (DelaySpec)**
An explicit, caller-provided specification describing when a delayed action is eligible to run. A DelaySpec MAY be expressed as an absolute time, a relative delay, or a bounded window; the specific encoding is an implementation choice, but it MUST be unambiguous and MUST include a timezone or reference frame where applicable.

**Action Ledger (Event List)**
A queryable list of action events maintained by the tool, covering pending scheduled actions and their eventual outcomes. The ledger is intended to be readable outside the immediate conversational context and usable for recovery after host resets, forks, compaction, or restarts.

### A2. Action timing requirements

#### A2.1 Per-action timing MUST be explicit

Every action request that can reasonably be deferred (including, but not limited to, move, archive, mark-read, delete-to-trash, draft creation, and sending messages) MUST support an explicit Action Execution Mode: ask, immediate, or delayed.

The host MUST NOT rely on hidden defaults for timing. If a default timing preference exists, it MUST be surfaced to the model and user, and the resulting mode MUST be recorded explicitly in the tool request and tool log.

#### A2.2 Delayed actions require explicit DelaySpec

If Action Execution Mode is delayed, the request MUST include a DelaySpec. The tool MUST record the DelaySpec verbatim (or in a normalized equivalent form) in:

- the per-session immutable operation log entry, and
- the Action Ledger entry.

The tool MUST NOT interpret "delayed" as "run whenever" without an explicit delay specification.

#### A2.3 "Ask" mode is a first-class planning operation

If Action Execution Mode is ask, the tool MUST NOT schedule or execute the action. Instead, it SHOULD return a structured proposal suitable for user review, including:

- the concrete action that would be taken,
- the target message identifiers,
- the required approvals,
- and (if applicable) a suggested DelaySpec.

### A3. Scheduler and Action Ledger behavior

#### A3.1 Tool MUST expose an Action Ledger

The tool MUST provide a transparency mechanism to list action events, including at least:

- pending scheduled actions,
- executed actions (with execution time and summary),
- cancelled actions,
- failed actions (with reason and last observed state).

This ledger is intended to be consulted by the host when the user resumes work, when the host has been time-travel reset, or when multiple devices/agents may have initiated actions.

#### A3.2 Ledger entries MUST be linkable to session history

Each Action Ledger entry MUST include references sufficient to correlate it with:

- the SessionID under which it was created,
- the OpRef of the log entry that created/scheduled it,
- and the OpRef (or equivalent) of the log entry that executed, cancelled, or otherwise resolved it.

This ensures delayed actions remain comprehensible and auditable even if the host's conversational history is truncated or forked.

#### A3.3 Scheduling and execution are separate logged operations

Scheduling a delayed action MUST append an operation to the session's immutable log.

Executing a delayed action MUST append a distinct operation to the same session log (or to an explicitly identified execution context that is still transparently linkable back to the originating SessionID and OpRef). Execution MUST NOT occur "silently" without producing a corresponding log entry and ledger state transition.

#### A3.4 Durability and restart behavior

If delayed actions are supported, the tool SHOULD support durable storage of:

- pending scheduled actions and their DelaySpecs,
- and sufficient ledger history to explain outcomes after restarts.

If durable storage is implemented, the tool MUST make durability behavior explicit and MUST ensure that delayed actions are not lost or spuriously duplicated across restarts.

### A4. Ordering, integrity, and replay safety for delayed actions

#### A4.1 ParentRef requirements apply to scheduling operations

Creating/scheduling an action that depends on a prior mailbox view MUST obey the existing ParentRef / OpRef integrity rules:

- The scheduling request MUST include ParentRef.
- ParentRef mismatch MUST produce a divergence response rather than silently scheduling against an unknown state.

#### A4.2 Execution-time revalidation is required

Because the external mail store may change between scheduling and execution (including changes by other devices or agents), the tool MUST revalidate preconditions at execution time where practical. Examples:

- A message targeted for move/delete may no longer exist or may already be moved.
- A draft intended to be sent may have been edited or invalidated.

Conflicts MUST be surfaced as explicit execution results and ledger updates, not silently ignored.

#### A4.3 Idempotency and duplicate prevention

The tool SHOULD prevent accidental duplicate execution of delayed actions (e.g., due to retries, races, or host resets) using an explicit action identifier, integrity linkage, and/or other mechanism. At minimum:

- the ledger MUST make duplicate attempts visible, and
- the tool MUST avoid silently applying an action multiple times.

### A5. Approvals for delayed actions

#### A5.1 Approval applies to both scheduling and execution semantics

For actions requiring user approval (especially outbound send and irreversible deletion), approvals MUST be explicit about what is being authorized, including:

- whether approval authorizes scheduling only, execution only, or both scheduling and later execution,
- and the scope (once / session / always) where supported.

The system MUST NOT allow "delay" to bypass the conservative approval requirements for destructive or externally visible actions.

#### A5.2 Sending remains conservative under delay

Even when Action Execution Mode is delayed, sending email MUST remain user-controlled. The design SHOULD default to:

- explicit per-message approval of final content prior to execution,
- with delayed send treated as a scheduled execution of an already-reviewed artifact (e.g., a draft).

### A6. Acceptance scenario extensions

A conforming implementation MUST support the following additional behaviors:

- The user can request that certain actions occur later (e.g., "delete-to-trash these in 2 hours" or "send this tomorrow morning"), and the host issues an explicit delayed action request containing a DelaySpec.

- The tool records the scheduled action in the session log and in the Action Ledger.

- The user (or host) can list pending scheduled actions via the ledger and cancel or modify them with appropriate approvals.

- After a host reset, fork, or time-travel revert, the host can recover understanding of scheduled actions by consulting the Action Ledger and session logs, without relying on implicit continuation state.
