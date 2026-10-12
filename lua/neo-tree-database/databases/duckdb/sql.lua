--- Builds the sql that lists a duckdb connection's catalogs, and the sql that
--- reads everything one catalog holds.

local M = {}

--- Returns the sql that lists the connection's catalogs, each with its size when
--- `read_sizes` is set. duckdb reports no blocks for an in-memory database.
---@param read_sizes boolean
---@return string
function M.catalogs(read_sizes)
  local size = read_sizes and "case when s.total_blocks > 0 then s.block_size * s.total_blocks end" or "null"
  return [[
select json_object('catalogs', coalesce(
  (select to_json(list(json_object(
     'name', d.database_name,
     'size', ]] .. size .. "\n" .. [[   ) order by d.database_name))
   from duckdb_databases() d
   left join pragma_database_size() s on s.database_name = d.database_name
   where not d.internal),
  '[]'::json))
]]
end

--- Returns the sql that reads everything the catalog `@catalog` holds, with
--- each table's row estimate when `read_sizes` is set. duckdb lists each NOT
--- NULL as a constraint, which the column rows already show. A macro gets no
--- definition, because duckdb_functions() leaves out parameter defaults.
---@param read_sizes boolean
---@return string
function M.introspect(read_sizes)
  local rows = read_sizes and "estimated_size" or "null"
  return [[
select json_object('schemas', coalesce((
  select to_json(list(json_object(
    'name', s.schema_name,
    'relations', coalesce((
      select to_json(list(json_object(
        'name', r.name,
        'kind', r.kind,
        'rows', r.rows,
        'definition', r.sql,
        'columns', coalesce((
          select to_json(list(json_object(
            'name', c.column_name,
            'type', c.data_type,
            'nullable', c.is_nullable,
            'default', c.column_default,
            'position', c.column_index
          ) order by c.column_index))
          from duckdb_columns() c
          where c.database_name = r.database_name
            and c.schema_name = r.schema_name
            and c.table_name = r.name
        ), '[]'::json),
        'indexes', coalesce((
          select to_json(list(json_object(
            'name', i.index_name,
            'unique', i.is_unique,
            'columns', to_json(string_split(trim(i.expressions, '[]'), ', ')),
            'definition', i.sql
          ) order by i.index_name))
          from duckdb_indexes() i
          where i.database_name = r.database_name
            and i.schema_name = r.schema_name
            and i.table_name = r.name
        ), '[]'::json),
        'constraints', coalesce((
          select to_json(list(json_object(
            'name', k.constraint_name,
            'type', k.constraint_type,
            'definition', k.constraint_text
          ) order by k.constraint_name))
          from duckdb_constraints() k
          where k.database_name = r.database_name
            and k.schema_name = r.schema_name
            and k.table_name = r.name
            and k.constraint_type <> 'NOT NULL'
        ), '[]'::json)
      ) order by r.name))
      from (
        select database_name, schema_name, table_name as name, 'table' as kind,
               ]] .. rows .. [[ as rows, sql
        from duckdb_tables()
        union all
        select database_name, schema_name, view_name as name, 'view' as kind,
               null as rows, sql
        from duckdb_views() where not internal
      ) r
      where r.database_name = s.database_name and r.schema_name = s.schema_name
    ), '[]'::json),
    'sequences', coalesce((
      select to_json(list(json_object(
        'name', q.sequence_name,
        'definition', q.sql
      ) order by q.sequence_name))
      from duckdb_sequences() q
      where q.database_name = s.database_name and q.schema_name = s.schema_name
    ), '[]'::json),
    'functions', coalesce((
      select to_json(list(json_object(
        'name', f.function_name,
        'kind', f.function_type,
        'args', to_json(list_transform(
          list_zip(f.parameters, f.parameter_types),
          lambda p: json_object('name', p[1], 'type', p[2], 'mode', 'in')
        ))
      ) order by f.function_name, len(f.parameters), f.parameters::varchar))
      from duckdb_functions() f
      where not f.internal
        and f.database_name = s.database_name and f.schema_name = s.schema_name
    ), '[]'::json)
  ) order by s.schema_name))
  from duckdb_schemas() s
  where s.database_name = @catalog
), '[]'::json))
]]
end

return M
