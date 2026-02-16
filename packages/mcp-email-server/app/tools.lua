-- MCP Tool Implementations
-- Handles list_messages, get_message, classify_email, and action tools

local M = {}

local json = require("dkjson")

-- Helper to create tool response
local function tool_response(content)
  if type(content) == "table" then
    return {content = {{type = "text", text = json.encode(content)}}}
  else
    return {content = {{type = "text", text = tostring(content)}}}
  end
end

-- Helper to create error response
local function tool_error(code, message, details)
  return {
    error = {
      code = code,
      message = message,
      details = details,
    }
  }
end

local function append(sessions, sid, parent_ref, operation, parameters)
  local entry, err = sessions.append(sid, parent_ref, operation, parameters)
  if entry then
    return entry
  end
  if type(err) == "table" and err.operation == "divergence_detected" then
    return nil, tool_error("session_divergence", "Session divergence detected", err)
  end
  return nil, tool_error("session_error", tostring(err or "unknown error"))
end

local function inbox(jmap_client)
  local boxes, err = jmap_client.get_mailboxes()
  if not boxes then
    return nil, err
  end
  for _, box in ipairs(boxes) do
    if box.role == "inbox" then
      return box.id
    end
  end
  return nil, "no inbox mailbox"
end

-- list_messages: Query messages with explicit continuation
function M.list_messages(args, sessions, jmap_client)
  local sid = args.session_id
  local parent_ref = args.parent_ref
  
  -- Check session exists
  if not sessions.exists(sid) then
    return tool_error("session_not_found", "Session does not exist")
  end
  
  local mailbox_id = args.mailbox_id
  local limit = args.limit or 50

  if not mailbox_id then
    mailbox_id, err = inbox(jmap_client)
    if not mailbox_id then
      return tool_error("jmap_error", "Failed to resolve inbox", {error = err})
    end
  end

  local entry, aerr = append(sessions, sid, parent_ref, "list_messages", {
    mailbox_id = mailbox_id,
    limit = limit,
    time_window_start = args.time_window_start,
    time_window_end = args.time_window_end,
  })
  if not entry then
    return aerr
  end

  local email_ids
  
  email_ids, err = jmap_client.query_messages(mailbox_id, {
    limit = limit,
    sort = {{property = "receivedAt", isAscending = false}},
    after = args.time_window_start,
    before = args.time_window_end,
  })
  
  if not email_ids then
    sessions.set_result(sid, entry.opref, {ok = false, error = err})
    return tool_error("jmap_error", "Failed to query messages", {error = err})
  end
  
  -- Get email details
  local emails, err2 = jmap_client.get_emails(email_ids, {
    "id", "subject", "from", "to", "receivedAt", "size", "preview", "mailboxIds"
  })
  
  if not emails then
    sessions.set_result(sid, entry.opref, {ok = false, error = err2})
    return tool_error("jmap_error", "Failed to get email details", {error = err2})
  end

  sessions.set_result(sid, entry.opref, {
    ok = true,
    result_count = #emails,
    traversal_anchor = {
      oldest_received_at = emails[#emails] and emails[#emails].receivedAt or nil,
      newest_received_at = emails[1] and emails[1].receivedAt or nil,
    },
  })
  
  return tool_response({
    opref = entry.opref,
    messages = emails,
    count = #emails,
    traversal_anchor = {
      oldest_received_at = emails[#emails] and emails[#emails].receivedAt or nil,
      newest_received_at = emails[1] and emails[1].receivedAt or nil,
    },
  })
end

-- get_message: Retrieve full message details
function M.get_message(args, sessions, jmap_client)
  local sid = args.session_id
  local parent_ref = args.parent_ref
  local message_id = args.message_id
  
  if not sessions.exists(sid) then
    return tool_error("session_not_found", "Session does not exist")
  end
  
  local entry, aerr = append(sessions, sid, parent_ref, "get_message", {
    message_id = message_id,
  })
  if not entry then
    return aerr
  end

  local emails, err = jmap_client.get_emails({message_id}, {
    "id", "subject", "from", "to", "cc", "bcc", "receivedAt", "sentAt",
    "size", "preview", "bodyValues", "textBody", "htmlBody", "attachments",
  })
  
  if not emails or #emails == 0 then
    sessions.set_result(sid, entry.opref, {ok = false, error = err})
    return tool_error("message_not_found", "Message not found", {error = err})
  end

  sessions.set_result(sid, entry.opref, {ok = true})
  
  return tool_response({
    opref = entry.opref,
    message = emails[1],
  })
end

-- classify_email: Classify using LLM
function M.classify_email(args, sessions, llm_client, config)
  local sid = args.session_id
  local parent_ref = args.parent_ref
  
  if not sessions.exists(sid) then
    return tool_error("session_not_found", "Session does not exist")
  end
  
  local entry, aerr = append(sessions, sid, parent_ref, "classify_email", {
    message_id = args.message_id,
  })
  if not entry then
    return aerr
  end

  -- Build classification prompt
  local categories = table.concat(config.categories, ", ")
  local prompt = string.format([[Classify this email into one of these categories: %s

Subject: %s
From: %s
Preview: %s

Return only the category name, nothing else.]], 
    categories,
    args.subject or "(no subject)",
    args.from or "(unknown)",
    args.preview or "(no preview)"
  )
  
  -- Call LLM (using Mistral small for classification)
  local category, err = llm_client.classify(prompt, "mistral", "small")
  
  if not category then
    sessions.set_result(sid, entry.opref, {ok = false, error = err})
    return tool_error("llm_error", "Classification failed", {error = err})
  end

  sessions.set_result(sid, entry.opref, {ok = true, category = category})
  
  return tool_response({
    opref = entry.opref,
    message_id = args.message_id,
    category = category,
    categories_available = config.categories,
  })
end

-- archive_message: Safe action, no approval needed
function M.archive_message(args, sessions, jmap_client)
  local sid = args.session_id
  local parent_ref = args.parent_ref
  local message_id = args.message_id
  
  if not sessions.exists(sid) then
    return tool_error("session_not_found", "Session does not exist")
  end
  
  local entry, aerr = append(sessions, sid, parent_ref, "archive_message", {
    message_id = message_id,
  })
  if not entry then
    return aerr
  end
  
  -- TODO: Perform JMAP Email/set to move to Archive mailbox
  -- For now, stub
  
  sessions.set_result(sid, entry.opref, {ok = false, status = "not_implemented"})
  
  return tool_response({
    opref = entry.opref,
    message_id = message_id,
    action = "archive",
    status = "not_implemented",
  })
end

-- trash_message: Reversible, no approval needed
function M.trash_message(args, sessions, jmap_client)
  local sid = args.session_id
  local parent_ref = args.parent_ref
  local message_id = args.message_id
  
  if not sessions.exists(sid) then
    return tool_error("session_not_found", "Session does not exist")
  end
  
  local entry, aerr = append(sessions, sid, parent_ref, "trash_message", {
    message_id = message_id,
  })
  if not entry then
    return aerr
  end
  
  -- TODO: Perform JMAP Email/set to move to Trash mailbox
  -- For now, stub
  
  sessions.set_result(sid, entry.opref, {ok = false, status = "not_implemented"})
  
  return tool_response({
    opref = entry.opref,
    message_id = message_id,
    action = "trash",
    status = "not_implemented",
  })
end

-- session_status: Query session state
function M.session_status(args, sessions)
  local sid = args.session_id
  
  if not sessions.exists(sid) then
    return tool_error("session_not_found", "Session does not exist")
  end
  
  local head = sessions.head(sid)
  local recent = sessions.recent(sid, args.recent_count or 10)
  
  return tool_response({
    session_id = sid,
    head_opref = head,
    log_length = sessions.length(sid),
    recent_operations = recent,
  })
end

return M
