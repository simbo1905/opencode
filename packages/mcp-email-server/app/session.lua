-- Session Management Module
--
-- Implements RFC sections 5.1-5.3:
--   - Multi-tenant sessions with unique SessionID
--   - Linear, append-only operation log per session
--   - OpRef / ParentRef integrity with divergence detection
--   - Transparency endpoints for recovery after resets
--
-- Usage:
--   local session = require("app.session")
--   local mgr = session.new()
--   local sid = mgr.create()
--   local result = mgr.append(sid, nil, "list_messages", {time_start = 1000})
--   -- result.opref, result.parentref, result.operation, ...

local M = {}

-- Session ID generator (16 chars, alphanumeric)
local function random_id()
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local id = {}
  for i = 1, 16 do
    local idx = math.random(1, #chars)
    id[i] = chars:sub(idx, idx)
  end
  return table.concat(id)
end

-- OpRef is a monotonic counter per session (simple, deterministic)
-- Format: "op_<counter>" e.g. "op_1", "op_2", ...

local function make_opref(sid, counter)
  return sid .. "_op_" .. tostring(counter)
end

-- Create a new session manager instance
-- All state is held in the returned table (no globals)
function M.new()
  local mgr = {}
  local sessions = {}

  -- Create a new session, return SessionID
  function mgr.create()
    local sid = random_id()
    sessions[sid] = {
      log = {},       -- ordered list of log entries
      counter = 0,    -- monotonic OpRef counter
      head = nil,     -- current head OpRef (nil when empty)
    }
    return sid
  end

  -- Check if a session exists
  function mgr.exists(sid)
    return sessions[sid] ~= nil
  end

  -- Get current head OpRef for a session
  function mgr.head(sid)
    local s = sessions[sid]
    if not s then return nil, "session not found" end
    return s.head
  end

  -- Get log length for a session
  function mgr.length(sid)
    local s = sessions[sid]
    if not s then return nil, "session not found" end
    return #s.log
  end

  -- Append an operation to the session log
  -- Returns: {opref, parentref, operation, parameters, timestamp} on success
  -- Returns: nil, divergence_response on ParentRef mismatch
  -- Returns: nil, error_string on other errors
  function mgr.append(sid, parentref, operation, parameters)
    local s = sessions[sid]
    if not s then return nil, "session not found" end

    -- ParentRef check (RFC 5.2)
    -- First operation: parentref must be nil
    -- Subsequent operations: parentref must match current head
    if s.head == nil then
      if parentref ~= nil then
        return nil, {
          operation = "divergence_detected",
          session_id = sid,
          current_head_opref = nil,
          caller_parentref = parentref,
          divergence = {
            reason = "session is empty; parentref must be nil for first operation",
            operations_between = {},
          },
          recovery_advice = "Start with parentref=nil for the first operation",
        }
      end
    else
      if parentref ~= s.head then
        -- Collect intervening operations
        local between = {}
        local found_caller = false
        for _, entry in ipairs(s.log) do
          if found_caller then
            between[#between + 1] = {
              opref = entry.opref,
              operation = entry.operation,
              timestamp = entry.timestamp,
            }
          end
          if entry.opref == parentref then
            found_caller = true
          end
        end
        -- If caller's parentref wasn't found at all, return all ops
        if not found_caller then
          for _, entry in ipairs(s.log) do
            between[#between + 1] = {
              opref = entry.opref,
              operation = entry.operation,
              timestamp = entry.timestamp,
            }
          end
        end
        return nil, {
          operation = "divergence_detected",
          session_id = sid,
          current_head_opref = s.head,
          caller_parentref = parentref,
          divergence = {
            reason = "session has advanced; caller's parentref is stale",
            operations_between = between,
          },
          recovery_advice = "Review intervening operations, or start fresh request with current_head_opref as new parentref",
        }
      end
    end

    -- Append operation
    s.counter = s.counter + 1
    local opref = make_opref(sid, s.counter)
    local entry = {
      opref = opref,
      parentref = parentref,
      timestamp = os.time(),
      operation = operation,
      parameters = parameters or {},
      result = nil,  -- filled in by caller after execution
    }
    s.log[#s.log + 1] = entry
    s.head = opref

    return entry
  end

  -- Set the result on the most recent log entry
  function mgr.set_result(sid, opref, result)
    local s = sessions[sid]
    if not s then return nil, "session not found" end
    for i = #s.log, 1, -1 do
      if s.log[i].opref == opref then
        s.log[i].result = result
        return true
      end
    end
    return nil, "opref not found"
  end

  -- Query a specific log entry by OpRef
  function mgr.get_entry(sid, opref)
    local s = sessions[sid]
    if not s then return nil, "session not found" end
    for _, entry in ipairs(s.log) do
      if entry.opref == opref then
        return entry
      end
    end
    return nil, "opref not found"
  end

  -- Query the last N operations (most recent first)
  function mgr.recent(sid, n)
    local s = sessions[sid]
    if not s then return nil, "session not found" end
    n = n or 10
    local result = {}
    local start = math.max(1, #s.log - n + 1)
    for i = #s.log, start, -1 do
      result[#result + 1] = s.log[i]
    end
    return result
  end

  -- Get full log (oldest first) — for transparency/recovery
  function mgr.full_log(sid)
    local s = sessions[sid]
    if not s then return nil, "session not found" end
    return s.log
  end

  -- List all active session IDs
  function mgr.list_sessions()
    local result = {}
    for sid, _ in pairs(sessions) do
      result[#result + 1] = sid
    end
    return result
  end

  return mgr
end

return M
