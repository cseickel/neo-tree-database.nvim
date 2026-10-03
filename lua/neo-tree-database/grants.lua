--[[
Who has been granted what.

A grant is shown from both ends. Under an object, a Grants folder lists each
role granted something on it. Under a role, each database lists every object
the role was granted something on. Both are read from the catalog document the
database itself shows, so each database is asked once for both.

Only direct grants are shown. Access a role has through another role is found
by following its Member of folder to that role.

Under a role, a function with several overloads is one row when the role holds
the same privileges on every overload, and otherwise one row per overload it
holds anything on, numbered as the tree numbers them.

The role side sees only what the catalog document holds: the database, its
schemas, and the tables, views, sequences and functions the tree lists. A grant
on a partition, on an object an extension created, on anything in pg_catalog,
or on a type, language or foreign server is not shown.
]]

local items = require("neo-tree-database.items")

local M = {}

---@class dbtree.Privilege
---@field name string As postgres spells it, such as `SELECT` or `TEMPORARY`.
---@field grantable boolean Whether the grantee may grant it on.

---@class dbtree.Grant
---@field grantee string|nil The role granted to, nil for PUBLIC.
---@field privileges dbtree.Privilege[]

---@class dbtree.GrantTarget
---@field kind string `database`, `schema`, a relation kind, `sequence`, or a function kind.
---@field name string
---@field schema string|nil Nil for a database or a schema.
---@field arguments string[]|nil For a function, the argument types of each overload the grant is on.
---@field overload integer|nil The overload's number, where the grant is on one of several.
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

--- The target of a grant on `routine`. `overload` is its number among the
--- overloads of its name, and nil where it has none.
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

--- Whether every one of `overloads` grants `grant`'s grantee the same
--- privileges as `grant` does.
---@param overloads dbtree.Routine[]
---@param grant dbtree.Grant
---@return boolean
local function granted_on_each(overloads, grant)
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

--- The grants on `overloads`, every overload of one function. A grantee holding
--- the same privileges on each overload gets one row naming the function, and
--- every other grant gets a row naming its overload.
---@param schema string
---@param overloads dbtree.Routine[]
---@return dbtree.GrantRow[]
local function routine_rows(schema, overloads)
  if #overloads == 1 then
    return M.rows(M.routine_target(schema, overloads[1]), overloads[1].grants)
  end

  local whole = M.routine_target(schema, overloads[1])
  if whole.arguments then
    whole.arguments = vim.tbl_map(function(routine)
      return routine.arguments
    end, overloads)
  end

  local rows = {}
  for number, routine in ipairs(overloads) do
    for _, grant in ipairs(routine.grants or {}) do
      if not granted_on_each(overloads, grant) then
        table.insert(rows, { target = M.routine_target(schema, routine, number), grant = grant })
      elseif number == 1 then
        table.insert(rows, { target = whole, grant = grant })
      end
    end
  end
  return rows
end

--- Each grant in `list` paired with `target`. `list` is nil where the database
--- keeps no grants.
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

--- The grants on `relation` and on each of its columns.
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

--- The Grants folder under `node`, or nothing when `rows` is empty.
---@param node dbtree.Item|NuiTree.Node
---@param rows dbtree.GrantRow[]
---@return dbtree.Item[]
function M.folder(node, rows)
  if #rows == 0 then
    return {}
  end
  local id = node.id .. "/@grants"
  return {
    items.container(id, "Grants", "folder", items.inherit(node.extra, {
      kind = "folder",
      folder = "grants",
      record = rows,
    })),
  }
end

--- `...` as id segments joined by `/`, stopping at the first nil.
---@param ... string|nil
---@return string
local function segments(...)
  local parts = {}
  for _, part in ipairs({ ... }) do
    table.insert(parts, items.segment(part))
  end
  return table.concat(parts, "/")
end

--- The rows of an object's Grants folder, each named by its grantee, such as
--- `bob`, or `bob (email)` for a grant on one column.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.grantees(node)
  local result = {}
  for _, row in ipairs(node.extra.record) do
    local grantee = row.grant.grantee
    local column = row.target.column
    local id = node.id .. "/" .. (grantee and items.segment(grantee) or "@public")
    local name = grantee or "PUBLIC"
    if column then
      id = id .. "/" .. items.segment(column)
      name = name .. " (" .. column .. ")"
    end
    table.insert(result, items.leaf(id, name, "grant", items.inherit(node.extra, { kind = "grant", record = row })))
  end
  return result
end

--- The object a grant is on, as a row on the role side names it, such as
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

--- Every grant `document` holds, on any object in it.
---@param catalog string
---@param document dbtree.Catalog
---@return dbtree.GrantRow[]
local function catalog_rows(catalog, document)
  local rows = M.rows(M.database_target(catalog), document.grants)
  for _, schema in ipairs(document.schemas or {}) do
    vim.list_extend(rows, M.rows(M.schema_target(schema.name), schema.grants))
    for _, relation in ipairs(schema.relations or {}) do
      vim.list_extend(rows, M.relation_rows(schema.name, relation))
    end
    for _, sequence in ipairs(schema.sequences or {}) do
      vim.list_extend(rows, M.rows(M.sequence_target(schema.name, sequence), sequence.grants))
    end
    for _, overloads in ipairs(items.overloads(schema.functions or {})) do
      vim.list_extend(rows, routine_rows(schema.name, overloads))
    end
  end
  return rows
end

--- What `grantee` was granted in `document`. A nil `grantee` is PUBLIC.
---@param catalog string
---@param document dbtree.Catalog
---@param grantee string|nil
---@return dbtree.GrantRow[]
function M.held_rows(catalog, document, grantee)
  local held = {}
  for _, row in ipairs(catalog_rows(catalog, document)) do
    if row.grant.grantee == grantee then
      table.insert(held, row)
    end
  end
  return held
end

--- What the role `node` stands for was granted in its catalog, each row named
--- by the object it grants on. `node.extra.grantee` is nil for PUBLIC.
---@param node dbtree.Item|NuiTree.Node
---@param document dbtree.Catalog
---@return dbtree.Item[]
function M.held(node, document)
  local extra = node.extra
  local result = {}
  for _, row in ipairs(M.held_rows(extra.catalog, document, extra.grantee)) do
    local target = row.target
    local id = node.id
      .. "/"
      .. segments(target.kind, target.schema or "", target.name, tostring(target.overload or ""), target.column)
    table.insert(
      result,
      items.leaf(id, M.object_name(target), "grant", items.inherit(extra, { kind = "grant", record = row }))
    )
  end
  return result
end

return M
