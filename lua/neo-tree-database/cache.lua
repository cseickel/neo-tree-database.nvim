--[[
What has already been asked of a database.

A connection answers twice: once with its catalogs, and once per catalog with
everything that catalog holds. Both answers are kept against the id of the node
that asked, so refreshing a node means dropping every key under it.

The cache is global while a neo-tree state is per tab, which is deliberate. Two
tabs browsing the same connection ask the database once between them, and each
tab's tree still opens and closes on its own.
]]

local M = {}

---@type table<string, table>
local answers = {}

--- What `id` last answered, nil when it has not been asked or has been dropped.
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

--- Forgets `id` and everything below it, so a refreshed catalog does not leave
--- the schemas it used to hold answering for the ones it holds now.
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
