--- Builds a server's result and a database's result from the rows the mysql
--- queries print.

local columns = require("neo-tree-database.databases.mysql.columns")
local keys = require("neo-tree-database.databases.mysql.keys")
local quote = require("neo-tree-database.shared.quote")
local routines = require("neo-tree-database.databases.mysql.routines")
local rows = require("neo-tree-database.databases.mysql.rows")

local M = {}

--- Returns the result `catalogs` builds from `printed`. It has roles only when
--- the rows list accounts.
---@param printed table[]
---@return dbtree.Server
function M.server(printed)
  local tagged = rows.by_tag(printed)
  local server = {
    catalogs = vim.tbl_map(function(row)
      return { name = row.name }
    end, tagged.catalog or {}),
  }
  if not tagged.account then
    return server
  end

  local roles, role_by_name = {}, {}
  for _, row in ipairs(tagged.account) do
    local attributes = {}
    if rows.is_true(row.role) then
      table.insert(attributes, "ROLE")
    end
    if rows.is_true(row.locked) then
      table.insert(attributes, "ACCOUNT LOCK")
    end
    local role = { name = row.name, attributes = attributes, member_of = {}, members = {} }
    role_by_name[row.name] = role
    table.insert(roles, role)
  end
  for _, row in ipairs(tagged.membership or {}) do
    local granted, member = role_by_name[row.role], role_by_name[row.member]
    if granted and member then
      table.insert(member.member_of, granted.name)
      table.insert(granted.members, member.name)
    end
  end
  for _, role in ipairs(roles) do
    table.sort(role.member_of)
    table.sort(role.members)
  end
  server.roles = roles
  return server
end

--- Returns the grants in `grant_rows`, one per grantee with its privileges
--- sorted. A grantee's grants on a database stored under two spellings of its
--- name are merged into one, which keeps the first spelling.
---@param grant_rows table[]|nil
---@return dbtree.Grant[]
local function grants_of(grant_rows)
  local grants, grant_by_grantee = {}, {}
  for _, row in ipairs(grant_rows or {}) do
    local grant = grant_by_grantee[row.grantee]
    if not grant then
      grant = { grantee = row.grantee, privileges = {}, database = row.database }
      grant_by_grantee[row.grantee] = grant
      table.insert(grants, grant)
    end
    table.insert(grant.privileges, { name = row.privilege, grantable = row.grantable == "YES" })
  end
  table.sort(grants, function(a, b)
    return a.grantee < b.grantee
  end)
  for _, grant in ipairs(grants) do
    table.sort(grant.privileges, rows.by_name)
  end
  return grants
end

--- Returns the result `introspect` builds from `printed` for the database
--- `catalog`, which holds its objects itself.
---@param server dbtree.MysqlServer
---@param catalog string
---@param printed table[]
---@return dbtree.Catalog
function M.catalog(server, catalog, printed)
  local tagged = rows.by_tag(printed)
  local views = rows.group_by(tagged.view, "name")
  local column_rows = rows.group_by(tagged.column, "table")
  local index_parts = rows.group_by_table(tagged.index_column, "name")
  local constraints = rows.group_by(tagged.constraint, "table")
  local key_columns = rows.group_by_table(tagged.key_column, "constraint")
  local references = rows.group_by_table(tagged.reference, "constraint")
  local checks = rows.group_by_table(tagged.check, "constraint")
  local table_grants = rows.group_by(tagged.table_grant, "table")
  local column_grants = rows.group_by_table(tagged.column_grant, "column")
  local params = rows.group_by(tagged.parameter, "routine")

  local result = {
    grants = grants_of(tagged.database_grant),
    relations = {},
    sequences = {},
    functions = {},
  }

  for _, row in ipairs(tagged.relation or {}) do
    local name = row.name
    if row.type == "SEQUENCE" then
      table.insert(result.sequences, { name = name, size = row.size, size_estimated = row.size ~= nil })
    else
      local is_view = row.type == "VIEW" or row.type == "SYSTEM VIEW"
      -- mysql gives an empty definition to a user without SHOW VIEW.
      local view_definition = vim.tbl_get(views, name, 1, "definition")
      if view_definition == "" then
        view_definition = nil
      end
      local own_column_grants = column_grants[name] or {}

      ---@type dbtree.MysqlKeyRows
      local key_rows = {
        server = server,
        catalog = catalog,
        table_name = name,
        index_parts = index_parts[name] or {},
        constraints = constraints[name] or {},
        key_columns = key_columns[name] or {},
        references = references[name] or {},
        checks = checks[name] or {},
      }

      table.insert(result.relations, {
        name = name,
        kind = is_view and "view" or "table",
        rows = not is_view and row.rows or nil,
        size = row.size,
        size_estimated = row.size ~= nil,
        definition = view_definition
          and ("CREATE VIEW " .. quote.qualified(catalog, name, quote.MYSQL) .. " AS " .. view_definition .. ";"),
        columns = vim.tbl_map(function(column_row)
          return columns.column({
            server = server,
            row = column_row,
            grants = grants_of(own_column_grants[column_row.name]),
            table_collation = row.collation,
          })
        end, column_rows[name] or {}),
        indexes = keys.indexes(key_rows),
        constraints = keys.constraints(key_rows),
        grants = grants_of(table_grants[name]),
      })
    end
  end

  -- A function and a procedure may share a name, and with it a specific name.
  for _, row in ipairs(tagged.routine or {}) do
    local own_params = vim.tbl_filter(function(param)
      return param.kind == row.kind
    end, params[row.name] or {})
    table.insert(result.functions, routines.routine(catalog, row, own_params))
  end

  return result
end

return M
