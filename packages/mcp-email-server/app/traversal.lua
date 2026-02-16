-- Traversal Module
-- Implements RFC §4.2: Explicit Continuation and Traversal Stability
--
-- Key principles:
--   - No hidden state, no opaque cursors
--   - Every list request uses explicit time window or message ID anchors
--   - Responses include explicit bounds for next-page construction
--   - Identical parameters yield identical results (stability)

local M = {}

-- Validate traversal parameters
-- Returns: validated params table, or nil + error string
function M.validate(params)
  if not params then
    return nil, "params required"
  end

  local limit = params.limit or 50
  if type(limit) ~= "number" or limit < 1 or limit > 1000 then
    return nil, "limit must be a number between 1 and 1000"
  end

  local direction = params.direction or "descending"
  if direction ~= "ascending" and direction ~= "descending" then
    return nil, "direction must be 'ascending' or 'descending'"
  end

  -- Must have at least one explicit anchor
  local has_time_window = params.time_window_start or params.time_window_end
  local has_message_anchor = params.anchor_message_id
  -- First request with no anchors is allowed (gets latest)
  -- But "continue" without anchors is rejected
  if params.is_continuation and not has_time_window and not has_message_anchor then
    return nil, "continuation requires explicit anchor (time_window or anchor_message_id)"
  end

  return {
    limit = limit,
    direction = direction,
    time_window_start = params.time_window_start,
    time_window_end = params.time_window_end,
    anchor_message_id = params.anchor_message_id,
    mailbox_id = params.mailbox_id,
  }
end

-- Build JMAP query options from traversal params
function M.query_opts(params)
  local opts = {
    limit = params.limit,
    sort = {{
      property = "receivedAt",
      isAscending = params.direction == "ascending",
    }},
  }

  if params.time_window_start then
    opts.after = params.time_window_start
  end
  if params.time_window_end then
    opts.before = params.time_window_end
  end

  return opts
end

-- Build response bounds from a list of emails
-- These are explicit anchors the caller can use for the next page
function M.bounds(emails, params)
  if not emails or #emails == 0 then
    return {
      count = 0,
      has_more = false,
    }
  end

  local oldest = emails[#emails]
  local newest = emails[1]

  -- For descending (newest first), next page starts before the oldest
  -- For ascending (oldest first), next page starts after the newest
  local next_anchor
  if params.direction == "ascending" then
    next_anchor = {
      time_window_start = newest.receivedAt,
      direction = "ascending",
    }
  else
    next_anchor = {
      time_window_end = oldest.receivedAt,
      direction = "descending",
    }
  end

  return {
    count = #emails,
    has_more = #emails >= params.limit,
    oldest_received_at = oldest.receivedAt,
    newest_received_at = newest.receivedAt,
    oldest_id = oldest.id,
    newest_id = newest.id,
    next_page = next_anchor,
  }
end

return M
