-- LLM Client Unit Tests
-- Tests app/llm.lua config validation and message building
-- NOTE: Does not test actual HTTP calls (requires lunet.httpc runtime)

package.path = "./app/?.lua;" .. package.path
local llm = require("llm")

local test_providers = {
  mistral = {
    name = "Mistral",
    url = "https://api.mistral.ai/v1/chat/completions",
    api_key_env = "MISTRAL_API_KEY",
    models = {
      small = "mistral-small-latest",
      large = "mistral-large-latest",
    },
    default_model = "small",
  },
  groq = {
    name = "Groq",
    url = "https://api.groq.com/openai/v1/chat/completions",
    api_key_env = "GROQ_API_KEY",
    models = {
      llama_70b = "llama-3.3-70b-versatile",
    },
    default_model = "llama_70b",
  },
}

-- Fake getenv that returns keys for known providers
local function fake_getenv(key)
  if key == "MISTRAL_API_KEY" then return "sk-test-mistral" end
  if key == "GROQ_API_KEY" then return "sk-test-groq" end
  return nil
end

describe("LLM Client", function()

  it("creates a client from provider config", function()
    local client = llm.new(test_providers, fake_getenv)
    assert.is_table(client)
    assert.is_function(client.complete)
    assert.is_function(client.classify)
    assert.is_function(client.with_fallback)
  end)

  it("rejects unknown provider", function()
    local client = llm.new(test_providers, fake_getenv)
    local result, err = client.complete("openai", "gpt4", {})
    assert.is_nil(result)
    assert.matches("unknown provider", err)
  end)

  it("rejects unknown model for known provider", function()
    local client = llm.new(test_providers, fake_getenv)
    local result, err = client.complete("mistral", "nonexistent", {})
    assert.is_nil(result)
    assert.matches("unknown model", err)
  end)

  it("rejects when API key is not set", function()
    local client = llm.new(test_providers, function() return nil end)
    local result, err = client.complete("mistral", "small", {{role = "user", content = "hi"}})
    assert.is_nil(result)
    assert.matches("API key not set", err)
  end)

  it("rejects empty API key", function()
    local client = llm.new(test_providers, function() return "" end)
    local result, err = client.complete("mistral", "small", {{role = "user", content = "hi"}})
    assert.is_nil(result)
    assert.matches("API key not set", err)
  end)

end)

describe("LLM classify", function()

  it("defaults to mistral/small", function()
    -- classify will fail at HTTP layer but we test it gets past config validation
    local client = llm.new(test_providers, fake_getenv)
    -- Will fail with "lunet.httpc not available" in test env
    local result, err = client.classify("Classify this email", nil, nil)
    assert.is_nil(result)
    assert.matches("httpc not available", err)
  end)

  it("uses specified provider and model", function()
    local client = llm.new(test_providers, fake_getenv)
    local result, err = client.classify("test prompt", "groq", "llama_70b")
    assert.is_nil(result)
    assert.matches("httpc not available", err)
  end)

end)

describe("LLM with_fallback", function()

  it("returns error mentioning both providers on double failure", function()
    local client = llm.new(test_providers, fake_getenv)
    local result, err = client.with_fallback(
      {provider = "mistral", model = "small"},
      {provider = "groq", model = "llama_70b"},
      {{role = "user", content = "hi"}}
    )
    assert.is_nil(result)
    assert.matches("primary:", err)
    assert.matches("fallback:", err)
  end)

  it("returns primary error when no fallback given", function()
    local client = llm.new(test_providers, fake_getenv)
    local result, err = client.with_fallback(
      {provider = "mistral", model = "small"},
      nil,
      {{role = "user", content = "hi"}}
    )
    assert.is_nil(result)
    assert.matches("httpc not available", err)
  end)

end)
