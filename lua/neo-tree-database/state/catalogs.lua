--- Keeps each answer from a database against the id of the node that asked for it.

local M = {}

---@type table<string, table>
local answers = {}

---@param id string
---@return table|nil
function M.get(id)
  return answers[id]
end

---@param id string
---@param answer table
function M.put(id, answer)
  answers[id] = answer
end

--- Drops the answers for `id` and for every id below it.
---@param id string
function M.drop(id)
  local prefix = id .. "/"
  for key in pairs(answers) do
    if key == id or key:sub(1, #prefix) == prefix then
      answers[key] = nil
    end
  end
end

return M
