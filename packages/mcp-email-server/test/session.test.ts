import { describe, it, expect } from "bun:test"

/**
 * Session Log and ParentRef Integrity Tests
 *
 * These tests validate session management, operation logs, and divergence detection.
 * DO NOT RUN YET — implementation will fill these in.
 */

describe("Session Management", () => {
  it.todo("allocates unique SessionID on creation")

  it.todo("appends operations to the session log in order")

  it.todo("returns OpRef for each operation")

  it.todo("detects ParentRef mismatch and returns divergence")

  it.todo("allows ParentRef match and appends new operation")

  it.todo("rejects request with wrong ParentRef (does not silently proceed)")

  it.todo("supports querying session log by OpRef")

  it.todo("supports querying recent operations in the session")

  it.todo("supports querying current session head OpRef")

  it.todo("supports multiple concurrent sessions with separate logs")

  it.todo("does not allow log branches within a SessionID")
})

describe("Divergence Recovery", () => {
  it.todo("provides intervening operations in divergence response")

  it.todo("enables caller to resync after divergence by using new ParentRef")

  it.todo("provides recovery advice in divergence response")

  it.todo("supports creating new session as recovery path")
})
