-- Minimal JSON encoder/decoder.
-- Dependency-free to keep lunet runtime small.

local M = {}

function M.encode(val)
  local t = type(val)
  if val == nil then return "null" end
  if t == "boolean" then return val and "true" or "false" end
  if t == "number" then return tostring(val) end
  if t == "string" then
    return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
  end
  if t ~= "table" then return "null" end

  local is_array = #val > 0
  if is_array then
    local parts = {}
    for i, v in ipairs(val) do parts[i] = M.encode(v) end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local parts = {}
  for k, v in pairs(val) do
    if type(k) == "string" then
      parts[#parts + 1] = '"' .. k .. '":' .. M.encode(v)
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.decode(str)
  local pos = 1

  local function skip_ws()
    pos = str:match("^%s*()", pos)
  end

  local function parse_value()
    skip_ws()
    local c = str:sub(pos, pos)
    if c == '"' then
      local start = pos + 1
      local i = start
      while i <= #str do
        local ch = str:sub(i, i)
        if ch == '"' and str:sub(i - 1, i - 1) ~= "\\" then
          pos = i + 1
          return str:sub(start, i - 1)
        end
        i = i + 1
      end
    end

    if c == "{" then
      pos = pos + 1
      local obj = {}
      skip_ws()
      if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip_ws()
        local key = parse_value()
        skip_ws()
        if str:sub(pos, pos) ~= ":" then error("Expected ':'") end
        pos = pos + 1
        obj[key] = parse_value()
        skip_ws()
        local sep = str:sub(pos, pos)
        if sep == "}" then pos = pos + 1; return obj end
        if sep == "," then pos = pos + 1 else error("Expected ',' or '}'") end
      end
    end

    if c == "[" then
      pos = pos + 1
      local arr = {}
      skip_ws()
      if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = parse_value()
        skip_ws()
        local sep = str:sub(pos, pos)
        if sep == "]" then pos = pos + 1; return arr end
        if sep == "," then pos = pos + 1 else error("Expected ',' or ']'") end
      end
    end

    if str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
    if str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
    if str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end

    if c == "-" or c:match("%d") then
      local num = str:match("^-?%d+%.?%d*", pos)
      pos = pos + #num
      return tonumber(num)
    end

    error("Unexpected char: " .. c)
  end

  return parse_value()
end

return M
