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

local function define()
  vim.api.nvim_set_hl(0, M.PRIVILEGE, { link = "Keyword", default = true })
  vim.api.nvim_set_hl(0, M.NOT_HELD, { link = neo_highlights.DIM_TEXT, default = true })
  -- A link cannot add an underline, so the held look is copied into the group.
  local held = vim.api.nvim_get_hl(0, { name = M.PRIVILEGE, link = false })
  local cterm = vim.tbl_extend("force", held.cterm or {}, { underline = true })
  vim.api.nvim_set_hl(0, M.GRANTABLE, vim.tbl_extend("force", held, { underline = true, cterm = cterm, default = true }))
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
