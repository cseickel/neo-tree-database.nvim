--- Shows a statement or a description in a popup window.

local NuiPopup = require("nui.popup")
local popups = require("neo-tree.ui.popups")

local M = {}

local MIN_WIDTH = 40
local MARGIN = 8

---@class dbtree.PopupContent
---@field title string
---@field lines string[]
---@field language "sql"|"markdown"
---@field on_open fun(lines: string[])|nil Called with the lines when the user presses `o`, which is mapped only when this is set.

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

---@param content dbtree.PopupContent
function M.show(content)
  local lines = content.lines
  if #lines == 0 then
    vim.notify("neo-tree database: nothing to show for " .. content.title, vim.log.levels.WARN)
    return
  end

  local key_hints = content.on_open and "y yank, o open, q close" or "y yank, q close"
  local title = content.title .. "  (" .. key_hints .. ")"
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

  -- neo-tree recognises its popups by their filetype, so the language is set
  -- through treesitter or syntax instead.
  if content.language == "markdown" then
    vim.treesitter.start(window.bufnr, "markdown")
    vim.wo[window.winid].conceallevel = 2
    vim.wo[window.winid].concealcursor = "n"
  else
    vim.bo[window.bufnr].syntax = content.language
  end
  vim.bo[window.bufnr].modifiable = false

  -- Wrapped lines and concealed markdown fences make the rows on screen differ
  -- from the number of lines.
  local rows = vim.api.nvim_win_text_height(window.winid, {}).all
  window:update_layout({ size = { width = width, height = height_for(rows) } })

  local copied_text = table.concat(lines, "\n")
  window:map("n", "y", function()
    vim.fn.setreg('"', copied_text, "l")
    vim.fn.setreg("+", copied_text, "l")
    vim.fn.setreg("*", copied_text, "l")
    window:unmount()
    vim.notify("neo-tree database: copied " .. content.title)
  end, { noremap = true })

  local on_open = content.on_open
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
