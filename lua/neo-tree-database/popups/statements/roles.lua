--- Builds the statements that create, drop and rename a role.

local quote = require("neo-tree-database.shared.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

M.info.role = function(node, scheme)
  local role = node.extra.record
  local name = quote.identifier(role.name, scheme.quoting)
  local attribute_clause = #role.attributes > 0 and (" WITH " .. table.concat(role.attributes, " ")) or ""
  return { title = "Role " .. role.name, lines = { "CREATE ROLE " .. name .. attribute_clause .. ";" } }
end

M.drop.role = function(node, scheme)
  local role = node.extra.record
  return {
    title = "Drop role " .. role.name,
    lines = { "DROP ROLE " .. quote.identifier(role.name, scheme.quoting) .. ";" },
  }
end

M.change.role = function(node, scheme)
  local role = node.extra.record
  local name = quote.identifier(role.name, scheme.quoting)
  return { title = "Alter role " .. role.name, lines = { "ALTER ROLE " .. name .. " RENAME TO " .. name .. ";" } }
end

return M
