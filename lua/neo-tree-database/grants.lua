--[[
Who has been granted what.

A grant is shown from both ends. Under an object, a Grants folder lists each
role granted something on it. Under a role, each database lists every object
the role was granted something on. Both are read from the catalog document the
database itself shows, so each database is asked once for both.

Only direct grants are shown. Access a role has through another role is found
by following its Member of folder to that role.

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
---@field arguments string|nil A function's argument types.
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

---@param schema string
---@param routine dbtree.Routine
---@return dbtree.GrantTarget
function M.routine_target(schema, routine)
  return { kind = routine.kind, schema = schema, name = routine.name, arguments = routine.arguments }
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

--- How a row on the role side is named: by the object it grants on, such as
--- `public.orders`, or `public.orders.email` for a grant on one column.
---@param target dbtree.GrantTarget
---@return string
local function object_name(target)
  if not target.schema then
    return target.name
  end
  local name = target.schema .. "." .. items.signature(target.name, target.arguments)
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
    for _, routine in ipairs(schema.functions or {}) do
      vim.list_extend(rows, M.rows(M.routine_target(schema.name, routine), routine.grants))
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
      .. segments(target.kind, target.schema or "", items.signature(target.name, target.arguments), target.column)
    table.insert(
      result,
      items.leaf(id, object_name(target), "grant", items.inherit(extra, { kind = "grant", record = row }))
    )
  end
  return result
end

return M
