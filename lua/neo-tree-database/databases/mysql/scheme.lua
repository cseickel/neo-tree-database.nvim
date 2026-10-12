--- Builds the database module for a mysql or a mariadb server, which differ only
--- in a few of the tables they keep.

local client = require("neo-tree-database.databases.client")
local ddl = require("neo-tree-database.databases.mysql.ddl")
local queries = require("neo-tree-database.databases.mysql.sql")
local quote = require("neo-tree-database.shared.quote")
local result = require("neo-tree-database.databases.mysql.result")

local RELATION_PRIVILEGES = {
  "SELECT",
  "INSERT",
  "UPDATE",
  "DELETE",
  "CREATE",
  "DROP",
  "REFERENCES",
  "INDEX",
  "ALTER",
  "CREATE VIEW",
  "SHOW VIEW",
  "TRIGGER",
}

-- A grant on a whole database can hold any privilege a table can, and those
-- that act on the database's other objects.
local DATABASE_PRIVILEGES = {
  "CREATE TEMPORARY TABLES",
  "LOCK TABLES",
  "EXECUTE",
  "CREATE ROUTINE",
  "ALTER ROUTINE",
  "EVENT",
}

--- Returns the privileges each kind of grant target can hold on `server`.
--- mariadb adds DELETE HISTORY, for its system-versioned tables.
---@param server dbtree.MysqlServer
---@return table<string, string[]>
local function privileges_by_kind(server)
  local relation = vim.deepcopy(RELATION_PRIVILEGES)
  if server == "mariadb" then
    table.insert(relation, "DELETE HISTORY")
  end
  return {
    database = vim.list_extend(vim.deepcopy(relation), DATABASE_PRIVILEGES),
    table = relation,
    view = relation,
    column = { "SELECT", "INSERT", "UPDATE", "REFERENCES" },
  }
end

-- Reading accounts takes SELECT on the `mysql` schema, which the server
-- refuses with an error such as `SELECT command denied to user`.
local ACCOUNTS_DENIED = "command denied"

---@param connection string
---@param statement string
---@param decode fun(output: string): table
---@return dbtree.Request
local function request_for(connection, statement, decode)
  return { url = connection, statement = statement, decode = decode }
end

---@param server dbtree.MysqlServer
---@return dbtree.Scheme
return function(server)
  local function decode_server(output)
    return result.server(client.json_rows(output))
  end

  ---@type dbtree.Scheme
  return {
    quoting = quote.MYSQL,
    ddl = ddl.ddl,
    column_definition = ddl.column_definition,
    statements = require("neo-tree-database.databases.mysql.statements"),
    privileges = privileges_by_kind(server),

    --- Returns a request that lists the server's databases and accounts, and
    --- falls back to the databases alone when the user cannot read accounts.
    --- The list holds no sizes, so neither feature changes it.
    catalogs = function(connection)
      local request = request_for(connection, queries.catalogs(server, true), decode_server)
      request.fallback = {
        error = ACCOUNTS_DENIED,
        request = request_for(connection, queries.catalogs(server, false), decode_server),
      }
      return request
    end,

    --- Returns `connection` unchanged, because one connection reads every
    --- database through information_schema.
    catalog_url = function(connection)
      return connection
    end,

    introspect = function(catalog_url, catalog, features)
      local statement = quote.render(queries.introspect(server, features), {
        catalog = quote.literal(catalog, quote.MYSQL),
        escaped = quote.literal((catalog:gsub("[_%%]", "\\%0")), quote.MYSQL),
      })
      return request_for(catalog_url, statement, function(output)
        return result.catalog(server, catalog, client.json_rows(output))
      end)
    end,

    --- Returns the name path that db-query's catalog knows a relation by. It
    --- starts at the database, which db-query's mysql catalog calls the schema.
    catalog_name = function(catalog, schema, relation)
      return { schema, relation }
    end,
  }
end
