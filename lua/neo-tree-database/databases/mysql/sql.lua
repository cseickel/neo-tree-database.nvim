--- Builds the sql that lists a mysql or mariadb server's databases and accounts,
--- and the sql that reads everything one database holds. Every row is a json
--- object whose `t` names what the row describes.

local M = {}

---@alias dbtree.MysqlServer "mysql"|"mariadb"

-- The server keeps its own tables in these, and its own accounts under these
-- names.
local SYSTEM_DATABASES = "'mysql', 'sys', 'information_schema', 'performance_schema'"
local SYSTEM_ACCOUNTS = "'mysql.sys', 'mysql.session', 'mysql.infoschema', 'mariadb.sys'"

--- Returns sql that writes the account `user`@`host` as information_schema
--- writes a grantee, such as `'app'@'%'`.
---@param user string
---@param host string
---@return string
local function account(user, host)
  return ("concat('''', %s, '''@''', %s, '''')"):format(user, host)
end

local CATALOGS = [[
select json_object('t', 'catalog', 'name', schema_name)
from information_schema.schemata
where schema_name not in (]] .. SYSTEM_DATABASES .. [[)
order by schema_name]]

-- A mysql role is an account like any other, which CREATE ROLE leaves locked.
local MYSQL_ACCOUNTS = [[
select json_object('t', 'account', 'name', ]] .. account("u.user", "u.host") .. [[, 'locked', u.account_locked = 'Y')
from mysql.user u
where u.user not in (]] .. SYSTEM_ACCOUNTS .. [[)
order by u.user, u.host;
select json_object(
  't', 'membership',
  'role', ]] .. account("e.from_user", "e.from_host") .. [[,
  'member', ]] .. account("e.to_user", "e.to_host") .. [[
)
from mysql.role_edges e]]

-- A mariadb role has an empty host.
local MARIADB_ACCOUNTS = [[
select json_object('t', 'account', 'name', ]] .. account("u.user", "u.host") .. [[, 'role', u.is_role = 'Y')
from mysql.user u
where u.user not in (]] .. SYSTEM_ACCOUNTS .. [[)
order by u.user, u.host;
select json_object(
  't', 'membership',
  'role', ]] .. account("m.role", "''") .. [[,
  'member', ]] .. account("m.user", "m.host") .. [[
)
from mysql.roles_mapping m]]

--- Returns the sql that lists the server's databases, and its accounts when
--- `with_accounts` is set. Reading accounts takes SELECT on the `mysql` schema.
---@param server dbtree.MysqlServer
---@param with_accounts boolean
---@return string
function M.catalogs(server, with_accounts)
  if not with_accounts then
    return CATALOGS
  end
  return CATALOGS .. ";\n" .. (server == "mariadb" and MARIADB_ACCOUNTS or MYSQL_ACCOUNTS)
end

-- Reading a table's row count or size makes the server open the table, which
-- can take ten times as long as listing the tables.
---@param read_sizes boolean
---@return string
local function relations(read_sizes)
  local sizes = read_sizes and [[
  'rows', t.table_rows,
  'size', t.data_length + t.index_length,
]] or ""
  return [[
select json_object(
  't', 'relation',
  'name', t.table_name,
  'type', t.table_type,
]] .. sizes .. [[
  'collation', t.table_collation
)
from information_schema.tables t
where t.table_schema = @catalog
order by t.table_name;
select json_object('t', 'view', 'name', v.table_name, 'definition', v.view_definition)
from information_schema.views v
where v.table_schema = @catalog;
select json_object(
  't', 'column',
  'table', c.table_name,
  'name', c.column_name,
  'type', c.column_type,
  'nullable', c.is_nullable,
  'default', c.column_default,
  'extra', c.extra,
  'generation', c.generation_expression,
  'collation', c.collation_name,
  'comment', c.column_comment,
  'position', c.ordinal_position
)
from information_schema.columns c
where c.table_schema = @catalog
order by c.table_name, c.ordinal_position]]
end

-- mysql writes a functional index part's expression in `expression`, a column
-- mariadb lacks.
---@param expression string
---@return string
local function indexes(expression)
  return [[
select json_object(
  't', 'index_column',
  'table', s.table_name,
  'name', s.index_name,
  'non_unique', s.non_unique,
  'type', s.index_type,
  'column', s.column_name,
  'expression', ]] .. expression .. [[,
  'sub_part', s.sub_part,
  'descending', s.collation = 'D'
)
from information_schema.statistics s
where s.table_schema = @catalog
order by s.table_name, s.index_name, s.seq_in_index]]
end

local CONSTRAINTS = [[
select json_object('t', 'constraint', 'table', k.table_name, 'name', k.constraint_name, 'type', k.constraint_type)
from information_schema.table_constraints k
where k.table_schema = @catalog
order by k.table_name, k.constraint_name;
select json_object(
  't', 'key_column',
  'table', u.table_name,
  'constraint', u.constraint_name,
  'column', u.column_name,
  'referenced_schema', u.referenced_table_schema,
  'referenced_table', u.referenced_table_name,
  'referenced_column', u.referenced_column_name
)
from information_schema.key_column_usage u
where u.table_schema = @catalog
order by u.table_name, u.constraint_name, u.ordinal_position;
select json_object(
  't', 'reference',
  'table', r.table_name,
  'constraint', r.constraint_name,
  'update_rule', r.update_rule,
  'delete_rule', r.delete_rule
)
from information_schema.referential_constraints r
where r.constraint_schema = @catalog]]

-- mysql's check_constraints has no table column, and names a check uniquely
-- within its database. mariadb names a check within its table.
local MYSQL_CHECKS = [[
select json_object('t', 'check', 'table', k.table_name, 'constraint', c.constraint_name, 'clause', c.check_clause)
from information_schema.check_constraints c
join information_schema.table_constraints k
  on k.constraint_schema = c.constraint_schema
 and k.constraint_name = c.constraint_name
 and k.constraint_type = 'CHECK'
where c.constraint_schema = @catalog]]

local MARIADB_CHECKS = [[
select json_object('t', 'check', 'table', c.table_name, 'constraint', c.constraint_name, 'clause', c.check_clause)
from information_schema.check_constraints c
where c.constraint_schema = @catalog]]

-- routine_definition is null for a routine the user neither defined nor holds
-- privileges to read. mariadb also lists packages here in its oracle mode.
local ROUTINES = [[
select json_object(
  't', 'routine',
  'name', r.routine_name,
  'kind', r.routine_type,
  'returns', r.dtd_identifier,
  'body', r.routine_definition,
  'deterministic', r.is_deterministic,
  'data_access', r.sql_data_access,
  'security', r.security_type
)
from information_schema.routines r
where r.routine_schema = @catalog and r.routine_type in ('FUNCTION', 'PROCEDURE')
order by r.routine_name, r.routine_type;
select json_object(
  't', 'parameter',
  'routine', p.specific_name,
  'kind', p.routine_type,
  'name', p.parameter_name,
  'mode', p.parameter_mode,
  'type', p.dtd_identifier
)
from information_schema.parameters p
where p.specific_schema = @catalog
  and p.ordinal_position > 0
  and p.routine_type in ('FUNCTION', 'PROCEDURE')
order by p.specific_name, p.ordinal_position]]

-- A grant on a whole database stores the name as the GRANT wrote it, so a
-- grant on `shop_db` may be stored as `shop\_db`. These tables list only the
-- grants the user may see, which is their own unless they can read the
-- `mysql` schema.
local GRANTS = [[
select json_object(
  't', 'database_grant',
  'grantee', g.grantee,
  'database', g.table_schema,
  'privilege', g.privilege_type,
  'grantable', g.is_grantable
)
from information_schema.schema_privileges g
where g.table_schema in (@catalog, @escaped);
select json_object(
  't', 'table_grant',
  'grantee', g.grantee,
  'table', g.table_name,
  'privilege', g.privilege_type,
  'grantable', g.is_grantable
)
from information_schema.table_privileges g
where g.table_schema = @catalog;
select json_object(
  't', 'column_grant',
  'grantee', g.grantee,
  'table', g.table_name,
  'column', g.column_name,
  'privilege', g.privilege_type,
  'grantable', g.is_grantable
)
from information_schema.column_privileges g
where g.table_schema = @catalog]]

--- Returns the sql that reads everything one database holds, with `@catalog`
--- standing for the database's name and `@escaped` for it with `_` and `%`
--- escaped.
---@param server dbtree.MysqlServer
---@param features dbtree.Features
---@return string
function M.introspect(server, features)
  local mariadb = server == "mariadb"
  local statements = {
    relations(features.read_sizes),
    indexes(mariadb and "null" or "s.expression"),
    CONSTRAINTS,
    mariadb and MARIADB_CHECKS or MYSQL_CHECKS,
    ROUTINES,
  }
  if features.read_grants then
    table.insert(statements, GRANTS)
  end
  return table.concat(statements, ";\n")
end

return M
