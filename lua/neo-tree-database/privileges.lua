--[[
The privilege columns on a grant row.

Each `privilege` entry in a renderer is one column, and its `grants` lists the
privileges it shows. A row shows the ones its kind of object can have, held or
not, each in its own highlight. A row whose kind can have none of them shows a
blank cell.

The window's width picks how privileges are written: in full, as 3 letters, as
2, or as psql's one-letter codes. `levels` gives the narrowest window each of
the first three is used in.

neo-tree places right-aligned cells end to end from the right edge, so a cell
narrower than its column would pull every cell to its left out of line. Every
cell is therefore drawn at its column's full width, with its privileges at the
left and the padding after them. A column's width is set by its longest name in
the window's form, or by the codes of every privilege one kind matches in it,
whichever is wider.
]]

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

--- The default columns take 39 characters in full, 20 as 3 letters and 15 as
--- 2, and each level leaves at least 30 for the indent, icon and name. With
--- `grant_option = "asterisk"` every level takes 5 more.
---@type dbtree.PrivilegeLevels
local DEFAULT_LEVELS = { full = 75, three = 50, two = 45 }
--- Each privilege's code as psql's `\dp` writes it, its full form where the
--- name is too long for a column of the others, and its two-letter form where
--- the first two letters would not tell it apart from another.
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

local RELATION = { "SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER", "MAINTAIN" }
local ROUTINE = { "EXECUTE" }

--- The privileges each kind of grant target can have. `column` is a grant on
--- one column of a relation.
---@type table<string, string[]>
local POSSIBLE = {
  database = { "CONNECT", "CREATE", "TEMPORARY" },
  schema = { "USAGE", "CREATE" },
  table = RELATION,
  view = RELATION,
  materialized_view = RELATION,
  column = { "SELECT", "INSERT", "UPDATE", "REFERENCES" },
  sequence = { "SELECT", "UPDATE", "USAGE" },
  ["function"] = ROUTINE,
  procedure = ROUTINE,
  aggregate = ROUTINE,
}

--- The forms in order from the widest window to the narrowest. A cell starts
--- at the window's form and moves down the list until its privileges fit.
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
local function possible_for(target)
  local kind = target.column and "column" or target.kind
  local possible = POSSIBLE[kind]
  if not possible then
    error("neo-tree database: no privileges are known for a " .. kind)
  end
  return possible
end

--- The names in `grants` that appear in `possible`, in the column's order.
---@param grants string[]
---@param possible string[]
---@return string[]
local function shown(grants, possible)
  return vim.tbl_filter(function(name)
    return vim.list_contains(possible, name)
  end, grants)
end

--- How wide `names` are once shortened, counting a `*` after every one so the
--- width holds whichever of them are held with grant option.
---@param names string[]
---@param shorten fun(name: string): string
---@param asterisk boolean
---@return integer
local function width(names, shorten, asterisk)
  local total = #names - 1
  for _, name in ipairs(names) do
    total = total + #shorten(name) + (asterisk and 1 or 0)
  end
  return total
end

---@param grants string[]
---@param shorten fun(name: string): string
---@param asterisk boolean
---@return integer
local function column_width(grants, shorten, asterisk)
  local widest = 0
  for _, name in ipairs(grants) do
    widest = math.max(widest, width({ name }, shorten, asterisk))
  end
  for _, possible in pairs(POSSIBLE) do
    local names = shown(grants, possible)
    if #names > 0 then
      widest = math.max(widest, width(names, SHORTENINGS[#SHORTENINGS], asterisk))
    end
  end
  return widest
end

--- Which of `SHORTENINGS` a window `window_width` wide starts at.
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
---@return boolean asterisk
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
  local asterisk, levels = read_config(config)
  local level = level_for(levels, vim.api.nvim_win_get_width(state.winid))
  local cell_width = column_width(config.grants, SHORTENINGS[level], asterisk)
  ---@type dbtree.GrantRow
  local row = node.extra.record

  local names = shown(config.grants, possible_for(row.target))
  if #names == 0 then
    return { { text = string.rep(" ", cell_width + 1) } }
  end

  local shorten = SHORTENINGS[#SHORTENINGS]
  for i = level, #SHORTENINGS do
    if width(names, SHORTENINGS[i], asterisk) <= cell_width then
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
  local function add(piece)
    table.insert(pieces, piece)
    content_width = content_width + #piece.text
  end
  for i, name in ipairs(names) do
    if i > 1 then
      add({ text = " " })
    end
    local privilege = held[name]
    local grantable = privilege ~= nil and privilege.grantable
    local highlight = highlights.NOT_HELD
    if privilege then
      highlight = (grantable and not asterisk) and highlights.GRANTABLE or highlights.PRIVILEGE
    end
    if asterisk and grantable then
      add({ text = shorten(name) .. "*", highlight = highlight })
    else
      add({ text = shorten(name), highlight = highlight })
      -- Every privilege's `*` has the same place on every row, so one without
      -- it leaves the place blank.
      if asterisk then
        add({ text = " " })
      end
    end
  end

  if content_width < cell_width then
    table.insert(pieces, { text = string.rep(" ", cell_width - content_width) })
  end
  return pieces
end

return M
