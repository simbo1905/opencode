-- Action Ledger Module
-- Implements RFC Addendum §A1-A6: Scheduled/Delayed Actions
--
-- Key principles:
--   - Every action is recorded as a ledger entry
--   - Delayed actions separate scheduling from execution
--   - Execution-time revalidation of preconditions
--   - Idempotency: duplicate execution attempts are prevented and logged
--   - Approval requirements are not bypassed by delays

local M = {}

-- Ledger entry states
-- Note: EXECUTED means "execution was attempted and preconditions passed".
-- The actual outcome (success/failure of the external side effect) is
-- recorded in entry.result via set_result(). Check entry.result.ok for
-- whether the side effect succeeded.
M.PENDING = "pending"
M.EXECUTED = "executed"
M.CANCELLED = "cancelled"
M.FAILED = "failed"

function M.new()
  local ledger = {}
  local entries = {}
  local counter = 0

  -- Create a new ledger entry
  function ledger.schedule(sid, opref, action, params, delay_spec)
    counter = counter + 1
    local id = "ledger_" .. tostring(counter)

    local entry = {
      id = id,
      session_id = sid,
      opref = opref,
      action = action,
      params = params or {},
      state = M.PENDING,
      scheduled_at = os.time(),
      executed_at = nil,
      delay_spec = delay_spec,
      result = nil,
      preconditions = params and params.preconditions or nil,
      execution_attempts = 0,
    }

    entries[id] = entry
    return entry
  end

  -- Execute a ledger entry (with revalidation)
  -- validate_fn: function(entry) -> true or nil, conflict_info
  function ledger.execute(id, validate_fn)
    local entry = entries[id]
    if not entry then
      return nil, "entry not found"
    end

    if entry.state ~= M.PENDING then
      return nil, {
        error = "duplicate_execution",
        entry_id = id,
        current_state = entry.state,
        message = "Entry is not pending; cannot execute",
      }
    end

    entry.execution_attempts = entry.execution_attempts + 1

    -- Revalidate preconditions at execution time
    if validate_fn then
      local ok, conflict = validate_fn(entry)
      if not ok then
        entry.state = M.FAILED
        entry.result = {ok = false, conflict = conflict}
        return nil, conflict
      end
    end

    entry.state = M.EXECUTED
    entry.executed_at = os.time()
    return entry
  end

  -- Set result on an executed entry
  function ledger.set_result(id, result)
    local entry = entries[id]
    if not entry then
      return nil, "entry not found"
    end
    entry.result = result
    return true
  end

  -- Cancel a pending entry
  function ledger.cancel(id, reason)
    local entry = entries[id]
    if not entry then
      return nil, "entry not found"
    end
    if entry.state ~= M.PENDING then
      return nil, "can only cancel pending entries"
    end
    entry.state = M.CANCELLED
    entry.result = {ok = false, reason = reason or "cancelled"}
    return entry
  end

  -- Query entries by state
  function ledger.query(filter)
    filter = filter or {}
    local result = {}
    for _, entry in pairs(entries) do
      local match = true
      if filter.state and entry.state ~= filter.state then
        match = false
      end
      if filter.session_id and entry.session_id ~= filter.session_id then
        match = false
      end
      if filter.action and entry.action ~= filter.action then
        match = false
      end
      if match then
        result[#result + 1] = entry
      end
    end
    -- Sort by scheduled_at descending
    table.sort(result, function(a, b)
      return a.scheduled_at > b.scheduled_at
    end)
    return result
  end

  -- Get a specific entry
  function ledger.get(id)
    return entries[id]
  end

  -- Count entries by state
  function ledger.counts()
    local counts = {pending = 0, executed = 0, cancelled = 0, failed = 0}
    for _, entry in pairs(entries) do
      counts[entry.state] = (counts[entry.state] or 0) + 1
    end
    return counts
  end

  return ledger
end

return M
