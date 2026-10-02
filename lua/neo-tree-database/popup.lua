--[[
Showing a statement or a description.

Either one is read before it is used, so it arrives in a window rather than in
a register or a buffer. From there `y` takes it, and for a statement `o` opens
it somewhere it can be run. Nothing here runs anything.

The buffer keeps neo-tree's own filetype, because other parts of neo-tree
recognise their popups by it, and is highlighted separately as sql or markdown.
]]

local NuiPopup = require("nui.popup")
local popups = require("neo-tree.ui.popups")

local M = {}

local MIN_WIDTH = 40
local MARGIN = 8

---@class dbtree.Shown
---@field title string
---@field lines string[]
---@field language "sql"|"markdown"
---@field on_open fun(lines: string[])|nil Opens the lines somewhere they can be run. `o` is mapped only when this is set.

--- The width that fits `lines` and `title` without overflowing the editor.
---@param lines string[]
---@param title string
---@return integer
local function width_for(lines, title)
  local width = math.max(MIN_WIDTH, vim.fn.strdisplaywidth(title) + 4)
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end
  return math.max(1, math.min(width, vim.o.columns - MARGIN))
end

---@param rows integer
---@return integer
local function height_for(rows)
  return math.max(1, math.min(rows, vim.o.lines - MARGIN))
end

---@param shown dbtree.Shown
function M.show(shown)
  local lines = shown.lines
  if #lines == 0 then
    vim.notify("neo-tree database: nothing to show for " .. shown.title, vim.log.levels.WARN)
    return
  end

  local keys = shown.on_open and "y yank, o open, q close" or "y yank, q close"
  local title = shown.title .. "  (" .. keys .. ")"
  local width = width_for(lines, title)

  local window = NuiPopup(popups.popup_options(title, MIN_WIDTH, {
    relative = "editor",
    position = "50%",
    size = { width = width, height = height_for(#lines) },
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

  if shown.language == "markdown" then
    vim.treesitter.start(window.bufnr, "markdown")
    vim.wo[window.winid].conceallevel = 2
    vim.wo[window.winid].concealcursor = "n"
  else
    vim.bo[window.bufnr].syntax = shown.language
  end
  vim.bo[window.bufnr].modifiable = false

  -- The rows on screen differ from the lines held once long lines wrap and the
  -- markdown fences are concealed.
  local rows = vim.api.nvim_win_text_height(window.winid, {}).all
  window:update_layout({ size = { width = width, height = height_for(rows) } })

  local text = table.concat(lines, "\n")
  window:map("n", "y", function()
    vim.fn.setreg('"', text, "l")
    vim.fn.setreg("+", text, "l")
    vim.fn.setreg("*", text, "l")
    window:unmount()
    vim.notify("neo-tree database: copied " .. shown.title)
  end, { noremap = true })

  local on_open = shown.on_open
  if on_open then
    window:map("n", "o", function()
      window:unmount()
      on_open(lines)
    end, { noremap = true })
  end

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
