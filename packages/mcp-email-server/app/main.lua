#!/usr/bin/env luajit
-- MCP Email Server - Main Entry Point
-- Implements transparent session-based email triage and action workflow
--
-- Usage:
--   /path/to/lunet-run app/main.lua
--   # or with custom port:
--   PORT=8080 /path/to/lunet-run app/main.lua

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

-- Load dependencies
local lunet = require("lunet")
local socket = require("lunet.socket")

-- Load application modules
package.path = "./app/?.lua;" .. package.path
local config = require("config")
local session_mgr = require("session")
local jmap = require("jmap")
local json = require("dkjson")
local approval_mod = require("approval")
local ledger_mod = require("ledger")
local toolmod = require("tools")

-- Initialize modules
local sessions = session_mgr.new()
local approvals = approval_mod.new(config.approval)
local action_ledger = ledger_mod.new()

print("=== MCP Email Server ===")
print("Protocol: MCP 2024-11-05")
print("Version: 0.1.0")
print(string.format("Port: http://%s:%d", config.server.host, config.server.port))
print("")
print("Tools:")
print("  - list_messages: Query messages with explicit time window/anchors")
print("  - get_message: Retrieve full message details")
print("  - classify_email: Multi-model email classification")
print("  - archive_message: Move to archive (safe, no approval)")
print("  - trash_message: Move to trash (reversible, no approval)")
print("  - session_status: Query current session state")
print("")

-- MCP tool definitions
local tooldefs = {
  {
    name = "list_messages",
    description = "List messages from mailbox with explicit continuation anchors. Requires ParentRef for traversal integrity.",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string", description = "Session identifier"},
        parent_ref = {type = "string", description = "Parent OpRef for session continuity (optional for first request)"},
        mailbox_id = {type = "string", description = "JMAP mailbox ID (optional, defaults to INBOX)"},
        limit = {type = "number", description = "Max messages to return (default 50)"},
        time_window_start = {type = "string", description = "ISO8601 start time for explicit time window"},
        time_window_end = {type = "string", description = "ISO8601 end time for explicit time window"},
      },
      required = {"session_id"},
    },
  },
  {
    name = "get_message",
    description = "Retrieve full message details by ID",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        parent_ref = {type = "string", description = "Parent OpRef for session continuity (null for first operation)"},
        message_id = {type = "string"},
      },
      required = {"session_id", "parent_ref", "message_id"},
    },
  },
  {
    name = "classify_email",
    description = "Classify email using lightweight model (pluggable categories from config)",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        parent_ref = {type = "string", description = "Parent OpRef for session continuity (null for first operation)"},
        message_id = {type = "string"},
        subject = {type = "string"},
        from = {type = "string"},
        preview = {type = "string"},
      },
      required = {"session_id", "parent_ref", "message_id", "subject", "from"},
    },
  },
  {
    name = "archive_message",
    description = "Archive message (safe action, no approval required)",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        parent_ref = {type = "string"},
        message_id = {type = "string"},
      },
      required = {"session_id", "parent_ref", "message_id"},
    },
  },
  {
    name = "trash_message",
    description = "Move message to trash (reversible, no approval required)",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        parent_ref = {type = "string"},
        message_id = {type = "string"},
      },
      required = {"session_id", "parent_ref", "message_id"},
    },
  },
  {
    name = "send_message",
    description = "Send an email (requires explicit approval)",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        parent_ref = {type = "string"},
        message_id = {type = "string", description = "Draft message ID to send"},
        to = {type = "string"},
        subject = {type = "string"},
        body = {type = "string"},
        approval = {type = "object", description = "Approval grant: {scope: 'once'|'session'|'always'}"},
        delay_spec = {type = "object", description = "Delay execution: {delay_seconds: number}"},
      },
      required = {"session_id", "parent_ref", "approval"},
    },
  },
  {
    name = "delete_message",
    description = "Delete a message (trash is safe; hard_delete requires approval)",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        parent_ref = {type = "string"},
        message_id = {type = "string"},
        hard_delete = {type = "boolean", description = "If true, permanently delete (requires approval)"},
        approval = {type = "object", description = "Approval grant for hard delete"},
        delay_spec = {type = "object", description = "Delay execution"},
      },
      required = {"session_id", "parent_ref", "message_id"},
    },
  },
  {
    name = "query_ledger",
    description = "Query the action ledger for scheduled/executed/failed actions",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        state = {type = "string", description = "Filter by state: pending, executed, cancelled, failed"},
        action = {type = "string", description = "Filter by action type"},
      },
    },
  },
  {
    name = "session_status",
    description = "Query session state: head OpRef, recent operations, traversal anchors",
    inputSchema = {
      type = "object",
      properties = {
        session_id = {type = "string"},
        recent_count = {type = "number", description = "Number of recent ops to return (default 10)"},
      },
      required = {"session_id"},
    },
  },
}

-- Tool dispatch table
local dispatchers = {
  list_messages = function(args) return toolmod.list_messages(args, sessions, nil) end,
  get_message = function(args) return toolmod.get_message(args, sessions, nil) end,
  classify_email = function(args) return toolmod.classify_email(args, sessions, nil, config) end,
  archive_message = function(args) return toolmod.archive_message(args, sessions, nil, approvals) end,
  trash_message = function(args) return toolmod.trash_message(args, sessions, nil, approvals) end,
  send_message = function(args) return toolmod.send_message(args, sessions, nil, approvals, action_ledger) end,
  delete_message = function(args) return toolmod.delete_message(args, sessions, nil, approvals, action_ledger) end,
  session_status = function(args) return toolmod.session_status(args, sessions) end,
  query_ledger = function(args) return toolmod.query_ledger(args, action_ledger) end,
}

local function handle_tool_call(tool_name, args)
  local handler = dispatchers[tool_name]
  if not handler then
    return {error = "unknown_tool", message = string.format("Tool '%s' not found", tool_name)}
  end
  return handler(args)
end

-- MCP JSON-RPC handler
local function handle_mcp_request(request)
  local method = request.method
  local id = request.id
  
  if method == "initialize" then
    return {
      jsonrpc = "2.0",
      id = id,
      result = {
        protocolVersion = "2024-11-05",
        serverInfo = {
          name = "mcp-email-server",
          version = "0.1.0",
        },
        capabilities = {
          tools = {},
        },
      },
    }
  elseif method == "notifications/initialized" then
    -- No response for notifications
    return nil
  elseif method == "tools/list" then
    return {
      jsonrpc = "2.0",
      id = id,
      result = {tools = tooldefs},
    }
  elseif method == "tools/call" then
    local tool_name = request.params.name
    local args = request.params.arguments or {}
    local result = handle_tool_call(tool_name, args)
    return {
      jsonrpc = "2.0",
      id = id,
      result = {content = {{type = "text", text = json.encode(result)}}},
    }
  elseif method == "ping" then
    return {jsonrpc = "2.0", id = id, result = {}}
  else
    return {
      jsonrpc = "2.0",
      id = id,
      error = {code = -32601, message = "Method not found"},
    }
  end
end

print("Server ready. Press Ctrl+C to stop.")
print("")

-- Note: Full SSE/HTTP server implementation would go here
-- For now, this is a module that can be extended
