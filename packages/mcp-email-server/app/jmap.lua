-- JMAP client for email access via lunet.httpc
-- Implements RFC 8620 (JMAP Core) and RFC 8621 (JMAP for Mail)
--
-- Usage:
--   local jmap = require("jmap")
--   local client = jmap.new(config.jmap)
--   local session_info = client.session()
--   local mailboxes = client.get_mailboxes()
--   local messages = client.query_messages(mailbox_id, {limit=50})

local M = {}

local json = require("dkjson")

-- Load dependencies
local httpc_ok, httpc = pcall(require, "lunet.httpc")
if not httpc_ok then
  error("lunet.httpc not available - required for JMAP")
end

-- Create a new JMAP client
function M.new(opts)
  local client = {}
  
  -- Configuration
  client.jmap_url = opts.url
  client.username = os.getenv(opts.username_env) or ""
  client.password = os.getenv(opts.password_env) or ""
  client.timeout_ms = opts.timeout_ms or 30000
  client.max_body_bytes = opts.max_body_bytes or (10 * 1024 * 1024)
  
  -- Session state (populated on first request)
  client.session_url = nil
  client.api_url = nil
  client.account_id = nil
  client.capabilities = nil
  
  if client.username == "" or client.password == "" then
    error("JMAP credentials not set - check JMAP_USERNAME and JMAP_PASSWORD env vars")
  end
  
  -- Base64 encode for Basic auth
  local function base64_encode(str)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}
    local padding = (3 - #str % 3) % 3
    str = str .. string.rep('\0', padding)
    for i = 1, #str, 3 do
      local n = (str:byte(i) * 65536) + (str:byte(i+1) * 256) + str:byte(i+2)
      result[#result+1] = b:sub(n / 262144 + 1, n / 262144 + 1)
      result[#result+1] = b:sub((n / 4096) % 64 + 1, (n / 4096) % 64 + 1)
      result[#result+1] = b:sub((n / 64) % 64 + 1, (n / 64) % 64 + 1)
      result[#result+1] = b:sub(n % 64 + 1, n % 64 + 1)
    end
    for i = 1, padding do result[#result - i + 1] = '=' end
    return table.concat(result)
  end
  
  local auth_header = "Basic " .. base64_encode(client.username .. ":" .. client.password)
  
  -- Fetch JMAP session (discovers API endpoint and account info)
  function client.session()
    local resp, err = httpc.request({
      url = client.jmap_url,
      method = "GET",
      headers = {
        ["Authorization"] = auth_header,
      },
      timeout_ms = client.timeout_ms,
      max_body_bytes = client.max_body_bytes,
    })
    
    if not resp then
      return nil, "Failed to fetch JMAP session: " .. (err or "unknown error")
    end
    
    if resp.status ~= 200 then
      return nil, string.format("JMAP session failed: HTTP %d - %s", resp.status, resp.body:sub(1, 200))
    end
    
    local ok, session_data = pcall(json.decode, resp.body)
    if not ok then
      return nil, "Failed to parse JMAP session JSON: " .. tostring(session_data)
    end
    
    -- Extract session info
    client.session_url = client.jmap_url
    client.api_url = session_data.apiUrl
    client.capabilities = session_data.capabilities
    
    -- Find primary account
    local accounts = session_data.accounts or {}
    for account_id, account_info in pairs(accounts) do
      if account_info.isPrimary or not client.account_id then
        client.account_id = account_id
        break
      end
    end
    
    if not client.account_id then
      return nil, "No account found in JMAP session"
    end
    
    return {
      api_url = client.api_url,
      account_id = client.account_id,
      capabilities = client.capabilities,
    }
  end
  
  -- Execute a JMAP method call
  function client.call(method_calls)
    -- Ensure session is initialized
    if not client.api_url then
      local session_info, err = client.session()
      if not session_info then
        return nil, err
      end
    end
    
    local request_body = json.encode({
      using = {
        "urn:ietf:params:jmap:core",
        "urn:ietf:params:jmap:mail",
      },
      methodCalls = method_calls,
    })
    
    local resp, err = httpc.request({
      url = client.api_url,
      method = "POST",
      headers = {
        ["Authorization"] = auth_header,
        ["Content-Type"] = "application/json",
      },
      body = request_body,
      timeout_ms = client.timeout_ms,
      max_body_bytes = client.max_body_bytes,
    })
    
    if not resp then
      return nil, "JMAP API call failed: " .. (err or "unknown error")
    end
    
    if resp.status ~= 200 then
      return nil, string.format("JMAP API call failed: HTTP %d - %s", resp.status, resp.body:sub(1, 200))
    end
    
    local ok, result = pcall(json.decode, resp.body)
    if not ok then
      return nil, "Failed to parse JMAP response JSON: " .. tostring(result)
    end
    
    return result.methodResponses
  end
  
  -- Get all mailboxes
  function client.get_mailboxes()
    local responses, err = client.call({
      {"Mailbox/get", {accountId = client.account_id}, "0"},
    })
    
    if not responses then
      return nil, err
    end
    
    local mailbox_response = responses[1]
    if mailbox_response[1] ~= "Mailbox/get" then
      return nil, "Unexpected response type: " .. mailbox_response[1]
    end
    
    return mailbox_response[2].list
  end
  
  -- Query messages in a mailbox
  function client.query_messages(mailbox_id, opts)
    opts = opts or {}
    local limit = opts.limit or 50
    local sort = opts.sort or {{property = "receivedAt", isAscending = false}}
    
    local filter = {}
    if mailbox_id then
      filter.inMailbox = mailbox_id
    end
    if opts.after then
      filter.after = opts.after
    end
    if opts.before then
      filter.before = opts.before
    end
    
    local responses, err = client.call({
      {"Email/query", {
        accountId = client.account_id,
        filter = filter,
        sort = sort,
        limit = limit,
      }, "0"},
    })
    
    if not responses then
      return nil, err
    end
    
    local query_response = responses[1]
    if query_response[1] ~= "Email/query" then
      return nil, "Unexpected response type: " .. query_response[1]
    end
    
    return query_response[2].ids
  end
  
  -- Get email details by IDs
  function client.get_emails(email_ids, properties)
    properties = properties or {"id", "subject", "from", "to", "receivedAt", "size", "preview"}
    
    local responses, err = client.call({
      {"Email/get", {
        accountId = client.account_id,
        ids = email_ids,
        properties = properties,
      }, "0"},
    })
    
    if not responses then
      return nil, err
    end
    
    local email_response = responses[1]
    if email_response[1] ~= "Email/get" then
      return nil, "Unexpected response type: " .. email_response[1]
    end
    
    return email_response[2].list
  end
  
  return client
end

return M
