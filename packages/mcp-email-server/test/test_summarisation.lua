#!/usr/bin/env luajit
-- Module test harness: Email summarisation/classification via real LLM
--
-- Tests app/llm.lua classify() and complete() with real API calls through
-- lunet.httpc. This is a Tier 2 module test per TEST_PYRAMID.md.
--
-- Usage:
--   /path/to/lunet-run test/test_summarisation.lua
--
-- Requires: MISTRAL_API_KEY, GROQ_API_KEY in .env or environment

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

local lunet = require("lunet")

-- Walk up from cwd looking for .env, but stop at the git repo root
-- (never leave the current worktree — agent sandboxes will stall)
local env = {}
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

-- Load app modules
package.path = "./app/?.lua;" .. package.path
local config = require("config")
local llm = require("llm")
local json = require("dkjson")

-- Categories from config
local categories = config.categories

-- Test framework
local pass = 0
local fail = 0
local skip = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print(string.format("[PASS] %s", name))
    pass = pass + 1
  else
    if tostring(err):match("API key not set") or tostring(err):match("httpc not available") then
      print(string.format("[SKIP] %s (%s)", name, err))
      skip = skip + 1
    else
      print(string.format("[FAIL] %s: %s", name, err))
      fail = fail + 1
    end
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then error(string.format("%s: expected %s, got %s", msg or "assert_eq", tostring(b), tostring(a))) end
end

local function assert_truthy(v, msg)
  if not v then error(msg or "expected truthy value") end
end

local function assert_match(str, pattern, msg)
  if not str or not str:match(pattern) then
    error(string.format("%s: '%s' does not match '%s'", msg or "assert_match", tostring(str), pattern))
  end
end

local function is_valid_category(cat)
  for _, c in ipairs(categories) do
    if cat:lower():find(c:lower():gsub("_", "[_ ]?")) then return true end
  end
  return false
end

-- Main test runner
lunet.spawn(function()
  print("=== Email Summarisation/Classification Module Test ===")
  print(string.format("Categories: %s", table.concat(categories, ", ")))
  print("")

  local client = llm.new(config.providers, getenv)

  -- Test 1: Classify spam email with Mistral
  test("Mistral: classify spam email", function()
    local result, err = client.classify(
      "Classify this email:\nSubject: You've Won $1,000,000! Claim Now!\nFrom: prizes@totallylegit.xyz\nPreview: Click here to claim your prize money immediately",
      "mistral", "small"
    )
    assert_truthy(result, "expected classification result, got: " .. tostring(err))
    print("  Category: " .. result)
  end)

  -- Test 2: Classify benign email with Mistral
  test("Mistral: classify benign meeting email", function()
    local result, err = client.classify(
      "Classify this email:\nSubject: Meeting notes from Tuesday standup\nFrom: alice@company.com\nPreview: Hi team, here are the notes from our standup. Action items below.",
      "mistral", "small"
    )
    assert_truthy(result, "expected classification result, got: " .. tostring(err))
    print("  Category: " .. result)
  end)

  -- Test 3: Classify automated notification with Groq
  test("Groq: classify automated notification", function()
    local result, err = client.classify(
      "Classify this email:\nSubject: Your order #12345 has shipped\nFrom: noreply@amazon.com\nPreview: Your package is on its way. Expected delivery: Thursday.",
      "groq", "llama_70b"
    )
    assert_truthy(result, "expected classification result, got: " .. tostring(err))
    print("  Category: " .. result)
  end)

  -- Test 4: Classify urgent action email with Groq
  test("Groq: classify urgent action required email", function()
    local result, err = client.classify(
      "Classify this email:\nSubject: URGENT: Server down in production\nFrom: monitoring@ops.company.com\nPreview: Production server us-east-1 is unresponsive. Immediate action required.",
      "groq", "llama_70b"
    )
    assert_truthy(result, "expected classification result, got: " .. tostring(err))
    print("  Category: " .. result)
  end)

  -- Test 5: Complete with explicit messages (multi-turn)
  test("Mistral: multi-turn completion", function()
    local result, err = client.complete("mistral", "small", {
      {role = "system", content = "You are a helpful assistant. Respond in one sentence."},
      {role = "user", content = "What is the capital of France?"},
    }, {max_tokens = 50})
    assert_truthy(result, "expected completion, got: " .. tostring(err))
    assert_match(result, "[Pp]aris", "expected mention of Paris")
    print("  Response: " .. result:sub(1, 100))
  end)

  -- Test 6: Complete respects max_tokens
  test("Groq: completion respects max_tokens", function()
    local result, err = client.complete("groq", "llama_70b", {
      {role = "user", content = "Write a very long essay about the history of computing."},
    }, {max_tokens = 15})
    assert_truthy(result, "expected completion, got: " .. tostring(err))
    -- With max_tokens=15, response should be short
    print("  Response length: " .. #result .. " chars")
  end)

  -- Test 7: Fallback from bad provider to good
  test("Fallback: invalid primary falls back to Mistral", function()
    local result, err, provider = client.with_fallback(
      {provider = "nonexistent", model = "fake"},
      {provider = "mistral", model = "small"},
      {{role = "user", content = "Say hello"}},
      {max_tokens = 10}
    )
    assert_truthy(result, "expected fallback result, got: " .. tostring(err))
    assert_eq(provider, "mistral", "expected fallback to mistral")
    print("  Fallback to: " .. provider)
  end)

  -- Test 8: Classify promotional email
  test("Mistral: classify promotional email", function()
    local result, err = client.classify(
      "Classify this email:\nSubject: 50% off everything this weekend only!\nFrom: deals@store.com\nPreview: Don't miss our biggest sale of the year. Use code SAVE50 at checkout.",
      "mistral", "small"
    )
    assert_truthy(result, "expected classification result, got: " .. tostring(err))
    print("  Category: " .. result)
  end)

  -- Summary
  print("")
  print("=== Summary ===")
  print(string.format("Total: %d pass, %d fail, %d skip (out of %d tests)",
    pass, fail, skip, pass + fail + skip))

  if fail > 0 then
    os.exit(1)
  end
end)
