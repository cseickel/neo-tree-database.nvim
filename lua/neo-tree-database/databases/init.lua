--- Picks the database module that handles a connection url, and declares the
--- results every database module returns.

local url = require("neo-tree-database.shared.url")

local M = {}

---@class dbtree.ListedCatalog
---@field name string
---@field size integer|nil Bytes on disk, nil when the database cannot report it.

---@class dbtree.Role
---@field name string
---@field attributes string[] Each as the database's CREATE statement spells it, such as `LOGIN`.
---@field member_of string[]
---@field members string[]

---@class dbtree.Server The result `catalogs` returns.
---@field catalogs dbtree.ListedCatalog[]
---@field roles dbtree.Role[]|nil Nil when the database has no roles, or does not let the user read them.

---@class dbtree.Objects What a schema holds, or a database that has no schemas.
---@field relations dbtree.Relation[]
---@field sequences dbtree.Sequence[]
---@field functions dbtree.Routine[]

---@class dbtree.Catalog : dbtree.Objects The result `introspect` returns. A database with schemas lists them in `schemas` and holds no objects itself.
---@field schemas dbtree.Schema[]|nil
---@field grants dbtree.Grant[]|nil

---@class dbtree.Schema : dbtree.Objects
---@field name string
---@field size integer|nil Bytes on disk of everything it holds.
---@field size_estimated boolean|nil
---@field grants dbtree.Grant[]|nil

---@class dbtree.Relation
---@field name string
---@field kind "table"|"view"|"materialized_view"
---@field rows integer|nil
---@field size integer|nil Bytes on disk, including its indexes.
---@field size_estimated boolean|nil
---@field definition string|nil
---@field columns dbtree.Column[]
---@field indexes dbtree.Index[]
---@field constraints dbtree.Constraint[]
---@field grants dbtree.Grant[]|nil

---@class dbtree.Column
---@field name string
---@field type string
---@field collation string|nil Set by mysql when the column's collation differs from its table's.
---@field nullable boolean
---@field default string|nil As sql, or the expression of a generated column.
---@field position integer
---@field identity string|nil postgres `attidentity`, `a` or `d`.
---@field generated string|nil postgres `attgenerated`, `s` for stored, or mysql `VIRTUAL` or `STORED`.
---@field options string[]|nil What mysql writes after a column's default, such as `AUTO_INCREMENT`.
---@field grants dbtree.Grant[]|nil

---@class dbtree.Index
---@field name string
---@field unique boolean
---@field size integer|nil Bytes on disk.
---@field size_estimated boolean|nil
---@field columns string[]
---@field definition string|nil
---@field owned_by_constraint boolean|nil

---@class dbtree.Constraint
---@field name string
---@field type string
---@field definition string

---@class dbtree.Sequence
---@field name string
---@field size integer|nil Bytes on disk.
---@field size_estimated boolean|nil
---@field definition string|nil
---@field grants dbtree.Grant[]|nil

---@class dbtree.Routine
---@field name string
---@field kind "function"|"procedure"|"aggregate"|"macro"|"table_macro"
---@field arguments string|nil postgres's list of argument types, which tells overloads apart.
---@field args dbtree.Argument[] Every argument, in the order declared.
---@field returns dbtree.Return|nil Nil when the function declares no return, as for a procedure or a macro.
---@field definition string|nil
---@field grants dbtree.Grant[]|nil

---@class dbtree.Field An argument or a returned column of a function.
---@field name string|nil Nil for an argument declared without a name.
---@field type string|nil Nil for a duckdb macro parameter declared without a type.
---@field default string|nil

---@class dbtree.Argument : dbtree.Field
---@field mode "in"|"out"|"inout"|"variadic"|"table"

---@class dbtree.Return
---@field type string
---@field set boolean Whether it returns SETOF the type.
---@field columns dbtree.Field[]|nil The type's columns, when it is a table or a composite type.

---@class dbtree.Grant
---@field grantee string|nil Nil for PUBLIC.
---@field privileges dbtree.Privilege[]
---@field database string|nil The database name as mysql stored a grant on the whole database, which may escape `_` and `%`.

---@class dbtree.Privilege
---@field name string As the database spells it, such as `SELECT` or `TEMPORARY`.
---@field grantable boolean Whether the grantee may grant it to other roles.

---@class dbtree.Scheme
---@field quoting dbtree.Quoting
---@field catalogs fun(connection: string, features: dbtree.Features): dbtree.Request
---@field catalog_url fun(connection: string, catalog: string): string
---@field introspect fun(catalog_url: string, catalog: string, features: dbtree.Features): dbtree.Request
---@field ddl fun(relation: dbtree.Relation, schema: string): string[]
---@field column_definition fun(column: dbtree.Column): string
---@field catalog_name fun(catalog: string, schema: string, relation: string): string[]
---@field privileges table<string, string[]>|nil The privileges each kind of grant target can hold, nil when the database has no grants.
---@field statements dbtree.Statements|nil Builders that replace the shared ones whose sql this database does not accept.

-- vim-dadbod accepts both `postgres` and `postgresql` urls.
local MODULE_BY_URL_SCHEME = {
  duckdb = "duckdb",
  mariadb = "mysql.mariadb",
  mysql = "mysql",
  postgres = "postgres",
  postgresql = "postgres",
}

--- Returns the database module for the url `connection`, or nil when
--- `connection` is nil or no module handles its scheme.
---@param connection string|nil
---@return dbtree.Scheme|nil
function M.of(connection)
  if type(connection) ~= "string" then
    return nil
  end

  local module_name = MODULE_BY_URL_SCHEME[url.scheme(connection)]
  if not module_name then
    return nil
  end
  return require("neo-tree-database.databases." .. module_name)
end

--- Returns the url schemes the tree can browse, sorted.
---@return string[]
function M.supported_schemes()
  local url_schemes = vim.tbl_keys(MODULE_BY_URL_SCHEME)
  table.sort(url_schemes)
  return url_schemes
end

return M
