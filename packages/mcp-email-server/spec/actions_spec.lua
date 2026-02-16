-- Approval Gate and Action Execution Tests
-- Tests app/approval.lua: new, requires_approval, is_approved, approve, revoke,
--                         list_persistent, clear_session, gate

package.path = "./app/?.lua;" .. package.path
local approval = require("approval")

-- Config matching structure from app/config.lua approval section
local function default_config()
  return {
    require_approval = {
      send = true,
      delete_hard = true,
    },
    safe_actions = {
      archive = true,
      trash = true,
      mark_read = true,
      mark_unread = true,
    },
    default_scope = "once",
  }
end

-- ──────────────────────────────────────────────
-- M.new — construction
-- ──────────────────────────────────────────────
describe("approval.new", function()

  it("returns a manager table", function()
    local mgr = approval.new(default_config())
    assert.is_table(mgr)
  end)

  it("creates independent managers", function()
    local m1 = approval.new(default_config())
    local m2 = approval.new(default_config())
    m1.approve("s1", "send", "always")
    assert.is_false(m2.is_approved("s1", "send"))
  end)

  it("uses defaults when config fields are missing", function()
    local mgr = approval.new({})
    -- With empty config, unknown actions default-deny (require approval)
    assert.is_true(mgr.requires_approval("send"))
    assert.is_true(mgr.requires_approval("archive"))
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.requires_approval
-- ──────────────────────────────────────────────
describe("mgr.requires_approval", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  it("returns true for send", function()
    assert.is_true(mgr.requires_approval("send"))
  end)

  it("returns true for delete_hard", function()
    assert.is_true(mgr.requires_approval("delete_hard"))
  end)

  it("returns false for archive (safe action)", function()
    assert.is_false(mgr.requires_approval("archive"))
  end)

  it("returns false for trash (safe action)", function()
    assert.is_false(mgr.requires_approval("trash"))
  end)

  it("returns false for mark_read (safe action)", function()
    assert.is_false(mgr.requires_approval("mark_read"))
  end)

  it("returns true for an unknown action (default-deny)", function()
    assert.is_true(mgr.requires_approval("unknown_action"))
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.is_approved
-- ──────────────────────────────────────────────
describe("mgr.is_approved", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  it("returns true for safe actions regardless of session", function()
    assert.is_true(mgr.is_approved("any_session", "archive"))
    assert.is_true(mgr.is_approved("any_session", "trash"))
    assert.is_true(mgr.is_approved("any_session", "mark_read"))
    assert.is_true(mgr.is_approved("any_session", "mark_unread"))
  end)

  it("returns false for unapproved dangerous action", function()
    assert.is_false(mgr.is_approved("s1", "send"))
    assert.is_false(mgr.is_approved("s1", "delete_hard"))
  end)

  it("returns true after persistent approval", function()
    mgr.approve("s1", "send", "always")
    assert.is_true(mgr.is_approved("s1", "send"))
    -- Also approved for other sessions
    assert.is_true(mgr.is_approved("s2", "send"))
  end)

  it("returns true after session approval for same session", function()
    mgr.approve("s1", "send", "session")
    assert.is_true(mgr.is_approved("s1", "send"))
  end)

  it("returns false after session approval for different session", function()
    mgr.approve("s1", "send", "session")
    assert.is_false(mgr.is_approved("s2", "send"))
  end)

  it("returns false for unknown action that is not safe", function()
    assert.is_false(mgr.is_approved("s1", "fly_to_moon"))
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.approve
-- ──────────────────────────────────────────────
describe("mgr.approve", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  it("returns an approval record with expected fields", function()
    local rec = mgr.approve("s1", "send", "once", {msg_id = "m1"})
    assert.is_table(rec)
    assert.are.equal("s1", rec.session_id)
    assert.are.equal("send", rec.action)
    assert.are.equal("once", rec.scope)
    assert.is_number(rec.timestamp)
    assert.are.equal("m1", rec.details.msg_id)
  end)

  it("uses default_scope when scope is nil", function()
    local rec = mgr.approve("s1", "send", nil)
    assert.are.equal("once", rec.scope) -- default_scope from config
  end)

  it("stores session-scoped approval", function()
    mgr.approve("s1", "send", "session")
    assert.is_true(mgr.is_approved("s1", "send"))
    assert.is_false(mgr.is_approved("s2", "send"))
  end)

  it("stores persistent (always) approval", function()
    mgr.approve("s1", "send", "always")
    assert.is_true(mgr.is_approved("s1", "send"))
    assert.is_true(mgr.is_approved("s2", "send"))
  end)

  it("once scope does not persist in any store", function()
    mgr.approve("s1", "send", "once")
    -- "once" means no storage; caller handles single-use
    assert.is_false(mgr.is_approved("s1", "send"))
  end)

  it("can approve multiple actions for the same session", function()
    mgr.approve("s1", "send", "session")
    mgr.approve("s1", "delete_hard", "session")
    assert.is_true(mgr.is_approved("s1", "send"))
    assert.is_true(mgr.is_approved("s1", "delete_hard"))
  end)

  it("details can be nil", function()
    local rec = mgr.approve("s1", "send", "once", nil)
    assert.is_nil(rec.details)
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.revoke
-- ──────────────────────────────────────────────
describe("mgr.revoke", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  it("revokes a persistent approval", function()
    mgr.approve("s1", "send", "always")
    assert.is_true(mgr.is_approved("s1", "send"))
    local ok = mgr.revoke("send")
    assert.is_true(ok)
    assert.is_false(mgr.is_approved("s1", "send"))
  end)

  it("returns true even when revoking a non-existent approval", function()
    local ok = mgr.revoke("never_approved")
    assert.is_true(ok)
  end)

  it("does not affect session-scoped approvals", function()
    mgr.approve("s1", "send", "session")
    mgr.revoke("send")
    -- session approval is separate from persistent
    assert.is_true(mgr.is_approved("s1", "send"))
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.list_persistent
-- ──────────────────────────────────────────────
describe("mgr.list_persistent", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  it("returns empty list when no persistent approvals", function()
    local list = mgr.list_persistent()
    assert.is_table(list)
    assert.are.equal(0, #list)
  end)

  it("lists all persistent approvals", function()
    mgr.approve("s1", "send", "always")
    mgr.approve("s1", "delete_hard", "always")
    local list = mgr.list_persistent()
    assert.are.equal(2, #list)
    -- Check both actions present (order not guaranteed from pairs)
    table.sort(list)
    assert.are.equal("delete_hard", list[1])
    assert.are.equal("send", list[2])
  end)

  it("does not include session-scoped approvals", function()
    mgr.approve("s1", "send", "session")
    local list = mgr.list_persistent()
    assert.are.equal(0, #list)
  end)

  it("does not include once-scoped approvals", function()
    mgr.approve("s1", "send", "once")
    local list = mgr.list_persistent()
    assert.are.equal(0, #list)
  end)

  it("reflects revocations", function()
    mgr.approve("s1", "send", "always")
    mgr.revoke("send")
    local list = mgr.list_persistent()
    assert.are.equal(0, #list)
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.clear_session
-- ──────────────────────────────────────────────
describe("mgr.clear_session", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  it("removes session approvals for the given session", function()
    mgr.approve("s1", "send", "session")
    assert.is_true(mgr.is_approved("s1", "send"))
    mgr.clear_session("s1")
    assert.is_false(mgr.is_approved("s1", "send"))
  end)

  it("does not affect other sessions", function()
    mgr.approve("s1", "send", "session")
    mgr.approve("s2", "send", "session")
    mgr.clear_session("s1")
    assert.is_false(mgr.is_approved("s1", "send"))
    assert.is_true(mgr.is_approved("s2", "send"))
  end)

  it("does not affect persistent approvals", function()
    mgr.approve("s1", "send", "always")
    mgr.clear_session("s1")
    assert.is_true(mgr.is_approved("s1", "send"))
  end)

  it("is safe to call for a session that has no approvals", function()
    -- Should not error
    mgr.clear_session("nonexistent")
  end)
end)

-- ──────────────────────────────────────────────
-- mgr.gate
-- ──────────────────────────────────────────────
describe("mgr.gate", function()

  local mgr

  before_each(function()
    mgr = approval.new(default_config())
  end)

  -- ── safe actions pass through ──
  it("allows safe actions without approval", function()
    local ok = mgr.gate("s1", "archive", nil)
    assert.is_true(ok)
  end)

  it("allows trash without approval", function()
    local ok = mgr.gate("s1", "trash", nil)
    assert.is_true(ok)
  end)

  -- ── dangerous actions blocked ──
  it("blocks send without approval", function()
    local ok, info = mgr.gate("s1", "send", nil)
    assert.is_false(ok)
    assert.is_table(info)
    assert.are.equal("send", info.action)
    assert.is_true(info.requires_approval)
    assert.matches("requires explicit approval", info.message)
    assert.is_table(info.available_scopes)
  end)

  it("blocks delete_hard without approval", function()
    local ok, info = mgr.gate("s1", "delete_hard", nil)
    assert.is_false(ok)
    assert.are.equal("delete_hard", info.action)
  end)

  -- ── inline approval ──
  it("allows action when approval provided inline", function()
    local ok = mgr.gate("s1", "send", {scope = "once"})
    assert.is_true(ok)
  end)

  it("stores session-scoped inline approval for future calls", function()
    local ok = mgr.gate("s1", "send", {scope = "session"})
    assert.is_true(ok)
    -- Now the same session should be pre-approved
    local ok2 = mgr.gate("s1", "send", nil)
    assert.is_true(ok2)
  end)

  it("stores always-scoped inline approval for future calls", function()
    local ok = mgr.gate("s1", "send", {scope = "always"})
    assert.is_true(ok)
    -- Other sessions also approved
    local ok2 = mgr.gate("s2", "send", nil)
    assert.is_true(ok2)
  end)

  -- ── pre-existing approval ──
  it("allows action when persistent approval already exists", function()
    mgr.approve("s1", "send", "always")
    local ok = mgr.gate("s1", "send", nil)
    assert.is_true(ok)
  end)

  it("allows action when session approval already exists", function()
    mgr.approve("s1", "send", "session")
    local ok = mgr.gate("s1", "send", nil)
    assert.is_true(ok)
  end)

  -- ── unknown actions (default-deny) ──
  it("blocks unknown action (default-deny for safety)", function()
    local ok, info = mgr.gate("s1", "unknown_action", nil)
    assert.is_false(ok)
    assert.is_table(info)
    assert.is_true(info.requires_approval)
  end)

  -- ── rejection info structure ──
  it("rejection info includes available_scopes", function()
    local ok, info = mgr.gate("s1", "send", nil)
    assert.is_false(ok)
    assert.same({"once", "session", "always"}, info.available_scopes)
  end)

  -- ── inline approval with details ──
  it("passes details from inline approval to approve", function()
    mgr.gate("s1", "send", {scope = "session", details = {msg = "m1"}})
    -- The approval was stored; we can verify via is_approved
    assert.is_true(mgr.is_approved("s1", "send"))
  end)
end)
