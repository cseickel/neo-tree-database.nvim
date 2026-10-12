--- Keeps each query result from a database under the id of the connection or
--- database node it describes.

local M = {}

---@type table<string, table>
local results = {}

---@param id string
---@return table|nil
function M.get(id)
  return results[id]
end

---@param id string
---@param result table
function M.put(id, result)
  results[id] = result
end

--- Drops the results for `id` and for every id below it.
---@param id string
function M.drop(id)
  local prefix = id .. "/"
  for key in pairs(results) do
    if key == id or key:sub(1, #prefix) == prefix then
      results[key] = nil
    end
  end
end

return M
