--[[
The highlight groups this source defines. Each takes a stock group's look by
default, so a user can restyle one of them without changing the stock group
everywhere else.
]]

local events = require("neo-tree.events")
local neo_highlights = require("neo-tree.ui.highlights")

local M = {}

--- A privilege the grantee holds.
M.PRIVILEGE = "NeoTreeDatabasePrivilege"
--- A privilege the grantee could be granted on the object and was not.
M.NOT_HELD = "NeoTreeDatabasePrivilegeNotHeld"
--- A privilege the grantee holds with grant option.
M.GRANTABLE = "NeoTreeDatabasePrivilegeGrantable"
--- The look each size group starts from.
M.SIZE = "NeoTreeDatabaseSize"
M.SIZE_KB = "NeoTreeDatabaseSizeKB"
M.SIZE_MB = "NeoTreeDatabaseSizeMB"
M.SIZE_GB = "NeoTreeDatabaseSizeGB"
--- The look each row estimate group starts from.
M.ROWS = "NeoTreeDatabaseRows"
M.ROWS_K = "NeoTreeDatabaseRowsK"
M.ROWS_M = "NeoTreeDatabaseRowsM"
M.ROWS_B = "NeoTreeDatabaseRowsB"

--- Returns `base` as it resolves now, with `attributes` added. A link cannot
--- add an attribute, so the look is copied.
---@param base string
---@param attributes table<string, boolean>
---@return vim.api.keyset.highlight
local function adding(base, attributes)
  local look = vim.api.nvim_get_hl(0, { name = base, link = false })
  look.cterm = vim.tbl_extend("force", look.cterm or {}, attributes)
  return vim.tbl_extend("force", look, attributes, { default = true })
end

--- Returns the `0xRRGGBB` colour `amount` of the way from `from` to `to`.
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
--- tree's background. A colour that is not set cannot be blended, so a base or
--- a background without one gives `fallback` instead.
---@param base string
---@param amount number
---@param fallback string The group to link to.
---@return vim.api.keyset.highlight
local function dimmed(base, amount, fallback)
  local look = vim.api.nvim_get_hl(0, { name = base, link = false })
  local background = vim.api.nvim_get_hl(0, { name = neo_highlights.NORMAL, link = false }).bg
    or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  if not look.fg or not background then
    return { link = fallback, default = true }
  end
  return vim.tbl_extend("force", look, { fg = blend(look.fg, background, amount), default = true })
end

--- Defines `small`, `middle` and `large` from `base`: dimmed by half, dimmed by
--- a tenth, and bold.
---@param base string
---@param small string
---@param middle string
---@param large string
local function define_magnitudes(base, small, middle, large)
  vim.api.nvim_set_hl(0, small, dimmed(base, 0.5, neo_highlights.DIM_TEXT))
  vim.api.nvim_set_hl(0, middle, dimmed(base, 0.1, base))
  vim.api.nvim_set_hl(0, large, adding(base, { bold = true }))
end

local function define()
  vim.api.nvim_set_hl(0, M.SIZE, { link = "Number", default = true })
  define_magnitudes(M.SIZE, M.SIZE_KB, M.SIZE_MB, M.SIZE_GB)
  vim.api.nvim_set_hl(0, M.ROWS, { link = "String", default = true })
  define_magnitudes(M.ROWS, M.ROWS_K, M.ROWS_M, M.ROWS_B)
  vim.api.nvim_set_hl(0, M.PRIVILEGE, { link = "Keyword", default = true })
  vim.api.nvim_set_hl(0, M.NOT_HELD, { link = neo_highlights.DIM_TEXT, default = true })
  vim.api.nvim_set_hl(0, M.GRANTABLE, adding(M.PRIVILEGE, { underline = true }))
end

--- Defines the groups, and defines them again after every colorscheme, which
--- clears them when it loads.
function M.setup()
  define()
  events.subscribe({
    event = events.VIM_COLORSCHEME,
    handler = define,
    id = "neo-tree-database-highlights",
  })
end

return M
