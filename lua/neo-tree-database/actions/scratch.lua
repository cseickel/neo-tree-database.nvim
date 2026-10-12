--- Defines the action that opens a select from a relation in a scratch buffer,
--- and opens any sql in one.

local quote = require("neo-tree-database.shared.quote")
local shared = require("neo-tree-database.actions.shared")
local utils = require("neo-tree.utils")

local M = {}

---@class dbtree.Scratch
---@field state dbtree.State
---@field url string The url of the connection the statement was written for.
---@field lines string[]
---@field title string The buffer's name, without `.sql`.

---@param spec dbtree.Scratch
local function open_buffer(spec)
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

--- Opens `spec` with the user's `open_scratch` function when one is configured,
--- and in a new scratch buffer otherwise.
---@param spec dbtree.Scratch
function M.open(spec)
  local configured = spec.state.open_scratch
  if type(configured) == "function" then
    return configured(spec)
  end
  open_buffer(spec)
end

--- Opens a scratch buffer holding a select from the relation that the cursor is
--- on or inside.
---@param state dbtree.State
function M.open_scratch(state)
  local node = shared.node_under_cursor(state)
  if not node or not node.extra.relation then
    return vim.notify("neo-tree database: not inside a table or view", vim.log.levels.WARN)
  end

  local name = quote.qualified(node.extra.schema, node.extra.relation, shared.quoting_for(node))
  M.open({
    state = state,
    url = node.extra.url,
    title = node.extra.schema .. "." .. node.extra.relation,
    lines = { "select *", "from " .. name, "limit 100;" },
  })
end

return M
