-- Configuration for MCP Email Server
-- Single source of truth for providers, endpoints, and operational parameters
--
-- Environment variables (loaded from .env) can override URLs and provide API keys.
-- Pattern: getenv(provider.api_key_env) for runtime key lookup.

local function getenv(key, default)
  return os.getenv(key) or default or ""
end

return {
  -- LLM Provider Configuration
  providers = {
    mistral = {
      name = "Mistral",
      url = getenv("MISTRAL_API_URL", "https://api.mistral.ai/v1") .. "/chat/completions",
      api_key_env = "MISTRAL_API_KEY",
      models = {
        small = "mistral-small-latest",
        large = "mistral-large-latest",
      },
      default_model = "small",
    },
    groq = {
      name = "Groq",
      url = getenv("GROQ_API_URL", "https://api.groq.com/openai/v1") .. "/chat/completions",
      api_key_env = "GROQ_API_KEY",
      models = {
        llama_70b = "llama-3.3-70b-versatile",
        llama_8b = "llama-3.1-8b-instant",
      },
      default_model = "llama_70b",
    },
    together = {
      name = "Together",
      url = getenv("TOGETHER_API_URL", "https://api.together.xyz/v1") .. "/chat/completions",
      api_key_env = "TOGETHER_API_KEY",
      models = {
        mixtral = "mistralai/Mixtral-8x7B-Instruct-v0.1",
      },
      default_model = "mixtral",
    },
  },

  -- JMAP Configuration
  jmap = {
    url = getenv("JMAP_URL", "https://api.fastmail.com/.well-known/jmap"),
    username_env = "JMAP_USERNAME",
    password_env = "JMAP_PASSWORD",
    timeout_ms = 30000,
    max_body_bytes = 10 * 1024 * 1024, -- 10 MiB
  },

  -- Server Configuration
  server = {
    host = getenv("HOST", "127.0.0.1"),
    port = tonumber(getenv("PORT", "8080")),
  },

  -- HTTP Request Defaults
  http = {
    timeout_ms = 15000,
    max_body_bytes = 10 * 1024 * 1024, -- 10 MiB
  },

  -- Email Classification Categories (pluggable)
  categories = {
    "urgent_action_required",
    "pending_response",
    "informational",
    "automated_notification",
    "promotional",
    "spam_or_phishing",
  },

  -- Approval Settings
  approval = {
    -- Actions requiring approval
    require_approval = {
      send = true,
      delete_hard = true,
    },
    -- Safe actions (no approval needed)
    safe_actions = {
      archive = true,
      trash = true, -- trash is reversible
      mark_read = true,
      mark_unread = true,
    },
    -- Approval scopes: "once", "session", "always"
    default_scope = "once",
  },
}
