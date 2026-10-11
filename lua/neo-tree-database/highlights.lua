--- Defines this source's highlight groups, each of which takes the look of a stock
--- group by default.

local events = require("neo-tree.events")
local neo_highlights = require("neo-tree.ui.highlights")

local M = {}

M.PRIVILEGE = "NeoTreeDatabasePrivilege"
M.PRIVILEGE_NOT_HELD = "NeoTreeDatabasePrivilegeNotHeld"
M.PRIVILEGE_GRANTABLE = "NeoTreeDatabasePrivilegeGrantable"
M.SIZE = "NeoTreeDatabaseSize"
M.SIZE_KB = "NeoTreeDatabaseSizeKB"
M.SIZE_MB = "NeoTreeDatabaseSizeMB"
M.SIZE_GB = "NeoTreeDatabaseSizeGB"
M.ROWS = "NeoTreeDatabaseRows"
M.ROWS_K = "NeoTreeDatabaseRowsK"
M.ROWS_M = "NeoTreeDatabaseRowsM"
M.ROWS_B = "NeoTreeDatabaseRowsB"

--- Returns the current definition of `base` with `attributes` added. A link
--- cannot add attributes of its own, so the definition is copied.
---@param base string
---@param attributes table<string, boolean>
---@return vim.api.keyset.highlight
local function with_attributes(base, attributes)
  local definition = vim.api.nvim_get_hl(0, { name = base, link = false })
  definition.cterm = vim.tbl_extend("force", definition.cterm or {}, attributes)
  return vim.tbl_extend("force", definition, attributes, { default = true })
end

--- Returns the `0xRRGGBB` colour that is `amount` of the way from `from` to `to`.
---@param from integer
---@param to integer
---@param amount number
---@return integer
local function blend(from, to, amount)
  local mixed = 0
  for _, place in ipairs({ 0x10000, 0x100, 0x1 }) do
    local start, finish = math.floor(from / place) % 256, math.floor(to / place) % 256
    mixed = mixed + math.floor(start + (finish - start) * amount + 0.5) * place
  end
  return mixed
end

--- Returns `base` with its foreground blended `amount` of the way into the
--- tree's background. When `base` or the background has no colour set, it
--- returns a link to `fallback` instead.
---@param base string
---@param amount number
---@param fallback string
---@return vim.api.keyset.highlight
local function dimmed(base, amount, fallback)
  local definition = vim.api.nvim_get_hl(0, { name = base, link = false })
  local background = vim.api.nvim_get_hl(0, { name = neo_highlights.NORMAL, link = false }).bg
    or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  if not definition.fg or not background then
    return { link = fallback, default = true }
  end
  return vim.tbl_extend("force", definition, { fg = blend(definition.fg, background, amount), default = true })
end

---@param base string
---@param small string
---@param middle string
---@param large string
local function define_magnitudes(base, small, middle, large)
  vim.api.nvim_set_hl(0, small, dimmed(base, 0.5, neo_highlights.DIM_TEXT))
  vim.api.nvim_set_hl(0, middle, dimmed(base, 0.1, base))
  vim.api.nvim_set_hl(0, large, with_attributes(base, { bold = true }))
end

local function define_groups()
  vim.api.nvim_set_hl(0, M.SIZE, { link = "Number", default = true })
  define_magnitudes(M.SIZE, M.SIZE_KB, M.SIZE_MB, M.SIZE_GB)
  vim.api.nvim_set_hl(0, M.ROWS, { link = "String", default = true })
  define_magnitudes(M.ROWS, M.ROWS_K, M.ROWS_M, M.ROWS_B)
  vim.api.nvim_set_hl(0, M.PRIVILEGE, { link = "Keyword", default = true })
  vim.api.nvim_set_hl(0, M.PRIVILEGE_NOT_HELD, { link = neo_highlights.DIM_TEXT, default = true })
  vim.api.nvim_set_hl(0, M.PRIVILEGE_GRANTABLE, with_attributes(M.PRIVILEGE, { underline = true }))
end

--- Defines the groups, and defines them again whenever a colorscheme loads,
--- because loading one clears them.
function M.setup()
  define_groups()
  events.subscribe({
    event = events.VIM_COLORSCHEME,
    handler = define_groups,
    id = "neo-tree-database-highlights",
  })
end

return M
