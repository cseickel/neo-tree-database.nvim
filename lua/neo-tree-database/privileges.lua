--- Renders the privilege columns of a grant row.

local highlights = require("neo-tree-database.highlights")

local M = {}

---@class dbtree.PrivilegeLevels
---@field full integer
---@field three integer
---@field two integer

---@class dbtree.PrivilegeColumn
---@field grants string[] The privileges this column shows, as postgres spells them.
---@field grant_option "highlight"|"asterisk"|nil How a privilege held with grant option is marked. Defaults to `highlight`.
---@field levels dbtree.PrivilegeLevels|nil The narrowest window each form is used in. Defaults to `DEFAULT_LEVELS`.

-- The default columns take 39 characters in full, 20 in three letters and 15 in
-- two, and each level leaves 30 or more for the indent, icon and name.
-- `grant_option = "asterisk"` adds 5 to each.
---@type dbtree.PrivilegeLevels
local DEFAULT_LEVELS = { full = 75, three = 50, two = 45 }

-- `code` is the letter psql's `\dp` uses. `word` replaces a name too long for its
-- column, and `two` replaces first two letters that another privilege shares.
---@type table<string, { code: string, word: string|nil, two: string|nil }>
local FORMS = {
  SELECT = { code = "r" },
  INSERT = { code = "a" },
  UPDATE = { code = "w" },
  DELETE = { code = "d" },
  TRUNCATE = { code = "D", two = "TC" },
  REFERENCES = { code = "x" },
  TRIGGER = { code = "t", two = "TG" },
  MAINTAIN = { code = "m" },
  CREATE = { code = "C" },
  CONNECT = { code = "c" },
  TEMPORARY = { code = "T", word = "TEMP" },
  EXECUTE = { code = "X" },
  USAGE = { code = "U" },
}

local RELATION_PRIVILEGES = { "SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER", "MAINTAIN" }
local ROUTINE_PRIVILEGES = { "EXECUTE" }

---@type table<string, string[]>
local PRIVILEGES_BY_KIND = {
  database = { "CONNECT", "CREATE", "TEMPORARY" },
  schema = { "USAGE", "CREATE" },
  table = RELATION_PRIVILEGES,
  view = RELATION_PRIVILEGES,
  materialized_view = RELATION_PRIVILEGES,
  column = { "SELECT", "INSERT", "UPDATE", "REFERENCES" },
  sequence = { "SELECT", "UPDATE", "USAGE" },
  ["function"] = ROUTINE_PRIVILEGES,
  procedure = ROUTINE_PRIVILEGES,
  aggregate = ROUTINE_PRIVILEGES,
}

-- Ordered from the full name down to psql's one-letter code.
---@type (fun(name: string): string)[]
local SHORTENINGS = {
  function(name)
    return FORMS[name].word or name
  end,
  function(name)
    return name:sub(1, 3)
  end,
  function(name)
    return FORMS[name].two or name:sub(1, 2)
  end,
  function(name)
    return FORMS[name].code
  end,
}

---@param target dbtree.GrantTarget
---@return string[]
local function privileges_for(target)
  local kind = target.column and "column" or target.kind
  local privileges = PRIVILEGES_BY_KIND[kind]
  if not privileges then
    error("neo-tree database: no privileges are known for a " .. kind)
  end
  return privileges
end

--- Returns the names in `grants` that are also in `privileges`, in the order of
--- `grants`.
---@param grants string[]
---@param privileges string[]
---@return string[]
local function applicable(grants, privileges)
  return vim.tbl_filter(function(name)
    return vim.list_contains(privileges, name)
  end, grants)
end

--- Returns the width of `names` once shortened and joined by spaces. With
--- `use_asterisk`, it counts a `*` after every name, so the width fits any of
--- them held with grant option.
---@param names string[]
---@param shorten fun(name: string): string
---@param use_asterisk boolean
---@return integer
local function shortened_width(names, shorten, use_asterisk)
  local total = #names - 1
  for _, name in ipairs(names) do
    total = total + #shorten(name) + (use_asterisk and 1 or 0)
  end
  return total
end

--- Returns the wider of two widths: the longest name in `grants` shortened by
--- `shorten`, and the codes of all the privileges in `grants` that one kind of
--- object can have.
---@param grants string[]
---@param shorten fun(name: string): string
---@param use_asterisk boolean
---@return integer
local function column_width(grants, shorten, use_asterisk)
  local widest = 0
  for _, name in ipairs(grants) do
    widest = math.max(widest, shortened_width({ name }, shorten, use_asterisk))
  end
  for _, kind_privileges in pairs(PRIVILEGES_BY_KIND) do
    local names = applicable(grants, kind_privileges)
    if #names > 0 then
      widest = math.max(widest, shortened_width(names, SHORTENINGS[#SHORTENINGS], use_asterisk))
    end
  end
  return widest
end

--- Returns the index in `SHORTENINGS` of the form that a window `window_width`
--- wide starts at.
---@param levels dbtree.PrivilegeLevels
---@param window_width integer
---@return integer
local function level_for(levels, window_width)
  if window_width >= levels.full then
    return 1
  elseif window_width >= levels.three then
    return 2
  elseif window_width >= levels.two then
    return 3
  end
  return 4
end

---@param config dbtree.PrivilegeColumn
---@return boolean use_asterisk
---@return dbtree.PrivilegeLevels levels
local function read_config(config)
  if type(config.grants) ~= "table" or #config.grants == 0 then
    error("neo-tree database: a privilege column needs a list of `grants`")
  end
  for _, name in ipairs(config.grants) do
    if not FORMS[name] then
      error("neo-tree database: " .. name .. " is not a postgres privilege")
    end
  end
  local grant_option = config.grant_option or "highlight"
  if grant_option ~= "highlight" and grant_option ~= "asterisk" then
    error('neo-tree database: grant_option is "highlight" or "asterisk", not ' .. tostring(grant_option))
  end
  local levels = vim.tbl_extend("force", DEFAULT_LEVELS, config.levels or {})
  for _, key in ipairs({ "full", "three", "two" }) do
    if type(levels[key]) ~= "number" then
      error("neo-tree database: levels." .. key .. " is a window width, not " .. tostring(levels[key]))
    end
  end
  if not (levels.full >= levels.three and levels.three >= levels.two) then
    error("neo-tree database: levels must narrow from full to three to two")
  end
  return grant_option == "asterisk", levels
end

---@param config dbtree.PrivilegeColumn
---@param node NuiTree.Node
---@param state neotree.State
---@return neotree.Render.Node[]
M.cell = function(config, node, state)
  local use_asterisk, levels = read_config(config)
  local level = level_for(levels, vim.api.nvim_win_get_width(state.winid))
  local cell_width = column_width(config.grants, SHORTENINGS[level], use_asterisk)
  ---@type dbtree.GrantRow
  local row = node.extra.record

  local names = applicable(config.grants, privileges_for(row.target))
  if #names == 0 then
    return { { text = string.rep(" ", cell_width + 1) } }
  end

  local shorten = SHORTENINGS[#SHORTENINGS]
  for i = level, #SHORTENINGS do
    if shortened_width(names, SHORTENINGS[i], use_asterisk) <= cell_width then
      shorten = SHORTENINGS[i]
      break
    end
  end

  ---@type table<string, dbtree.Privilege>
  local held = {}
  for _, privilege in ipairs(row.grant.privileges) do
    held[privilege.name] = privilege
  end

  local pieces = { { text = " " } }
  local content_width = 0
  local function append(piece)
    table.insert(pieces, piece)
    content_width = content_width + #piece.text
  end
  for i, name in ipairs(names) do
    if i > 1 then
      append({ text = " " })
    end
    local privilege = held[name]
    local grantable = privilege ~= nil and privilege.grantable
    local highlight = highlights.PRIVILEGE_NOT_HELD
    if privilege then
      highlight = (grantable and not use_asterisk) and highlights.PRIVILEGE_GRANTABLE or highlights.PRIVILEGE
    end
    if use_asterisk and grantable then
      append({ text = shorten(name) .. "*", highlight = highlight })
    else
      append({ text = shorten(name), highlight = highlight })
      -- Holds the place of the `*` that other rows show after this privilege.
      if use_asterisk then
        append({ text = " " })
      end
    end
  end

  -- neo-tree places right-aligned cells end to end without measuring them, so
  -- every cell is padded to its column's width.
  if content_width < cell_width then
    table.insert(pieces, { text = string.rep(" ", cell_width - content_width) })
  end
  return pieces
end

return M
