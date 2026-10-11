--- Builds the statements that create, drop, and change a role or a grant.

local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")
local quote = require("neo-tree-database.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

local GRANT_OBJECT_KEYWORD = {
  database = "DATABASE",
  schema = "SCHEMA",
  table = "TABLE",
  view = "TABLE",
  materialized_view = "TABLE",
  sequence = "SEQUENCE",
  ["function"] = "ROUTINE",
  procedure = "ROUTINE",
  aggregate = "ROUTINE",
}

--- Returns the object that a GRANT names, listing every overload of a function
--- that the grant is on.
---@param target dbtree.GrantTarget
---@param quoting dbtree.Quoting
---@return string
local function grant_object(target, quoting)
  local keyword = GRANT_OBJECT_KEYWORD[target.kind]
  if not target.schema then
    return keyword .. " " .. quote.identifier(target.name, quoting)
  end
  local name = quote.qualified(target.schema, target.name, quoting)
  if not target.arguments then
    return keyword .. " " .. name
  end
  local signatures = vim.tbl_map(function(arguments)
    return items.signature(name, arguments)
  end, target.arguments)
  return keyword .. " " .. table.concat(signatures, ", ")
end

--- Returns `privileges` as a GRANT lists them, each followed by `column` when the
--- grant is on one column.
---@param privileges dbtree.Privilege[]
---@param column string|nil
---@param quoting dbtree.Quoting
---@return string
local function privilege_list(privileges, column, quoting)
  local column_suffix = column and (" (" .. quote.identifier(column, quoting) .. ")") or ""
  local names = {}
  for _, privilege in ipairs(privileges) do
    table.insert(names, privilege.name .. column_suffix)
  end
  return table.concat(names, ", ")
end

---@param grant dbtree.Grant
---@param quoting dbtree.Quoting
---@return string
local function grantee_sql(grant, quoting)
  return grant.grantee and quote.identifier(grant.grantee, quoting) or "PUBLIC"
end

---@param row dbtree.GrantRow
---@return string
local function grant_title(row)
  return (row.grant.grantee or "PUBLIC") .. " on " .. grants.object_name(row.target)
end

M.info.grant = function(node, scheme)
  local row = node.extra.record
  local quoting = scheme.quoting
  local object_clause = grant_object(row.target, quoting)
  local grantee_clause = grantee_sql(row.grant, quoting)

  -- WITH GRANT OPTION applies to every privilege a GRANT lists, so the
  -- grantable privileges get a GRANT of their own.
  local plain_privileges, grantable_privileges = {}, {}
  for _, privilege in ipairs(row.grant.privileges) do
    table.insert(privilege.grantable and grantable_privileges or plain_privileges, privilege)
  end

  local lines = {}
  if #plain_privileges > 0 then
    table.insert(
      lines,
      ("GRANT %s ON %s TO %s;"):format(
        privilege_list(plain_privileges, row.target.column, quoting),
        object_clause,
        grantee_clause
      )
    )
  end
  if #grantable_privileges > 0 then
    table.insert(
      lines,
      ("GRANT %s ON %s TO %s WITH GRANT OPTION;"):format(
        privilege_list(grantable_privileges, row.target.column, quoting),
        object_clause,
        grantee_clause
      )
    )
  end
  return { title = "Grant to " .. grant_title(row), lines = lines }
end

M.drop.grant = function(node, scheme)
  local row = node.extra.record
  local quoting = scheme.quoting
  return {
    title = "Revoke from " .. grant_title(row),
    lines = {
      ("REVOKE %s ON %s FROM %s;"):format(
        privilege_list(row.grant.privileges, row.target.column, quoting),
        grant_object(row.target, quoting),
        grantee_sql(row.grant, quoting)
      ),
    },
  }
end

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
