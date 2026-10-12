--- Builds the folders under a schema, one per kind of object it holds, and its
--- Grants folder.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")

local M = {}

local SCHEMA_FOLDERS = {
  { folder = "tables", label = "Tables", field = "relations", kind = "table" },
  { folder = "views", label = "Views", field = "relations", kind = "view" },
  { folder = "materialized_views", label = "Materialized Views", field = "relations", kind = "materialized_view" },
  { folder = "sequences", label = "Sequences", field = "sequences" },
  { folder = "functions", label = "Functions", field = "functions", kind = "function" },
  { folder = "procedures", label = "Procedures", field = "functions", kind = "procedure" },
  { folder = "aggregates", label = "Aggregates", field = "functions", kind = "aggregate" },
  { folder = "macros", label = "Macros", field = "functions", kind = "macro" },
  { folder = "table_macros", label = "Table Macros", field = "functions", kind = "table_macro" },
}

---@param records table[]
---@param kind string|nil
---@return table[]
local function of_kind(records, kind)
  if not kind then
    return records
  end
  return vim.tbl_filter(function(record)
    return record.kind == kind
  end, records)
end

--- Returns a folder under `node` for each kind of object in `objects`, which
--- `schema` holds. `node` is the schema's node, or the node of a database that
--- has no schemas.
---@param node dbtree.Item|NuiTree.Node
---@param objects dbtree.Objects
---@param schema string
---@return dbtree.Item[]
function M.object_folders(node, objects, schema)
  local result = {}
  for _, folder_spec in ipairs(SCHEMA_FOLDERS) do
    local records = of_kind(objects[folder_spec.field] or {}, folder_spec.kind)
    if #records > 0 then
      table.insert(
        result,
        base.container(node.id .. "/@" .. folder_spec.folder, folder_spec.label, "folder", base.inherit(node.extra, {
          kind = "folder",
          folder = folder_spec.folder,
          schema = schema,
          record = records,
        }))
      )
    end
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.folders(node)
  local parent = node.extra
  local result = M.object_folders(node, parent.record, parent.schema)
  return vim.list_extend(result, grant.folder(node, grant.rows(grant.schema_target(parent.schema), parent.record.grants)))
end

return M
