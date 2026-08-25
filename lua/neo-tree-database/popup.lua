--[[
Showing a statement.

A statement is read before it is used, so it arrives in a window rather than in
a register or a buffer. From there `y` takes it and `o` opens it somewhere it
can be run. Nothing here runs anything.

The buffer keeps neo-tree's own filetype, because other parts of neo-tree
recognise their popups by it, and takes sql syntax separately so the statement
is still coloured.
]]

local NuiPopup = require("nui.popup")
local popups = require("neo-tree.ui.popups")

local M = {}

local MIN_WIDTH = 40
local MARGIN = 8

--- The width and height that fit `lines` without overflowing the editor.
---@param lines string[]
---@param title string
---@return integer width
---@return integer height
local function size_for(lines, title)
  local width = math.max(MIN_WIDTH, vim.fn.strdisplaywidth(title) + 4)
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end
  return math.max(1, math.min(width, vim.o.columns - MARGIN)),
    math.max(1, math.min(#lines, vim.o.lines - MARGIN))
end

--- Shows `statement`, with `on_open` called with its lines if the user asks for
--- it somewhere it can be edited.
---@param statement dbtree.Statement
---@param on_open fun(lines: string[])
function M.show(statement, on_open)
  local lines = statement.lines
  if #lines == 0 then
    vim.notify("neo-tree database: nothing to show for " .. statement.title, vim.log.levels.WARN)
    return
  end

  local title = statement.title .. "  (y yank, o open, q close)"
  local width, height = size_for(lines, title)

  local window = NuiPopup(popups.popup_options(title, MIN_WIDTH, {
    relative = "editor",
    position = "50%",
    size = { width = width, height = height },
    zindex = 60,
    enter = true,
  }))
  window:mount()

  local written, err = pcall(vim.api.nvim_buf_set_lines, window.bufnr, 0, -1, false, lines)
  if not written then
    window:unmount()
    vim.notify("neo-tree database: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  vim.bo[window.bufnr].syntax = "sql"
  vim.bo[window.bufnr].modifiable = false

  local text = table.concat(lines, "\n")
  window:map("n", "y", function()
    vim.fn.setreg('"', text, "l")
    vim.fn.setreg("+", text, "l")
    vim.fn.setreg("*", text, "l")
    window:unmount()
    vim.notify("neo-tree database: copied " .. statement.title)
  end, { noremap = true })

  window:map("n", "o", function()
    window:unmount()
    on_open(lines)
  end, { noremap = true })

  for _, key in ipairs({ "q", "<esc>" }) do
    window:map("n", key, function()
      window:unmount()
    end, { noremap = true })
  end

  window:on(require("nui.utils.autocmd").event.BufLeave, function()
    window:unmount()
  end, { once = true })
end

return M
