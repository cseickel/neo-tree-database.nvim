--[[
The highlight groups this source defines. Each links to a stock group by
default, so a user can restyle one of them without changing the stock group
everywhere else.
]]

local events = require("neo-tree.events")

local M = {}

M.PRIVILEGE = "NeoTreeDatabasePrivilege"

local function define()
  vim.api.nvim_set_hl(0, M.PRIVILEGE, { link = "Keyword", default = true })
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
