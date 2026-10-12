--- Builds the mysql statements that take the place of the shared ones whose sql
--- mysql does not accept.

local ddl = require("neo-tree-database.databases.mysql.ddl")
local grant_rows = require("neo-tree-database.nodes.grant")
local quote = require("neo-tree-database.shared.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

---@param name string
---@return string
local function identifier(name)
  return quote.identifier(name, quote.MYSQL)
end

---@param node NuiTree.Node
---@return string
local function table_name(node)
  return quote.qualified(node.extra.schema, node.extra.relation, quote.MYSQL)
end

---@param node NuiTree.Node
---@param clause string
---@return string
local function alter_table(node, clause)
  return "ALTER TABLE " .. table_name(node) .. " " .. clause .. ";"
end

M.info.catalog = function(node)
  return { title = "Database " .. node.extra.catalog, lines = { "CREATE DATABASE " .. identifier(node.extra.catalog) .. ";" } }
end

M.drop.catalog = function(node)
  return {
    title = "Drop database " .. node.extra.catalog,
    lines = { "DROP DATABASE " .. identifier(node.extra.catalog) .. ";" },
  }
end

local function rename_relation(node)
  local name = table_name(node)
  return {
    title = "Rename " .. node.extra.schema .. "." .. node.extra.relation,
    lines = { "RENAME TABLE " .. name .. " TO " .. name .. ";" },
  }
end

M.change.table = rename_relation
M.change.view = rename_relation

M.change.column = function(node)
  local column = node.extra.record
  local column_name = identifier(column.name)
  return {
    title = "Alter " .. node.extra.relation .. "." .. column.name,
    lines = {
      alter_table(node, "MODIFY COLUMN " .. ddl.column_definition(column)),
      alter_table(node, "RENAME COLUMN " .. column_name .. " TO " .. column_name),
    },
  }
end

---@param node NuiTree.Node
---@return string
local function drop_index(node)
  local index = node.extra.record
  if index.name == "PRIMARY" then
    return alter_table(node, "DROP PRIMARY KEY")
  end
  return "DROP INDEX " .. identifier(index.name) .. " ON " .. table_name(node) .. ";"
end

M.drop.index = function(node)
  return { title = "Drop " .. node.extra.record.name, lines = { drop_index(node) } }
end

M.change.index = function(node)
  local index_name = identifier(node.extra.record.name)
  return {
    title = "Alter " .. node.extra.record.name,
    lines = { alter_table(node, "RENAME INDEX " .. index_name .. " TO " .. index_name) },
  }
end

-- mysql drops a primary key, a unique key and a foreign key each by its own
-- clause.
---@param node NuiTree.Node
---@return string
local function drop_constraint(node)
  local constraint = node.extra.record
  if constraint.type == "PRIMARY KEY" then
    return alter_table(node, "DROP PRIMARY KEY")
  end
  if constraint.type == "FOREIGN KEY" then
    return alter_table(node, "DROP FOREIGN KEY " .. identifier(constraint.name))
  end
  if constraint.type == "UNIQUE" then
    return alter_table(node, "DROP INDEX " .. identifier(constraint.name))
  end
  return alter_table(node, "DROP CONSTRAINT " .. identifier(constraint.name))
end

---@param node NuiTree.Node
---@return string|nil
local function add_constraint(node)
  local constraint = node.extra.record
  if not constraint.definition then
    return nil
  end
  return alter_table(node, "ADD " .. ddl.constraint_clause(constraint))
end

M.info.constraint = function(node)
  local constraint = node.extra.record
  return {
    title = constraint.name,
    lines = { add_constraint(node) or ("-- " .. constraint.name .. " has no definition") },
  }
end

M.drop.constraint = function(node)
  return { title = "Drop " .. node.extra.record.name, lines = { drop_constraint(node) } }
end

M.change.constraint = function(node)
  local lines = { drop_constraint(node) }
  local add = add_constraint(node)
  if add then
    table.insert(lines, add)
  end
  return { title = "Replace " .. node.extra.record.name, lines = lines }
end

M.drop.routine = function(node)
  local routine = node.extra.record
  return {
    title = "Drop " .. node.extra.schema .. "." .. routine.name,
    lines = {
      "DROP "
        .. routine.kind:upper()
        .. " "
        .. quote.qualified(node.extra.schema, routine.name, quote.MYSQL)
        .. ";",
    },
  }
end

M.change.routine = function()
  return nil, "mysql cannot rename a function or a procedure"
end

---@param role dbtree.Role
---@return boolean
local function is_role(role)
  return vim.list_contains(role.attributes, "ROLE")
end

--- Returns `name` as a statement names the account, which for a mariadb role
--- leaves out the empty host it is stored with.
---@param name string
---@return string
local function grantee_sql(name)
  return (name:gsub("@''$", ""))
end

---@param role dbtree.Role
---@return string
local function account_name(role)
  return is_role(role) and grantee_sql(role.name) or role.name
end

M.info.role = function(node)
  local role = node.extra.record
  local lines
  if is_role(role) then
    lines = { "CREATE ROLE " .. account_name(role) .. ";" }
  else
    local lock = vim.list_contains(role.attributes, "ACCOUNT LOCK") and " ACCOUNT LOCK" or ""
    lines = { "CREATE USER " .. role.name .. lock .. ";" }
  end
  return { title = "Account " .. role.name, lines = lines }
end

M.drop.role = function(node)
  local role = node.extra.record
  local keyword = is_role(role) and "ROLE" or "USER"
  return { title = "Drop " .. role.name, lines = { "DROP " .. keyword .. " " .. account_name(role) .. ";" } }
end

M.change.role = function(node)
  local role = node.extra.record
  if is_role(role) then
    return nil, "mariadb cannot rename a role"
  end
  return { title = "Rename " .. role.name, lines = { "RENAME USER " .. role.name .. " TO " .. role.name .. ";" } }
end

--- Returns the object that a GRANT names. A grant on a whole database names it
--- as the server stored the grant, which may escape `_` and `%`.
---@param row dbtree.GrantRow
---@return string
local function grant_object(row)
  local target = row.target
  if not target.schema then
    return identifier(row.grant.database or target.name) .. ".*"
  end
  return quote.qualified(target.schema, target.name, quote.MYSQL)
end

---@param privileges dbtree.Privilege[]
---@param column string|nil
---@return string
local function privilege_list(privileges, column)
  local column_suffix = column and (" (" .. identifier(column) .. ")") or ""
  return table.concat(vim.tbl_map(function(privilege)
    return privilege.name .. column_suffix
  end, privileges), ", ")
end

---@param row dbtree.GrantRow
---@return string
local function grant_title(row)
  return row.grant.grantee .. " on " .. grant_rows.object_name(row.target)
end

M.info.grant = function(node)
  local row = node.extra.record
  local object = grant_object(row)

  -- WITH GRANT OPTION applies to every privilege a GRANT lists, so the
  -- grantable privileges get a GRANT of their own.
  local plain_privileges, grantable_privileges = {}, {}
  for _, privilege in ipairs(row.grant.privileges) do
    table.insert(privilege.grantable and grantable_privileges or plain_privileges, privilege)
  end

  local lines = {}
  for _, group in ipairs({ { plain_privileges, "" }, { grantable_privileges, " WITH GRANT OPTION" } }) do
    if #group[1] > 0 then
      table.insert(
        lines,
        ("GRANT %s ON %s TO %s%s;"):format(
          privilege_list(group[1], row.target.column),
          object,
          grantee_sql(row.grant.grantee),
          group[2]
        )
      )
    end
  end
  return { title = "Grant to " .. grant_title(row), lines = lines }
end

M.drop.grant = function(node)
  local row = node.extra.record
  return {
    title = "Revoke from " .. grant_title(row),
    lines = {
      ("REVOKE %s ON %s FROM %s;"):format(
        privilege_list(row.grant.privileges, row.target.column),
        grant_object(row),
        grantee_sql(row.grant.grantee)
      ),
    },
  }
end

return M
