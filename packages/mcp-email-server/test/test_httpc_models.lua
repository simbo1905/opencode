#!/usr/bin/env luajit
-- Test rig for lunet.httpc with Mistral, Groq, Together
--
-- Runs a simple server on a Unix domain socket that tests all three providers.
-- Makes fixed completion requests + continuation requests to each provider.
--
-- Usage:
--   LUNET_BIN=/path/to/lunet-run ./test/test_httpc_models.lua
--   # or via lunet directly:
--   /path/to/lunet-run test/test_httpc_models.lua

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

local lunet = require("lunet")
local socket = require("lunet.socket")
local httpc_ok, httpc = pcall(require, "lunet.httpc")

if not httpc_ok then
  print("ERROR: lunet.httpc not available")
  print("Build it: cd vendor/lunet && xmake build lunet-httpc")
  os.exit(1)
end

-- Load .env file (Lua doesn't have os.setenv, so use globals)
local env = {}
-- Walk up from cwd looking for .env, but stop at the git repo root
-- (never leave the current worktree — agent sandboxes will stall)
local function load_env()
  local dir = "."
  for _ = 1, 10 do
    local env_path = dir .. "/.env"
    local file = io.open(env_path, "r")
    if file then
      for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key and value then
          value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
          env[key] = os.getenv(key) or value
        end
      end
      file:close()
      return
    end
    -- Stop if we hit a .git directory (repo root)
    local git = io.open(dir .. "/.git", "r") or io.open(dir .. "/.git/HEAD", "r")
    if git then
      git:close()
      return
    end
    dir = dir .. "/.."
  end
end

local function getenv(key)
  return os.getenv(key) or env[key]
end

load_env()

-- Load config (single source of truth for providers)
package.path = "./app/?.lua;" .. package.path
local config = require("config")
local json = require("dkjson")

local json_encode = json.encode
local json_decode = json.decode

-- Test a provider with a completion request
local function test_completion(name, url, api_key, model, prompt)
  print(string.format("\n[%s] Testing completion", name))
  
  if not api_key or api_key == "" then
    print(string.format("[%s] SKIP: API key not set", name))
    return {ok = true, skipped = true}
  end

  local request_body = json_encode({
    model = model,
    messages = {{role = "user", content = prompt}},
    max_tokens = 50,
    temperature = 0.7,
  })

  local resp, err = httpc.request({
    url = url,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    },
    body = request_body,
    timeout_ms = 15000,
  })

  if not resp then
    print(string.format("[%s] ERROR: %s", name, err or "unknown"))
    return {ok = false, reason = err or "unknown"}
  end

  print(string.format("[%s] Status: %d", name, resp.status))
  
  if resp.status ~= 200 then
    print(string.format("[%s] Body: %s", name, resp.body:sub(1, 200)))
    return {ok = false, reason = "http_" .. resp.status}
  end

  local ok_parse, result = pcall(json_decode, resp.body)
  if not ok_parse then
    print(string.format("[%s] ERROR: Failed to parse JSON", name))
    return {ok = false, reason = "json_parse_error"}
  end

  local content = nil
  if result.choices and result.choices[1] then
    local message = result.choices[1].message or result.choices[1].delta
    content = message and message.content
  end

  if content then
    print(string.format("[%s] Response: %s", name, content:sub(1, 80)))
    print(string.format("[%s] OK", name))
    return {ok = true, content = content}
  else
    print(string.format("[%s] ERROR: No content in response", name))
    return {ok = false, reason = "no_content"}
  end
end

-- Test a provider with a multi-turn conversation
local function test_continuation(name, url, api_key, model)
  print(string.format("\n[%s] Testing continuation", name))
  
  if not api_key or api_key == "" then
    print(string.format("[%s] SKIP: API key not set", name))
    return {ok = true, skipped = true}
  end

  local request_body = json_encode({
    model = model,
    messages = {
      {role = "user", content = "What is 2+2?"},
      {role = "assistant", content = "4"},
      {role = "user", content = "What about 3+3?"},
    },
    max_tokens = 30,
    temperature = 0.7,
  })

  local resp, err = httpc.request({
    url = url,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. api_key,
    },
    body = request_body,
    timeout_ms = 15000,
  })

  if not resp then
    print(string.format("[%s] ERROR: %s", name, err or "unknown"))
    return {ok = false, reason = err or "unknown"}
  end

  if resp.status ~= 200 then
    print(string.format("[%s] Continuation failed: HTTP %d", name, resp.status))
    return {ok = false, reason = "http_" .. resp.status}
  end

  local ok_parse, result = pcall(json_decode, resp.body)
  if not ok_parse then
    return {ok = false, reason = "json_parse_error"}
  end

  local content = nil
  if result.choices and result.choices[1] then
    local message = result.choices[1].message or result.choices[1].delta
    content = message and message.content
  end

  if content then
    print(string.format("[%s] Continuation: %s", name, content:sub(1, 80)))
    print(string.format("[%s] OK", name))
    return {ok = true, content = content}
  else
    return {ok = false, reason = "no_content"}
  end
end

-- Main test runner
lunet.spawn(function()
  print("=== lunet.httpc Model Provider Test Rig ===")
  print("Testing Mistral, Groq, Together with completion + continuation\n")

  -- Build provider list from config (single source of truth)
  local providers = {}
  for key, cfg in pairs(config.providers) do
    local default_model_key = cfg.default_model
    local model = cfg.models[default_model_key]
    providers[#providers + 1] = {
      name = cfg.name,
      url = cfg.url,
      api_key = getenv(cfg.api_key_env),
      model = model,
    }
  end

  local results = {}
  local prompt = "Tell me a short joke in one sentence."

  for _, provider in ipairs(providers) do
    local comp = test_completion(provider.name, provider.url, provider.api_key, provider.model, prompt)
    local cont = test_continuation(provider.name, provider.url, provider.api_key, provider.model)
    results[provider.name] = {
      completion = comp.ok,
      continuation = cont.ok,
    }
  end

  -- Summary
  print("\n=== Summary ===")
  local total_pass = 0
  local total_fail = 0
  for _, provider in ipairs(providers) do
    local comp_status = results[provider.name].completion and "PASS" or "FAIL"
    local cont_status = results[provider.name].continuation and "PASS" or "FAIL"
    print(string.format("%s: completion=%s, continuation=%s", provider.name, comp_status, cont_status))
    if results[provider.name].completion then total_pass = total_pass + 1 else total_fail = total_fail + 1 end
    if results[provider.name].continuation then total_pass = total_pass + 1 else total_fail = total_fail + 1 end
  end
  print(string.format("\nTotal: %d pass, %d fail (out of %d tests)", total_pass, total_fail, total_pass + total_fail))

  if total_fail > 0 then
    os.exit(1)
  end
end)
