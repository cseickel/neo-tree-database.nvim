--- Builds the parts every node shares: its id, its shape, and the root above the
--- connections.

local M = {}

---@class dbtree.Item
---@field id string
---@field name string
---@field type string
---@field extra table
---@field loaded boolean|nil
---@field children dbtree.Item[]|nil
---@field _is_expanded boolean|nil

--- Returns `name` with `%`, `/` and `@` percent-encoded, so it can be one segment
--- of a node id. Ids separate segments with `/` and start a heading or
--- placeholder segment with `@`.
---@param name string
---@return string
function M.segment(name)
  return (name:gsub("[%%/@]", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

--- Returns a container whose only child is a loading placeholder. neo-tree draws
--- an expander for it until the real children replace the placeholder.
---@param id string
---@param name string
---@param node_type string
---@param extra table
---@return dbtree.Item
function M.container(id, name, node_type, extra)
  return {
    id = id,
    name = name,
    type = node_type,
    loaded = false,
    extra = extra,
    children = {
      {
        id = id .. "/@loading",
        name = "..loading",
        type = "loading",
        extra = { kind = "loading" },
      },
    },
  }
end

---@param id string
---@param name string
---@param node_type string
---@param extra table
---@return dbtree.Item
function M.leaf(id, name, node_type, extra)
  return { id = id, name = name, type = node_type, extra = extra }
end

--- Returns the connection, catalog, url, schema and relation of `parent`, the
--- parent node's `extra`, with `fields` added.
---@param parent table
---@param fields table
---@return table
function M.inherit(parent, fields)
  return vim.tbl_extend("force", {
    connection = parent.connection,
    catalog = parent.catalog,
    url = parent.url,
    schema = parent.schema,
    relation = parent.relation,
  }, fields)
end

--- Sets `name_width` on each of `items` to the width of the widest of their
--- names, so the text drawn after each name can start in the same column.
---@param items dbtree.Item[]
---@return dbtree.Item[]
function M.align_names(items)
  local widest = 0
  for _, item in ipairs(items) do
    widest = math.max(widest, vim.api.nvim_strwidth(item.name))
  end
  for _, item in ipairs(items) do
    item.extra.name_width = widest
  end
  return items
end

--- Returns `routines` grouped by kind and name, with the groups and the routines
--- in each group in the order given.
---@param routines dbtree.Routine[]
---@return dbtree.Routine[][]
function M.group_overloads(routines)
  local groups, group_by_key = {}, {}
  for _, routine in ipairs(routines) do
    local key = routine.kind .. "/" .. routine.name
    local group = group_by_key[key]
    if not group then
      group = {}
      group_by_key[key] = group
      table.insert(groups, group)
    end
    table.insert(group, routine)
  end
  return groups
end

---@param parent_id string
---@param text string
---@return dbtree.Item[]
function M.message(parent_id, text)
  return { M.leaf(parent_id .. "/@message", text, "message", { kind = "message" }) }
end

M.ROOT = "db:"

--- Returns the root node holding `children`. neo-tree hides the first item it is
--- given as the tree's root, so the connections need a parent above them.
---@param children table[]
---@return dbtree.Item[]
function M.root(children)
  return {
    {
      id = M.ROOT,
      name = "Databases",
      type = "root",
      loaded = true,
      extra = { kind = "root" },
      children = children,
      _is_expanded = true,
    },
  }
end

---@param connection dbtree.Connection
---@return string
function M.connection_id(connection)
  return M.ROOT .. "/" .. M.segment(connection.name)
end

--- Returns the id of the node for `catalog`, which is also the key its result is
--- cached under.
---@param connection dbtree.Connection
---@param catalog string
---@return string
function M.catalog_id(connection, catalog)
  return M.connection_id(connection) .. "/" .. M.segment(catalog)
end

return M
