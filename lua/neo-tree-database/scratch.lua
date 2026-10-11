--- Opens sql in a new scratch buffer connected to the database it was written for.

local utils = require("neo-tree.utils")

local M = {}

---@class dbtree.Scratch
---@field state neotree.State
---@field url string The url of the connection the statement was written for.
---@field lines string[]
---@field title string The buffer's name, without `.sql`.

---@param spec dbtree.Scratch
function M.open(spec)
  local buffer_name = spec.title .. ".sql"
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, spec.lines)
  vim.api.nvim_buf_set_name(buffer, buffer_name)
  vim.bo[buffer].filetype = "sql"
  -- Set after the filetype, so it replaces any `b:db` that a sql filetype
  -- autocmd assigns.
  vim.b[buffer].db = spec.url
  vim.bo[buffer].modified = false
  utils.open_file(spec.state, buffer_name, nil, buffer)
end

return M
