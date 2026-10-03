--[[
The statements for a role and a grant.

A grant is written as the GRANT that made it and dropped as the REVOKE that
takes it back. Nothing alters a grant in place, so a grant has no change.
]]

local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")
local quote = require("neo-tree-database.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

--- The keyword a GRANT names each kind of object by. A view is granted on as a
--- TABLE, and every kind of function as a ROUTINE.
local ON = {
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

--- The object a GRANT names, listing every overload of a function it is on.
---@param target dbtree.GrantTarget
---@param quoting dbtree.Quoting
---@return string
local function object(target, quoting)
  if not target.schema then
    return ON[target.kind] .. " " .. quote.identifier(target.name, quoting)
  end
  local name = quote.qualified(target.schema, target.name, quoting)
  if not target.arguments then
    return ON[target.kind] .. " " .. name
  end
  local signatures = vim.tbl_map(function(arguments)
    return items.signature(name, arguments)
  end, target.arguments)
  return ON[target.kind] .. " " .. table.concat(signatures, ", ")
end

--- `privileges` as a GRANT lists them, each naming the column when the grant
--- is on one.
---@param privileges dbtree.Privilege[]
---@param column string|nil
---@param quoting dbtree.Quoting
---@return string
local function privilege_list(privileges, column, quoting)
  local suffix = column and (" (" .. quote.identifier(column, quoting) .. ")") or ""
  local names = {}
  for _, privilege in ipairs(privileges) do
    table.insert(names, privilege.name .. suffix)
  end
  return table.concat(names, ", ")
end

---@param grant dbtree.Grant
---@param quoting dbtree.Quoting
---@return string
local function grantee(grant, quoting)
  return grant.grantee and quote.identifier(grant.grantee, quoting) or "PUBLIC"
end

---@param row dbtree.GrantRow
---@return string
local function title(row)
  return (row.grant.grantee or "PUBLIC") .. " on " .. grants.object_name(row.target)
end

--- The privileges held with grant option are granted in a statement of their
--- own, because WITH GRANT OPTION applies to every privilege a GRANT lists.
M.info.grant = function(node, scheme)
  local row = node.extra.record
  local quoting = scheme.quoting
  local on = object(row.target, quoting)
  local to = grantee(row.grant, quoting)

  local plain, grantable = {}, {}
  for _, privilege in ipairs(row.grant.privileges) do
    table.insert(privilege.grantable and grantable or plain, privilege)
  end

  local lines = {}
  if #plain > 0 then
    table.insert(lines, ("GRANT %s ON %s TO %s;"):format(privilege_list(plain, row.target.column, quoting), on, to))
  end
  if #grantable > 0 then
    table.insert(
      lines,
      ("GRANT %s ON %s TO %s WITH GRANT OPTION;"):format(
        privilege_list(grantable, row.target.column, quoting),
        on,
        to
      )
    )
  end
  return { title = "Grant to " .. title(row), lines = lines }
end

M.drop.grant = function(node, scheme)
  local row = node.extra.record
  local quoting = scheme.quoting
  return {
    title = "Revoke from " .. title(row),
    lines = {
      ("REVOKE %s ON %s FROM %s;"):format(
        privilege_list(row.grant.privileges, row.target.column, quoting),
        object(row.target, quoting),
        grantee(row.grant, quoting)
      ),
    },
  }
end

M.info.role = function(node, scheme)
  local role = node.extra.record
  local name = quote.identifier(role.name, scheme.quoting)
  local with = #role.attributes > 0 and (" WITH " .. table.concat(role.attributes, " ")) or ""
  return { title = "Role " .. role.name, lines = { "CREATE ROLE " .. name .. with .. ";" } }
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
