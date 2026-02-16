-- LLM Client Module
-- Wraps lunet.httpc calls to LLM providers defined in config.lua
--
-- Usage:
--   local llm = require("llm")
--   local client = llm.new(config.providers, getenv)
--   local text, err = client.complete("mistral", "small", messages, {max_tokens=100})
--   local category, err = client.classify(prompt, "mistral", "small")

local json = require("dkjson")

local M = {}

function M.new(providers, getenv_fn)
  local client = {}
  local httpc_ok, httpc = pcall(require, "lunet.httpc")

  -- Fallback getenv
  local getenv = getenv_fn or os.getenv

  -- Complete: send messages to a provider/model, return assistant content
  function client.complete(provider_key, model_key, messages, opts)
    local provider = providers[provider_key]
    if not provider then
      return nil, "unknown provider: " .. tostring(provider_key)
    end

    local model = provider.models[model_key]
    if not model then
      return nil, string.format("unknown model '%s' for provider '%s'", tostring(model_key), provider_key)
    end

    local api_key = getenv(provider.api_key_env)
    if not api_key or api_key == "" then
      return nil, string.format("API key not set: %s", provider.api_key_env)
    end

    opts = opts or {}
    local body = json.encode({
      model = model,
      messages = messages,
      max_tokens = opts.max_tokens or 200,
      temperature = opts.temperature or 0.3,
    })

    if not httpc_ok then
      return nil, "lunet.httpc not available"
    end

    local resp, err = httpc.request({
      url = provider.url,
      method = "POST",
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. api_key,
      },
      body = body,
      timeout_ms = opts.timeout_ms or 15000,
    })

    if not resp then
      return nil, "HTTP request failed: " .. (err or "unknown")
    end

    if resp.status ~= 200 then
      return nil, string.format("HTTP %d: %s", resp.status, resp.body:sub(1, 200))
    end

    local ok, result = pcall(json.decode, resp.body)
    if not ok then
      return nil, "JSON parse error: " .. tostring(result)
    end

    if result.choices and result.choices[1] then
      local msg = result.choices[1].message or result.choices[1].delta
      if msg and msg.content then
        return msg.content
      end
    end

    return nil, "no content in response"
  end

  -- Classify: convenience wrapper for single-prompt classification
  function client.classify(prompt, provider_key, model_key)
    provider_key = provider_key or "mistral"
    model_key = model_key or "small"

    local messages = {
      {role = "system", content = "You are an email classifier. Return only the category name."},
      {role = "user", content = prompt},
    }

    return client.complete(provider_key, model_key, messages, {
      max_tokens = 50,
      temperature = 0.1,
    })
  end

  -- Multi-model: try primary, fall back to secondary
  function client.with_fallback(primary, fallback, messages, opts)
    local result, err = client.complete(primary.provider, primary.model, messages, opts)
    if result then
      return result, nil, primary.provider
    end

    if fallback then
      local result2, err2 = client.complete(fallback.provider, fallback.model, messages, opts)
      if result2 then
        return result2, nil, fallback.provider
      end
      return nil, string.format("primary: %s; fallback: %s", err, err2)
    end

    return nil, err
  end

  return client
end

return M
