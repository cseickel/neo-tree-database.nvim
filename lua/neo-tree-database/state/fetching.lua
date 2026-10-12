--- Keeps the ids of the nodes whose queries are still running.

local M = {}

---@type table<string, boolean>
local fetching_ids = {}

---@param id string
---@return boolean
function M.has(id)
  return fetching_ids[id] == true
end

---@param id string
function M.add(id)
  fetching_ids[id] = true
end

---@param id string
function M.remove(id)
  fetching_ids[id] = nil
end

return M
