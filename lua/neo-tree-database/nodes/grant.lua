--- Builds the grant rows, both in each object's Grants folder and under each
--- role.

local base = require("neo-tree-database.nodes.base")

local M = {}

---@class dbtree.GrantTarget
---@field kind string `database`, `schema`, a relation kind, `sequence`, or a function kind.
---@field name string
---@field schema string|nil Nil for a database or a schema.
---@field arguments string[]|nil For a function, the argument types of each overload the grant is on.
---@field overload integer|nil The overload's number, when the grant is on one of several overloads.
---@field column string|nil Set for a grant on one column of a relation.

---@class dbtree.GrantRow
---@field target dbtree.GrantTarget
---@field grant dbtree.Grant

---@param catalog string
---@return dbtree.GrantTarget
function M.database_target(catalog)
  return { kind = "database", name = catalog }
end

---@param schema string
---@return dbtree.GrantTarget
function M.schema_target(schema)
  return { kind = "schema", name = schema }
end

---@param schema string
---@param relation dbtree.Relation
---@return dbtree.GrantTarget
function M.relation_target(schema, relation)
  return { kind = relation.kind, schema = schema, name = relation.name }
end

---@param schema string
---@param sequence dbtree.Sequence
---@return dbtree.GrantTarget
function M.sequence_target(schema, sequence)
  return { kind = "sequence", schema = schema, name = sequence.name }
end

--- Returns the target of a grant on `routine`. `overload` is the routine's
--- number among the overloads of its name, and nil when the name has only one.
---@param schema string
---@param routine dbtree.Routine
---@param overload integer|nil
---@return dbtree.GrantTarget
function M.routine_target(schema, routine, overload)
  return {
    kind = routine.kind,
    schema = schema,
    name = routine.name,
    arguments = routine.arguments and { routine.arguments },
    overload = overload,
  }
end

--- Returns whether every routine in `overloads` gives `grant`'s grantee the same
--- privileges that `grant` does.
---@param overloads dbtree.Routine[]
---@param grant dbtree.Grant
---@return boolean
local function same_on_every_overload(overloads, grant)
  for _, routine in ipairs(overloads) do
    local same = vim.iter(routine.grants or {}):any(function(other)
      return other.grantee == grant.grantee and vim.deep_equal(other.privileges, grant.privileges)
    end)
    if not same then
      return false
    end
  end
  return true
end

--- Returns the grant rows for `overloads`, the overloads of one function. A
--- grantee that holds the same privileges on every overload gets one row for the
--- function, and each other grant gets a row for its overload.
---@param schema string
---@param overloads dbtree.Routine[]
---@return dbtree.GrantRow[]
local function routine_rows(schema, overloads)
  if #overloads == 1 then
    return M.rows(M.routine_target(schema, overloads[1]), overloads[1].grants)
  end

  local function_target = M.routine_target(schema, overloads[1])
  if function_target.arguments then
    function_target.arguments = vim.tbl_map(function(routine)
      return routine.arguments
    end, overloads)
  end

  local rows = {}
  for number, routine in ipairs(overloads) do
    for _, grant in ipairs(routine.grants or {}) do
      if not same_on_every_overload(overloads, grant) then
        table.insert(rows, { target = M.routine_target(schema, routine, number), grant = grant })
      elseif number == 1 then
        table.insert(rows, { target = function_target, grant = grant })
      end
    end
  end
  return rows
end

--- Returns a row pairing `target` with each grant in `list`.
---@param target dbtree.GrantTarget
---@param list dbtree.Grant[]|nil
---@return dbtree.GrantRow[]
function M.rows(target, list)
  local rows = {}
  for _, grant in ipairs(list or {}) do
    table.insert(rows, { target = target, grant = grant })
  end
  return rows
end

--- Returns the grant rows for `relation` and for each of its columns.
---@param schema string
---@param relation dbtree.Relation
---@return dbtree.GrantRow[]
function M.relation_rows(schema, relation)
  local target = M.relation_target(schema, relation)
  local rows = M.rows(target, relation.grants)
  for _, column in ipairs(relation.columns or {}) do
    local column_target = vim.tbl_extend("force", target, { column = column.name })
    vim.list_extend(rows, M.rows(column_target, column.grants))
  end
  return rows
end

--- Returns the Grants folder for `node`, or an empty list when `rows` is empty.
---@param node dbtree.Item|NuiTree.Node
---@param rows dbtree.GrantRow[]
---@return dbtree.Item[]
function M.folder(node, rows)
  if #rows == 0 then
    return {}
  end
  local id = node.id .. "/@grants"
  return {
    base.container(id, "Grants", "folder", base.inherit(node.extra, {
      kind = "folder",
      folder = "grants",
      record = rows,
    })),
  }
end

--- Returns the arguments up to the first nil as id segments joined by `/`.
---@param ... string|nil
---@return string
local function id_path(...)
  local parts = {}
  for _, part in ipairs({ ... }) do
    table.insert(parts, base.segment(part))
  end
  return table.concat(parts, "/")
end

--- Returns the items in an object's Grants folder, each named by its grantee,
--- such as `bob`, or `bob (email)` for a grant on one column.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.grantee_items(node)
  local result = {}
  for _, row in ipairs(node.extra.record) do
    local grantee = row.grant.grantee
    local column = row.target.column
    local id = node.id .. "/" .. (grantee and base.segment(grantee) or "@public")
    local name = grantee or "PUBLIC"
    if column then
      id = id .. "/" .. base.segment(column)
      name = name .. " (" .. column .. ")"
    end
    table.insert(result, base.leaf(id, name, "grant", base.inherit(node.extra, { kind = "grant", record = row })))
  end
  return result
end

--- Returns the name of a grant's object as a row under a role shows it, such as
--- `public.orders`, `public.orders.email` for a grant on one column, or
--- `public.total (2)` for a grant on one overload of several.
---@param target dbtree.GrantTarget
---@return string
function M.object_name(target)
  if not target.schema then
    return target.name
  end
  local name = target.schema .. "." .. target.name
  if target.overload then
    return name .. " (" .. target.overload .. ")"
  end
  return target.column and (name .. "." .. target.column) or name
end

--- Returns the grant rows of every object in `objects`, which `schema` holds.
---@param schema string
---@param objects dbtree.Objects
---@return dbtree.GrantRow[]
local function object_rows(schema, objects)
  local rows = {}
  for _, relation in ipairs(objects.relations or {}) do
    vim.list_extend(rows, M.relation_rows(schema, relation))
  end
  for _, sequence in ipairs(objects.sequences or {}) do
    vim.list_extend(rows, M.rows(M.sequence_target(schema, sequence), sequence.grants))
  end
  for _, overloads in ipairs(base.group_overloads(objects.functions or {})) do
    vim.list_extend(rows, routine_rows(schema, overloads))
  end
  return rows
end

---@param name string
---@param catalog dbtree.Catalog
---@return dbtree.GrantRow[]
local function catalog_rows(name, catalog)
  local rows = M.rows(M.database_target(name), catalog.grants)
  if not catalog.schemas then
    return vim.list_extend(rows, object_rows(name, catalog))
  end
  for _, schema in ipairs(catalog.schemas) do
    vim.list_extend(rows, M.rows(M.schema_target(schema.name), schema.grants))
    vim.list_extend(rows, object_rows(schema.name, schema))
  end
  return rows
end

--- Returns the grant rows in `catalog` whose grantee is `grantee`, where nil
--- means PUBLIC.
---@param name string
---@param catalog dbtree.Catalog
---@param grantee string|nil
---@return dbtree.GrantRow[]
function M.held_rows(name, catalog, grantee)
  local held_rows = {}
  for _, row in ipairs(catalog_rows(name, catalog)) do
    if row.grant.grantee == grantee then
      table.insert(held_rows, row)
    end
  end
  return held_rows
end

--- Returns the items under a role's catalog node, one per object that the role
--- was granted something on. `node.extra.grantee` is nil for PUBLIC.
---@param node dbtree.Item|NuiTree.Node
---@param catalog dbtree.Catalog
---@return dbtree.Item[]
function M.held_items(node, catalog)
  local extra = node.extra
  local result = {}
  for _, row in ipairs(M.held_rows(extra.catalog, catalog, extra.grantee)) do
    local target = row.target
    local id = node.id
      .. "/"
      .. id_path(target.kind, target.schema or "", target.name, tostring(target.overload or ""), target.column)
    table.insert(
      result,
      base.leaf(id, M.object_name(target), "grant", base.inherit(extra, { kind = "grant", record = row }))
    )
  end
  return result
end

return M
