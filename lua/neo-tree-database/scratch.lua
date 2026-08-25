--[[
Opening sql somewhere it can be run.

This plugin runs nothing, so a statement leaves it through here: a new buffer
holding the sql, with the connection set the way vim-dadbod expects to find it.
What happens to that buffer afterwards is the user's business, and a config
that wants a different window or a different naming replaces this function.
]]

local M = {}

---@class dbtree.Scratch
---@field url string The connection the statement was written against.
---@field lines string[]
---@field title string What the statement describes, for a buffer name.

--- Opens `spec` in a split below.
---
--- The connection is set after the filetype rather than before, because a
--- config with an autocmd on the sql filetype is free to assign `b:db` itself,
--- and the connection the user asked for is the one that should win.
---@param spec dbtree.Scratch
function M.open(spec)
  vim.cmd("botright new")

  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, spec.lines)
  vim.bo[buffer].filetype = "sql"
  vim.b[buffer].db = spec.url
  vim.bo[buffer].modified = false
end

return M
