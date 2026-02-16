-- Approval Gate and Action Execution Tests
-- Derived from packages/mcp-email-server/test/approvals.test.ts (TS spec reference)

describe("Approval Requirements", function()

  pending("rejects send without explicit approval")
  pending("rejects delete-to-trash without explicit approval")
  pending("allows archive without approval (safe operation)")
  pending("accepts send with explicit approval")
  pending("records approval in session log")

end)

describe("Approval Scopes", function()

  pending("supports once scope (approve this message only)")
  pending("supports session scope (approve all actions in this session)")
  pending("supports always scope (persistent approval)")
  pending("makes always approval discoverable and revocable")

end)

describe("Fine-grained Send Approval", function()

  pending("requires per-message approval for sending")
  pending("allows draft creation without send approval")
  pending("requires approval to send a draft")
  pending("shows full message content for approval before sending")

end)

describe("Safe Delete Semantics", function()

  pending("maps delete-to-trash to reversible move")
  pending("requires strong approval for hard-delete")
  pending("disables hard-delete by default (via config)")
  pending("allows hard-delete only if explicitly enabled")
  pending("records delete action and result in session log")

end)

describe("Action Execution Logging", function()

  pending("logs all actions (archive, move, send, delete) to session log")
  pending("includes message identifiers in action logs")
  pending("includes action result (success/conflict) in log entry")

end)
