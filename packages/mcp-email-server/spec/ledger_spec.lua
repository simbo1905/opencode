-- Action Ledger and Delayed Action Tests
-- Tests app/ledger.lua: new, schedule, execute, set_result, cancel, query, get, counts

package.path = "./app/?.lua;" .. package.path
local ledger = require("ledger")

-- ──────────────────────────────────────────────
-- Module-level constants
-- ──────────────────────────────────────────────
describe("ledger constants", function()

  it("exports PENDING state", function()
    assert.are.equal("pending", ledger.PENDING)
  end)

  it("exports EXECUTED state", function()
    assert.are.equal("executed", ledger.EXECUTED)
  end)

  it("exports CANCELLED state", function()
    assert.are.equal("cancelled", ledger.CANCELLED)
  end)

  it("exports FAILED state", function()
    assert.are.equal("failed", ledger.FAILED)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.new
-- ──────────────────────────────────────────────
describe("ledger.new", function()

  it("returns a ledger table", function()
    local l = ledger.new()
    assert.is_table(l)
  end)

  it("creates independent ledger instances", function()
    local l1 = ledger.new()
    local l2 = ledger.new()
    l1.schedule("s1", "op1", "send", {})
    assert.are.equal(0, #l2.query())
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.schedule
-- ──────────────────────────────────────────────
describe("ledger.schedule", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("returns an entry with a unique id", function()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    assert.is_string(e.id)
    assert.matches("^ledger_", e.id)
  end)

  it("increments id counter across calls", function()
    local e1 = l.schedule("s1", "op1", "send", {})
    local e2 = l.schedule("s1", "op2", "send", {})
    assert.are_not.equal(e1.id, e2.id)
  end)

  it("stores session_id and opref", function()
    local e = l.schedule("s1", "op1", "send", {})
    assert.are.equal("s1", e.session_id)
    assert.are.equal("op1", e.opref)
  end)

  it("stores action and params", function()
    local e = l.schedule("s1", "op1", "send", {to = "bob"})
    assert.are.equal("send", e.action)
    assert.are.equal("bob", e.params.to)
  end)

  it("defaults params to empty table when nil", function()
    local e = l.schedule("s1", "op1", "send", nil)
    assert.is_table(e.params)
    assert.are.equal(0, #e.params)
  end)

  it("starts in PENDING state", function()
    local e = l.schedule("s1", "op1", "send", {})
    assert.are.equal(ledger.PENDING, e.state)
  end)

  it("records scheduled_at timestamp", function()
    local e = l.schedule("s1", "op1", "send", {})
    assert.is_number(e.scheduled_at)
  end)

  it("has nil executed_at and result initially", function()
    local e = l.schedule("s1", "op1", "send", {})
    assert.is_nil(e.executed_at)
    assert.is_nil(e.result)
  end)

  it("starts with execution_attempts = 0", function()
    local e = l.schedule("s1", "op1", "send", {})
    assert.are.equal(0, e.execution_attempts)
  end)

  it("stores delay_spec", function()
    local spec = {delay_seconds = 60}
    local e = l.schedule("s1", "op1", "send", {}, spec)
    assert.same(spec, e.delay_spec)
  end)

  it("extracts preconditions from params", function()
    local e = l.schedule("s1", "op1", "send", {preconditions = {exists = true}})
    assert.same({exists = true}, e.preconditions)
  end)

  it("has nil preconditions when params lack them", function()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    assert.is_nil(e.preconditions)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.execute
-- ──────────────────────────────────────────────
describe("ledger.execute", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("transitions entry to EXECUTED state", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result = l.execute(e.id)
    assert.is_not_nil(result)
    assert.are.equal(ledger.EXECUTED, result.state)
  end)

  it("sets executed_at timestamp", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result = l.execute(e.id)
    assert.is_number(result.executed_at)
  end)

  it("increments execution_attempts", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id)
    assert.are.equal(1, e.execution_attempts)
  end)

  it("returns nil + error for non-existent id", function()
    local result, err = l.execute("ledger_999")
    assert.is_nil(result)
    assert.are.equal("entry not found", err)
  end)

  it("rejects execution of already-executed entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id)
    local result, err = l.execute(e.id)
    assert.is_nil(result)
    assert.is_table(err)
    assert.are.equal("duplicate_execution", err.error)
    assert.are.equal(e.id, err.entry_id)
    assert.are.equal(ledger.EXECUTED, err.current_state)
  end)

  it("rejects execution of cancelled entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.cancel(e.id)
    local result, err = l.execute(e.id)
    assert.is_nil(result)
    assert.is_table(err)
    assert.are.equal("duplicate_execution", err.error)
    assert.are.equal(ledger.CANCELLED, err.current_state)
  end)

  it("rejects execution of failed entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    -- Force failure via validate_fn
    l.execute(e.id, function() return nil, "precondition failed" end)
    assert.are.equal(ledger.FAILED, e.state)
    local result, err = l.execute(e.id)
    assert.is_nil(result)
    assert.is_table(err)
    assert.are.equal("duplicate_execution", err.error)
  end)

  -- ── validate_fn ──
  it("executes successfully when validate_fn returns true", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result = l.execute(e.id, function() return true end)
    assert.is_not_nil(result)
    assert.are.equal(ledger.EXECUTED, result.state)
  end)

  it("fails when validate_fn returns nil + conflict", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result, conflict = l.execute(e.id, function()
      return nil, "message deleted"
    end)
    assert.is_nil(result)
    assert.are.equal("message deleted", conflict)
    assert.are.equal(ledger.FAILED, e.state)
    assert.is_table(e.result)
    assert.is_false(e.result.ok)
    assert.are.equal("message deleted", e.result.conflict)
  end)

  it("increments execution_attempts even on failure", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id, function() return nil, "fail" end)
    assert.are.equal(1, e.execution_attempts)
  end)

  it("passes entry to validate_fn", function()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    local captured
    l.execute(e.id, function(entry)
      captured = entry
      return true
    end)
    assert.are.equal(e.id, captured.id)
    assert.are.equal("send", captured.action)
    assert.are.equal("alice", captured.params.to)
  end)

  it("executes without validate_fn (nil)", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result = l.execute(e.id, nil)
    assert.is_not_nil(result)
    assert.are.equal(ledger.EXECUTED, result.state)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.set_result
-- ──────────────────────────────────────────────
describe("ledger.set_result", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("sets result on an entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    local ok = l.set_result(e.id, {ok = true, message_id = "m1"})
    assert.is_true(ok)
    assert.same({ok = true, message_id = "m1"}, e.result)
  end)

  it("returns nil + error for non-existent id", function()
    local ok, err = l.set_result("ledger_999", {ok = true})
    assert.is_nil(ok)
    assert.are.equal("entry not found", err)
  end)

  it("can overwrite a previous result", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.set_result(e.id, {ok = true})
    l.set_result(e.id, {ok = false, error = "retry"})
    assert.is_false(e.result.ok)
    assert.are.equal("retry", e.result.error)
  end)

  it("works on entries in any state", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id)
    local ok = l.set_result(e.id, {ok = true})
    assert.is_true(ok)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.cancel
-- ──────────────────────────────────────────────
describe("ledger.cancel", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("cancels a pending entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result = l.cancel(e.id, "user requested")
    assert.is_not_nil(result)
    assert.are.equal(ledger.CANCELLED, result.state)
    assert.is_table(result.result)
    assert.is_false(result.result.ok)
    assert.are.equal("user requested", result.result.reason)
  end)

  it("uses default reason when none provided", function()
    local e = l.schedule("s1", "op1", "send", {})
    local result = l.cancel(e.id)
    assert.are.equal("cancelled", result.result.reason)
  end)

  it("returns nil + error for non-existent id", function()
    local result, err = l.cancel("ledger_999")
    assert.is_nil(result)
    assert.are.equal("entry not found", err)
  end)

  it("rejects cancelling an already-executed entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id)
    local result, err = l.cancel(e.id)
    assert.is_nil(result)
    assert.are.equal("can only cancel pending entries", err)
  end)

  it("rejects cancelling an already-cancelled entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.cancel(e.id)
    local result, err = l.cancel(e.id)
    assert.is_nil(result)
    assert.are.equal("can only cancel pending entries", err)
  end)

  it("rejects cancelling a failed entry", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id, function() return nil, "fail" end)
    local result, err = l.cancel(e.id)
    assert.is_nil(result)
    assert.are.equal("can only cancel pending entries", err)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.query
-- ──────────────────────────────────────────────
describe("ledger.query", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("returns empty list when ledger is empty", function()
    local result = l.query()
    assert.is_table(result)
    assert.are.equal(0, #result)
  end)

  it("returns all entries when no filter", function()
    l.schedule("s1", "op1", "send", {})
    l.schedule("s1", "op2", "archive", {})
    local result = l.query()
    assert.are.equal(2, #result)
  end)

  it("filters by state", function()
    local e1 = l.schedule("s1", "op1", "send", {})
    l.schedule("s1", "op2", "archive", {})
    l.execute(e1.id)
    local pending = l.query({state = ledger.PENDING})
    assert.are.equal(1, #pending)
    assert.are.equal("archive", pending[1].action)
    local executed = l.query({state = ledger.EXECUTED})
    assert.are.equal(1, #executed)
    assert.are.equal("send", executed[1].action)
  end)

  it("filters by session_id", function()
    l.schedule("s1", "op1", "send", {})
    l.schedule("s2", "op2", "archive", {})
    local result = l.query({session_id = "s1"})
    assert.are.equal(1, #result)
    assert.are.equal("s1", result[1].session_id)
  end)

  it("filters by action", function()
    l.schedule("s1", "op1", "send", {})
    l.schedule("s1", "op2", "archive", {})
    l.schedule("s1", "op3", "send", {})
    local result = l.query({action = "send"})
    assert.are.equal(2, #result)
  end)

  it("combines multiple filters", function()
    l.schedule("s1", "op1", "send", {})
    l.schedule("s2", "op2", "send", {})
    l.schedule("s1", "op3", "archive", {})
    local result = l.query({session_id = "s1", action = "send"})
    assert.are.equal(1, #result)
    assert.are.equal("s1", result[1].session_id)
    assert.are.equal("send", result[1].action)
  end)

  it("sorts results by scheduled_at descending", function()
    l.schedule("s1", "op1", "send", {})
    l.schedule("s1", "op2", "archive", {})
    l.schedule("s1", "op3", "trash", {})
    local result = l.query()
    -- All scheduled at roughly the same os.time(), but insertion order
    -- with same timestamp should still produce a valid sorted list
    for i = 1, #result - 1 do
      assert.is_true(result[i].scheduled_at >= result[i + 1].scheduled_at)
    end
  end)

  it("returns empty list when filter matches nothing", function()
    l.schedule("s1", "op1", "send", {})
    local result = l.query({state = ledger.CANCELLED})
    assert.are.equal(0, #result)
  end)

  it("accepts empty filter table (same as nil)", function()
    l.schedule("s1", "op1", "send", {})
    local result = l.query({})
    assert.are.equal(1, #result)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.get
-- ──────────────────────────────────────────────
describe("ledger.get", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("retrieves an entry by id", function()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    local got = l.get(e.id)
    assert.is_not_nil(got)
    assert.are.equal(e.id, got.id)
    assert.are.equal("send", got.action)
    assert.are.equal("alice", got.params.to)
  end)

  it("returns nil for non-existent id", function()
    local got = l.get("ledger_999")
    assert.is_nil(got)
  end)

  it("reflects state changes after execute", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id)
    local got = l.get(e.id)
    assert.are.equal(ledger.EXECUTED, got.state)
  end)

  it("reflects state changes after cancel", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.cancel(e.id, "changed mind")
    local got = l.get(e.id)
    assert.are.equal(ledger.CANCELLED, got.state)
  end)

  it("reflects state changes after failure", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id, function() return nil, "gone" end)
    local got = l.get(e.id)
    assert.are.equal(ledger.FAILED, got.state)
  end)
end)

-- ──────────────────────────────────────────────
-- ledger.counts
-- ──────────────────────────────────────────────
describe("ledger.counts", function()

  local l

  before_each(function()
    l = ledger.new()
  end)

  it("returns all-zero counts for empty ledger", function()
    local c = l.counts()
    assert.are.equal(0, c.pending)
    assert.are.equal(0, c.executed)
    assert.are.equal(0, c.cancelled)
    assert.are.equal(0, c.failed)
  end)

  it("counts pending entries", function()
    l.schedule("s1", "op1", "send", {})
    l.schedule("s1", "op2", "archive", {})
    local c = l.counts()
    assert.are.equal(2, c.pending)
    assert.are.equal(0, c.executed)
  end)

  it("counts executed entries", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id)
    local c = l.counts()
    assert.are.equal(0, c.pending)
    assert.are.equal(1, c.executed)
  end)

  it("counts cancelled entries", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.cancel(e.id)
    local c = l.counts()
    assert.are.equal(0, c.pending)
    assert.are.equal(1, c.cancelled)
  end)

  it("counts failed entries", function()
    local e = l.schedule("s1", "op1", "send", {})
    l.execute(e.id, function() return nil, "boom" end)
    local c = l.counts()
    assert.are.equal(0, c.pending)
    assert.are.equal(1, c.failed)
  end)

  it("tracks mixed states correctly", function()
    local e1 = l.schedule("s1", "op1", "send", {})
    local e2 = l.schedule("s1", "op2", "archive", {})
    local e3 = l.schedule("s1", "op3", "trash", {})
    l.schedule("s1", "op4", "delete_hard", {})
    l.execute(e1.id)
    l.cancel(e2.id)
    l.execute(e3.id, function() return nil, "fail" end)
    local c = l.counts()
    assert.are.equal(1, c.pending)
    assert.are.equal(1, c.executed)
    assert.are.equal(1, c.cancelled)
    assert.are.equal(1, c.failed)
  end)
end)

-- ──────────────────────────────────────────────
-- Integration: full lifecycle
-- ──────────────────────────────────────────────
describe("ledger lifecycle integration", function()

  it("schedule -> execute -> set_result full flow", function()
    local l = ledger.new()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    assert.are.equal(ledger.PENDING, e.state)

    local result = l.execute(e.id, function() return true end)
    assert.are.equal(ledger.EXECUTED, result.state)

    l.set_result(e.id, {ok = true, message_id = "sent_123"})
    local got = l.get(e.id)
    assert.are.equal("sent_123", got.result.message_id)
  end)

  it("schedule -> cancel flow", function()
    local l = ledger.new()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    local cancelled = l.cancel(e.id, "user cancelled")
    assert.are.equal(ledger.CANCELLED, cancelled.state)

    -- Cannot execute after cancel
    local result, err = l.execute(e.id)
    assert.is_nil(result)
    assert.is_table(err)
    assert.are.equal("duplicate_execution", err.error)
  end)

  it("schedule -> failed execution -> cannot re-execute", function()
    local l = ledger.new()
    local e = l.schedule("s1", "op1", "send", {to = "alice"})
    l.execute(e.id, function() return nil, "message deleted" end)
    assert.are.equal(ledger.FAILED, e.state)

    local result, err = l.execute(e.id)
    assert.is_nil(result)
    assert.is_table(err)
    assert.are.equal("duplicate_execution", err.error)
    assert.are.equal(ledger.FAILED, err.current_state)
  end)
end)
