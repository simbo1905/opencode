-- Session Log and ParentRef Integrity Tests
-- Derived from packages/mcp-email-server/test/session.test.ts (TS spec reference)

package.path = package.path .. ";./app/?.lua"
local session = require("session")

describe("Session Management", function()

  local mgr

  before_each(function()
    math.randomseed(os.time())
    mgr = session.new()
  end)

  it("allocates unique SessionID on creation", function()
    local s1 = mgr.create()
    local s2 = mgr.create()
    assert.is_not_nil(s1)
    assert.is_not_nil(s2)
    assert.are_not.equal(s1, s2)
    assert.are.equal(0, mgr.length(s1))
    assert.are.equal(0, mgr.length(s2))
  end)

  it("appends operations to the session log in order", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "list_messages", {time_start = 1000})
    local e2 = mgr.append(sid, e1.opref, "archive_message", {msg_id = "m1"})
    local e3 = mgr.append(sid, e2.opref, "mark_read", {msg_id = "m2"})
    assert.are.equal(3, mgr.length(sid))
    local log = mgr.full_log(sid)
    assert.are.equal("list_messages", log[1].operation)
    assert.are.equal("archive_message", log[2].operation)
    assert.are.equal("mark_read", log[3].operation)
  end)

  it("returns OpRef for each operation", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "list_messages", {})
    assert.is_not_nil(e1.opref)
    assert.is_string(e1.opref)
    local e2 = mgr.append(sid, e1.opref, "archive_message", {})
    assert.is_not_nil(e2.opref)
    assert.are_not.equal(e1.opref, e2.opref)
  end)

  it("detects ParentRef mismatch and returns divergence", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "list_messages", {})
    local e2 = mgr.append(sid, e1.opref, "archive_message", {})
    -- Submit with stale parentref (e1 instead of e2)
    local result, div = mgr.append(sid, e1.opref, "mark_read", {})
    assert.is_nil(result)
    assert.is_table(div)
    assert.are.equal("divergence_detected", div.operation)
    assert.are.equal(e2.opref, div.current_head_opref)
    assert.are.equal(e1.opref, div.caller_parentref)
    assert.is_true(#div.divergence.operations_between > 0)
  end)

  it("allows ParentRef match and appends new operation", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "list_messages", {})
    local e2 = mgr.append(sid, e1.opref, "archive_message", {})
    assert.is_not_nil(e2)
    assert.are.equal(e1.opref, e2.parentref)
  end)

  it("rejects request with wrong ParentRef (does not silently proceed)", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "list_messages", {})
    mgr.append(sid, e1.opref, "archive_message", {})
    -- Try with stale parentref
    local result, div = mgr.append(sid, e1.opref, "move_message", {})
    assert.is_nil(result)
    assert.are.equal("divergence_detected", div.operation)
    -- Log should still have only 2 entries (rejected op not added)
    assert.are.equal(2, mgr.length(sid))
  end)

  it("supports querying session log by OpRef", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "list_messages", {time_start = 1000})
    local e2 = mgr.append(sid, e1.opref, "archive_message", {msg_id = "m1"})
    local found = mgr.get_entry(sid, e2.opref)
    assert.is_not_nil(found)
    assert.are.equal("archive_message", found.operation)
    assert.are.equal("m1", found.parameters.msg_id)
  end)

  it("supports querying recent operations in the session", function()
    local sid = mgr.create()
    local prev = nil
    for i = 1, 5 do
      local e = mgr.append(sid, prev, "op_" .. i, {})
      prev = e.opref
    end
    local recent = mgr.recent(sid, 3)
    assert.are.equal(3, #recent)
    -- Most recent first
    assert.are.equal("op_5", recent[1].operation)
    assert.are.equal("op_4", recent[2].operation)
    assert.are.equal("op_3", recent[3].operation)
  end)

  it("supports querying current session head OpRef", function()
    local sid = mgr.create()
    assert.is_nil(mgr.head(sid))
    local e1 = mgr.append(sid, nil, "list_messages", {})
    assert.are.equal(e1.opref, mgr.head(sid))
    local e2 = mgr.append(sid, e1.opref, "archive_message", {})
    assert.are.equal(e2.opref, mgr.head(sid))
  end)

  it("supports multiple concurrent sessions with separate logs", function()
    local sa = mgr.create()
    local sb = mgr.create()
    local ea = mgr.append(sa, nil, "list_a", {})
    local eb = mgr.append(sb, nil, "list_b", {})
    assert.are.equal(1, mgr.length(sa))
    assert.are.equal(1, mgr.length(sb))
    -- Cross-session parentref should fail
    local result, div = mgr.append(sb, ea.opref, "bad_op", {})
    assert.is_nil(result)
    assert.are.equal("divergence_detected", div.operation)
  end)

  it("does not allow log branches within a SessionID", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "op_1", {})
    local e2 = mgr.append(sid, e1.opref, "op_2", {})
    -- Two conflicting requests both with parentref = e1
    local e3 = mgr.append(sid, e2.opref, "op_3", {})
    assert.is_not_nil(e3)
    local result, div = mgr.append(sid, e1.opref, "op_3_alt", {})
    assert.is_nil(result)
    assert.are.equal("divergence_detected", div.operation)
    assert.are.equal(3, mgr.length(sid))
  end)

end)

describe("Divergence Recovery", function()

  local mgr

  before_each(function()
    math.randomseed(os.time())
    mgr = session.new()
  end)

  it("provides intervening operations in divergence response", function()
    local sid = mgr.create()
    local prev = nil
    local oprefs = {}
    for i = 1, 5 do
      local e = mgr.append(sid, prev, "op_" .. i, {})
      oprefs[i] = e.opref
      prev = e.opref
    end
    -- Submit with stale parentref (op_2, head is op_5)
    local result, div = mgr.append(sid, oprefs[2], "late_op", {})
    assert.is_nil(result)
    assert.are.equal(3, #div.divergence.operations_between)
    assert.are.equal(oprefs[3], div.divergence.operations_between[1].opref)
    assert.are.equal(oprefs[4], div.divergence.operations_between[2].opref)
    assert.are.equal(oprefs[5], div.divergence.operations_between[3].opref)
  end)

  it("enables caller to resync after divergence by using new ParentRef", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "op_1", {})
    local e2 = mgr.append(sid, e1.opref, "op_2", {})
    -- Cause divergence
    local _, div = mgr.append(sid, e1.opref, "stale_op", {})
    assert.are.equal(e2.opref, div.current_head_opref)
    -- Resync using the head from divergence response
    local e3 = mgr.append(sid, div.current_head_opref, "resynced_op", {})
    assert.is_not_nil(e3)
    assert.are.equal("resynced_op", e3.operation)
  end)

  it("provides recovery advice in divergence response", function()
    local sid = mgr.create()
    local e1 = mgr.append(sid, nil, "op_1", {})
    mgr.append(sid, e1.opref, "op_2", {})
    local _, div = mgr.append(sid, e1.opref, "stale_op", {})
    assert.is_not_nil(div.recovery_advice)
    assert.is_string(div.recovery_advice)
    assert.is_true(#div.recovery_advice > 0)
  end)

  it("supports creating new session as recovery path", function()
    local sa = mgr.create()
    mgr.append(sa, nil, "op_1", {})
    -- Create new session as recovery
    local sb = mgr.create()
    assert.are_not.equal(sa, sb)
    assert.are.equal(0, mgr.length(sb))
    local e = mgr.append(sb, nil, "fresh_start", {})
    assert.is_not_nil(e)
    assert.are.equal("fresh_start", e.operation)
  end)

end)
