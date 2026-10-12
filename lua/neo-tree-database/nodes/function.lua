--- Builds the function nodes, their overloads, and the Args, return and Grants
--- under each function.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")

local M = {}

---@class dbtree.Labelled A field with the name that its row shows.
---@field name string
---@field field dbtree.Field

---@class dbtree.Result What a function's return row shows.
---@field text string
---@field fields dbtree.Labelled[]

local MODE_PREFIX = { inout = "INOUT ", variadic = "VARIADIC " }

--- Returns the arguments that a call to `routine` passes. An argument declared
--- without a name is labelled by its position, such as `$1`.
---@param routine dbtree.Routine
---@return dbtree.Labelled[]
function M.inputs(routine)
  local result = {}
  for position, arg in ipairs(routine.args) do
    if arg.mode == "in" or arg.mode == "inout" or arg.mode == "variadic" then
      table.insert(result, { name = (MODE_PREFIX[arg.mode] or "") .. (arg.name or ("$" .. position)), field = arg })
    end
  end
  return result
end

--- Returns the output arguments of `routine`. An argument declared without a
--- name is labelled `column1`, `column2` and so on, as postgres names the columns
--- it returns.
---@param routine dbtree.Routine
---@return dbtree.Labelled[]
local function outputs(routine)
  local result = {}
  for _, arg in ipairs(routine.args) do
    if arg.mode == "out" or arg.mode == "inout" or arg.mode == "table" then
      table.insert(result, { name = arg.name or ("column" .. (#result + 1)), field = arg })
    end
  end
  return result
end

--- Returns what the return row of `routine` shows, or nil when it declares no
--- return. Output arguments make a TABLE on a procedure, when there are several
--- of them, or when any is declared in RETURNS TABLE. A function's single OUT
--- argument makes a value of its own type, which postgres records as the return
--- type.
---@param routine dbtree.Routine
---@return dbtree.Result|nil
local function return_of(routine)
  local columns = outputs(routine)
  local returns = routine.returns
  if not returns and #columns == 0 then
    return nil
  end

  local declared_table = vim.iter(routine.args):any(function(arg)
    return arg.mode == "table"
  end)
  if #columns > 0 and (not returns or returns.type == "record" or declared_table) then
    return { text = "TABLE", fields = columns }
  end

  if #columns == 0 then
    columns = vim.tbl_map(function(column)
      return { name = column.name, field = column }
    end, returns.columns or {})
  end
  return { text = (returns.set and "SETOF " or "") .. returns.type, fields = columns }
end

---@param node dbtree.Item|NuiTree.Node
---@param id string
---@param name string
---@param routine dbtree.Routine
---@param overload integer|nil
---@return dbtree.Item
local function routine_item(node, id, name, routine, overload)
  local extra = base.inherit(node.extra, {
    kind = "routine",
    record = routine,
    overload = overload,
    target = grant.routine_target(node.extra.schema, routine, overload),
  })
  local has_children = #M.inputs(routine) > 0 or return_of(routine) ~= nil or #(routine.grants or {}) > 0
  if has_children then
    return base.container(id, name, "routine", extra)
  end
  return base.leaf(id, name, "routine", extra)
end

--- Returns the functions in a folder of one kind, one item per name.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.folder_routines(node)
  local result = {}
  for _, overloads in ipairs(base.group_overloads(node.extra.record)) do
    local name = overloads[1].name
    local id = node.id .. "/" .. base.segment(name)
    if #overloads == 1 then
      table.insert(result, routine_item(node, id, name, overloads[1]))
    else
      table.insert(
        result,
        base.container(id, name, "overloaded_routine", base.inherit(node.extra, {
          kind = "overloaded_routine",
          record = overloads,
        }))
      )
    end
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.overload_items(node)
  local result = {}
  for number, routine in ipairs(node.extra.record) do
    table.insert(result, routine_item(node, node.id .. "/" .. number, "overload " .. number, routine, number))
  end
  return result
end

--- Returns the Args folder, the return row, and the Grants folder of a function.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.routine_children(node)
  local extra = node.extra
  local routine = extra.record
  local result = {}

  local inputs = M.inputs(routine)
  if #inputs > 0 then
    table.insert(
      result,
      base.container(node.id .. "/@args", "Args", "folder", base.inherit(extra, {
        kind = "folder",
        folder = "arguments",
        record = inputs,
      }))
    )
  end

  local return_row = return_of(routine)
  if return_row then
    local id = node.id .. "/@return"
    local return_extra = base.inherit(extra, { kind = "return", record = return_row })
    local make_item = #return_row.fields > 0 and base.container or base.leaf
    table.insert(result, make_item(id, "return", "return", return_extra))
  end

  return vim.list_extend(result, grant.folder(node, grant.rows(extra.target, routine.grants)))
end

---@param node dbtree.Item|NuiTree.Node
---@param fields dbtree.Labelled[]
---@return dbtree.Item[]
local function field_items(node, fields)
  local result = {}
  for position, labelled_field in ipairs(fields) do
    table.insert(
      result,
      base.leaf(node.id .. "/" .. position, labelled_field.name, "field", base.inherit(node.extra, {
        kind = "field",
        record = labelled_field.field,
      }))
    )
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.argument_items(node)
  return field_items(node, node.extra.record)
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.return_columns(node)
  return field_items(node, node.extra.record.fields)
end

return M
