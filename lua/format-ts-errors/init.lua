---@class Settings
---@field add_markdown boolean add markdown ticks before and after formatted objects
---@field start_indent_level integer how many indents in front of formatted object

---@type Settings
local DEFAULTS = {
  add_markdown = false,
  start_indent_level = 1,
}

local M = {
  ---@type Settings
  _settings = DEFAULTS,
}

M.setup = function(opts)
  M._settings = vim.tbl_extend("force", DEFAULTS, opts or {})
end

-- ===========================================================================
-- Formatting utils
-- ===========================================================================

---@param csv string like abc,def,ghi
---@return string # bulletted list like
--- • abc
--- • def
--- • ghi
M.bulletted = function(csv)
  return table.concat(
    vim
      .iter(vim.fn.split(csv, ", "))
      :map(function(k)
        return (" • %s"):format(k)
      end)
      :totable(),
    "\n"
  )
end

---@param o string e.g. {someinlinebrackets;likethis;}
---@return string,string[] # return indented pretty type def, e.g.:
--- {
---   someinlinebrackets;
---   likethis;
--- }
M.format_object_type = function(o)
  o = vim.fn.substitute(o, "; ", ";", "g")
  o = vim.fn.substitute(o, ";", ";\n", "g")
  o = vim.fn.substitute(o, "{ ", "{\n", "g")

  -- indent
  o = vim.fn.split(o, "\n")
  local lines = {}
  local level = M._settings.start_indent_level
  for _, line in ipairs(o) do
    -- just a closing, unindent this iteration
    if not line:find("{") and line:find("}") then
      level = level - 1
    end

    local spaces = ("  "):rep(level)
    table.insert(lines, spaces .. line)

    -- just an opening, indent next iteration
    if line:find("{") and not line:find("}") then
      level = level + 1
    end
  end

  local formatted = table.concat(lines, "\n")

  -- Single item -------------------------------------------------------------
  if #lines == 1 then
    -- Surround in backticks, even when no markdown requested
    if M._settings.add_markdown then
      return ("`%s`\n"):format(formatted), lines
    end
    -- Surround in single quote like original
    return ("'%s'\n"):format(formatted), lines
  end

  -- Multiline ---------------------------------------------------------------
  -- add markdown fencing?
  if M._settings.add_markdown then
    -- ensure fenced code is also surrounded by newlines
    return ("\n```typescript\n%s\n```\n"):format(formatted), lines
  end
  --- don't add markdown fencing
  return formatted, lines
end

---Given msg, apply matchers and concat results
---@param msg string
---@param matchers string[]
---@return string
M.format_lines = function(msg, matchers)
  local formatted_lines = {}
  local lines = vim.fn.split(msg, "\n")
  for _, line in ipairs(lines) do
    local matcher_result = ""
    for _, matcher in ipairs(matchers) do
      if matcher_result:len() == 0 then
        matcher_result = M.line_parsers[matcher](line)
        if matcher_result:len() > 0 then
          table.insert(formatted_lines, matcher_result)
        end
      end
    end
    -- no match, return default
    if matcher_result:len() == 0 then
      table.insert(formatted_lines, line)
    end
  end

  return table.concat(formatted_lines, "\n")
end

-- ===========================================================================
-- Parsers
-- ===========================================================================

M.line_parsers = {

  -- Property 'public_token' is missing in type '{}' but required in type 'ItemPublicTokenExchangeRequest'.
  threepat = function(line)
    ---@diagnostic disable-next-line: unused-local
    local found, _ei, p1, prop, p2, ours, p3, theirs =
      line:find("(%S.-) '(.-)' (.- type) '(.-)' (.- type) '(.-)'.")
    if found then
      local formatted_theirs, lines_theirs = M.format_object_type(theirs)
      local last = (#lines_theirs > 1 and "%s\n%s" or "%s %s"):format(
        p3,
        formatted_theirs
      )
      return table.concat({
        ("%s %s %s"):format(p1, prop, p2),
        M.format_object_type(ours),
        last,
      }, "\n")
    end
    return ""
  end,

  -- 1. Argument of type '{}' is not assignable to parameter of type 'ItemPublicTokenExchangeRequest'.
  -- 2. Type 'string' is not assignable to type 'undefined'
  twopat = function(line)
    ---@diagnostic disable-next-line: unused-local
    local found, _ei, p1, ours, p2, theirs =
      line:find("(%S.-) '(.-)' (.- type) '(.-)'.")
    if found then
      return (
        ("%s\n%s\n"):format(p1, ours)
        .. ("%s\n%s"):format(p2, M.format_object_type(theirs))
      )
    end
    return ""
  end,

  -- Just like missing_named_properties but "of" instead of "type"
  -- Bullet list the missing keys
  -- Non-abstract class 'PolygonClientHandler' is missing implementations for the following members of 'AbstractKeyedWSHandler<BarsClientMessage, BarChannel, Destroyable>': 'createSubscription', 'parseMessage', 'onParsedMessage'.
  missing_implementations = function(line)
    ---@diagnostic disable-next-line: unused-local
    local found, _pos, before, classname, mid, abstractclassname, types =
      line:find("(%S.-) '(.-)' (.- of) '(.-)': (.+)")
    if found then
      local missing = M.bulletted(types)
      return table.concat({
        ("%s\n%s"):format(before, M.format_object_type(classname)),
        ("%s\n%s"):format(mid, M.format_object_type(abstractclassname)),
        missing,
      }, "\n")
    end
    return ""
  end,

  -- Just like missing_implementations but "type" instead of "of"
  -- Type '{}' is missing the following properties from type 'LinkTokenCreateRequest': client_name, language, country_codes, user
  missing_named_properties = function(line)
    ---@diagnostic disable-next-line: unused-local
    local found, _pos, before, classname, mid, interface, keys =
      line:find("(%S.-) '(.-)' (.- type) '(.-)': (.+)")
    if found then
      local missing = M.bulletted(keys)
      return table.concat({
        ("%s\n%s"):format(before, M.format_object_type(classname)),
        ("%s\n%s"):format(mid, M.format_object_type(interface)),
        missing,
      }, "\n")
    end
    return ""
  end,
}

return M
