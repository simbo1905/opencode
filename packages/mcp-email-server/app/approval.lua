-- Approval Gate Module
-- Implements RFC §6: User Approval for Irreversible Actions
--
-- Key principles:
--   - Sends and hard-deletes require explicit approval
--   - Archive and trash are safe (reversible) and don't need approval
--   - Approval scopes: "once" (this message), "session" (this session), "always" (persistent)
--   - "always" approvals are discoverable and revocable

local M = {}

-- Create a new approval manager
function M.new(config_approval)
  local mgr = {}

  -- Approval configuration from config.lua
  local require_approval = config_approval.require_approval or {}
  local safe_actions = config_approval.safe_actions or {}
  local default_scope = config_approval.default_scope or "once"

  -- In-memory approval store
  -- session_approvals[sid] = { action_type = true }  (session scope)
  -- persistent_approvals = { action_type = true }     (always scope)
  local session_approvals = {}
  local persistent_approvals = {}

  -- Check if an action requires approval
  function mgr.requires_approval(action)
    if safe_actions[action] then
      return false
    end
    if require_approval[action] then
      return true
    end
    return false
  end

  -- Check if approval has been granted
  function mgr.is_approved(sid, action)
    -- Safe actions are always approved
    if safe_actions[action] then
      return true
    end

    -- Check persistent approvals
    if persistent_approvals[action] then
      return true
    end

    -- Check session approvals
    if session_approvals[sid] and session_approvals[sid][action] then
      return true
    end

    return false
  end

  -- Grant approval for an action
  -- scope: "once" | "session" | "always"
  -- Returns: approval record
  function mgr.approve(sid, action, scope, details)
    scope = scope or default_scope

    local record = {
      session_id = sid,
      action = action,
      scope = scope,
      timestamp = os.time(),
      details = details,
    }

    if scope == "session" then
      if not session_approvals[sid] then
        session_approvals[sid] = {}
      end
      session_approvals[sid][action] = true
    elseif scope == "always" then
      persistent_approvals[action] = true
    end
    -- "once" scope: no storage needed, caller handles single-use

    return record
  end

  -- Revoke a persistent approval
  function mgr.revoke(action)
    persistent_approvals[action] = nil
    return true
  end

  -- List all persistent approvals (for discoverability)
  function mgr.list_persistent()
    local result = {}
    for action, _ in pairs(persistent_approvals) do
      result[#result + 1] = action
    end
    return result
  end

  -- Clear session approvals (on session end)
  function mgr.clear_session(sid)
    session_approvals[sid] = nil
  end

  -- Validate and gate an action
  -- Returns: true if action can proceed
  -- Returns: false, rejection_info if approval needed
  function mgr.gate(sid, action, approval)
    if not mgr.requires_approval(action) then
      return true
    end

    -- Check existing approvals
    if mgr.is_approved(sid, action) then
      return true
    end

    -- If approval provided in this request, process it
    if approval then
      mgr.approve(sid, action, approval.scope, approval.details)
      return true
    end

    -- Rejection: approval required
    return false, {
      action = action,
      requires_approval = true,
      message = string.format("Action '%s' requires explicit approval", action),
      available_scopes = {"once", "session", "always"},
    }
  end

  return mgr
end

return M
