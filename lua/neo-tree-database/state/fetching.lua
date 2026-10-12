--- Keeps the nodes whose queries are still running, and redraws their trees
--- while any runs, so their icons spin.

local renderer = require("neo-tree.ui.renderer")

local M = {}

M.FRAME_MS = 100

---@type table<string, neotree.State>
local state_by_id = {}

---@type uv.uv_timer_t|nil
local timer = nil

local function redraw_running()
  local drawn = {}
  for _, state in pairs(state_by_id) do
    if not drawn[state] then
      drawn[state] = true
      renderer.redraw(state)
    end
  end
end

---@param id string
---@return boolean
function M.has(id)
  return state_by_id[id] ~= nil
end

--- Marks the node `id` of `state`'s tree as querying.
---@param id string
---@param state neotree.State
function M.add(id, state)
  state_by_id[id] = state
  if not timer then
    timer = assert(vim.uv.new_timer())
    timer:start(M.FRAME_MS, M.FRAME_MS, vim.schedule_wrap(redraw_running))
  end
end

--- Marks the node `id` as done querying, and redraws its tree so its icon stops
--- spinning.
---@param id string
function M.remove(id)
  local state = state_by_id[id]
  state_by_id[id] = nil
  if timer and next(state_by_id) == nil then
    timer:stop()
    timer:close()
    timer = nil
  end
  if state then
    renderer.redraw(state)
  end
end

return M
