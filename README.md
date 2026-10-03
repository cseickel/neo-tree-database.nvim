# neo-tree-database

⚠️ This is a work in progress. What you see here today is **100% unreviewed AI slop**. ⚠️

A neo-tree source that browses databases: connections, catalogs, schemas, tables and views, each
relation's columns, indexes and constraints, sequences, functions, roles, and the grants on all of
them.

This is a replacement for the tree in vim-dadbod-ui. I use it along with vim-dadbod, which manages the actual db connections and executes queries.

## Installing

```lua
{
  "nvim-neo-tree/neo-tree.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "path/to/neo-tree-database" },
  config = function()
    require("neo-tree").setup({
      sources = { "filesystem", "neo-tree-database" },
    })
  end,
}
```

Open it with `:Neotree database`.

## Connections

Connections are read from `connections.json` under `g:db_ui_save_location`, which defaults to
`~/.local/share/db_ui`, and from `g:dbs`. That is the file vim-dadbod-ui uses, so a config that
already names its databases needs nothing new. Nothing here writes to either, and a connection is
added by editing the file.

```json
[
  { "name": "warehouse", "url": "postgres://chris@localhost:5432/warehouse" },
  { "name": "scratch", "url": "duckdb:/home/chris/scratch.duckdb" }
]
```

A postgres connection lists every database on its server, each reached by its own url, so one entry
covers the whole server. A duckdb connection lists the catalogs its own process can see, which is
the file the url names.

## Functions

A schema lists its functions in a folder per kind: Functions, Procedures and Aggregates in
postgres, Macros and Table Macros in duckdb. Each function is listed once by its name. A name with
several overloads shows how many it has and opens onto `overload 1` to `overload N`, numbered in
the order the catalog lists them, each showing how many arguments it takes.

A function, or one overload, opens onto:

- **Args**: the arguments a call passes, each with its type and default. An INOUT or VARIADIC
  argument is marked as such, and one declared without a name is numbered the way the function's
  body refers to it, such as `$1`.
- **return**: what it returns, such as `integer`, `SETOF text` or `TABLE`. Where it returns a
  table or a composite type, the row opens onto the columns. OUT arguments and the columns of a
  RETURNS TABLE are listed here, and an OUT argument declared without a name is `column1`, as
  postgres names it.
- **Grants**: who was granted what on it.

A function with none of those is a leaf. A procedure has no return row unless it has OUT
arguments. A duckdb macro has only its Args, because duckdb keeps neither a return type nor a
definition for it, and a macro parameter declared without a type shows none.

`i` on a function shows its definition, and on a name with several overloads the definition of
every overload. `d` on that name drops every overload in one statement, and `c` renames each of
them. duckdb drops every overload of a macro at once, so `d` on one overload of a macro is refused,
and so is `c` on any macro.

`y` copies `schema.name(argument types)` on a function, and `schema.name` on a name with several
overloads.

## Roles and grants

A postgres connection has a Roles folder beside its databases. Each role opens onto:

- **Member of**: the roles it is a member of.
- **Members**: the roles that are members of it.
- **Grants**: one entry per database the role holds anything in, listing every object the role was
  granted something on there. Opening Grants reads every database's catalog at once, the same
  catalog each database node shows. A database that could not be read stays listed, and opening it
  shows why.

A role under Member of or Members opens the same way, so a chain of memberships can be followed in
place. The roles postgres predefines (`pg_*`) are left out of the list. PUBLIC is listed after the
roles, with only its grants.

The database, each schema, table, view, sequence and function has a Grants folder listing who was
granted what on it. A table's Grants folder also lists grants on its columns, named like
`bob (email)`, and under a role the same grant is named `public.orders.email`. An object that was
never granted on shows its owner holding every privilege, which is what postgres gives an owner by
default.

Under a role, a grant on a function is named without its argument types, as `public.calc`. Where
the name has several overloads, a role holding the same privileges on every overload gets one row,
and `i` on that row writes a GRANT naming every overload. Otherwise the role gets one row per
overload it holds anything on, numbered as the tree numbers them, as `public.calc (2)`.

Only direct grants are shown. What a role can reach through another role is found by opening its
Member of folder. Grants on objects the tree does not list are not shown, such as a partition, an
object an extension created, or anything in `pg_catalog`.

duckdb has no roles or grants.

### Privilege columns

A grant row shows its privileges in columns to the right of its name. Each column shows every
privilege it lists that the row's kind of object can have: held ones in
`NeoTreeDatabasePrivilege`, the rest in `NeoTreeDatabasePrivilegeNotHeld`. `i` on a grant shows
the full GRANT, including privileges no column lists.

```
alice › Grants › app
├─ app                 CREATE  CONNECT TEMP
├─ public              CREATE  USAGE
├─ public.orders       SELECT  INSERT  UPDATE DELETE TRUNCATE
└─ public.orders.email SELECT  INSERT  UPDATE
```

As the window narrows, every column switches to a shorter form at once, so the columns still line
up:

| Window width | Privileges are written as                     | Example          |
|--------------|-----------------------------------------------|------------------|
| 75 and up    | full words, TEMPORARY as TEMP                 | `SELECT  INSERT` |
| 50 to 74     | 3 letters                                     | `SEL INS`        |
| 45 to 49     | 2 letters, TC for TRUNCATE and TG for TRIGGER | `SE IN`          |
| below 45     | psql's one-letter codes                       | `r a`            |

Each column is a `privilege` component, and `grants` lists the privileges it shows. These are the
default columns, which leave out REFERENCES, TRIGGER and MAINTAIN:

```lua
database = {
  renderers = {
    grant = {
      { "indent" },
      { "icon" },
      {
        "container",
        content = {
          { "name", zindex = 10 },
          { "privilege", grants = { "SELECT", "CREATE", "EXECUTE" }, zindex = 10, align = "right" },
          { "privilege", grants = { "INSERT", "USAGE", "CONNECT" }, zindex = 10, align = "right" },
          { "privilege", grants = { "UPDATE", "TEMPORARY" }, zindex = 10, align = "right" },
          { "privilege", grants = { "DELETE" }, zindex = 10, align = "right" },
          { "privilege", grants = { "TRUNCATE" }, zindex = 10, align = "right" },
        },
      },
    },
  },
},
```

`levels` on a column sets the window widths where it switches form. The default is
`{ full = 75, three = 50, two = 45 }`, and below `two` it uses the codes. Those numbers are worked
out for the default columns, so columns of your own need numbers of their own. Give every column the
same `levels`, or they will switch form at different widths and stop lining up.

Each column is as wide as its longest privilege. No kind of object can have two of the privileges
one default column lists. When a column of your own does match more than one, it shows all of
them and shortens them further until they fit, as in `SE US` in a column of full words.

A privilege held with grant option is drawn in `NeoTreeDatabasePrivilegeGrantable`. By default
that group is a copy of `NeoTreeDatabasePrivilege` with an underline, made again after every
colorscheme loads. Set `grant_option = "asterisk"` on a column to mark it with a `*`
after the privilege instead, the way psql does.

## Highlights

| Group                               | Default                                |
|-------------------------------------|----------------------------------------|
| `NeoTreeDatabasePrivilege`          | links to `Keyword`                     |
| `NeoTreeDatabasePrivilegeNotHeld`   | links to `NeoTreeDimText`              |
| `NeoTreeDatabasePrivilegeGrantable` | `NeoTreeDatabasePrivilege`, underlined |

## Keys

| Key                    | Does                                            |
|------------------------|-------------------------------------------------|
| `<cr>`, `l`, `<space>` | Expand or collapse                              |
| `R`                    | Refresh the current node                        |
| `y`                    | Copy the sql name of the thing under the cursor |
| `K`                    | Describe a table, view or column, with comments |
| `i`                    | Show the CREATE statement for this object       |
| `d`                    | Show the DROP statement for this object         |
| `c`                    | Show the ALTER statement for this object        |
| `s`                    | Open `select * from <relation>` in a buffer     |
| `C`, `z`               | Close the node, close every node                |
| `q`, `<esc>`, `?`, `e` | Close the window, cancel, help, toggle width    |
| `<`, `>`               | Previous and next neo-tree source               |

Neo-tree binds the same keys for every source, and the ones that create,
rename, delete or move files are turned off here, because a database node has
no path for them to act on.

`i`, `d` and `c` open a window with the sql command for that action but do
not run it. From there `y` copies it, `o` opens it in a buffer with the
connection set, and `q` closes it. On a grant, `i` shows the GRANT and `d` the
REVOKE. On a role, `i` shows the CREATE ROLE with its attributes.

`K` needs [db-query.nvim](https://github.com/cseickel/db-query.nvim) and shows its description of
the object in the same window, where `y` copies it and `q` closes it. db-query reads a database's
catalog the first time it is asked, so the first `K` in a database starts that read. Press `K`
again once it finishes.

The tree buffer's `b:db` and `b:db_name` follow the node under the cursor, so vim-dadbod and
db-query commands run from the tree, such as `:DBRefreshCatalog`, reach that node's database.

## Configuration

```lua
require("neo-tree").setup({
  sources = { "filesystem", "neo-tree-database" },
  database = {
    connections = function()
      return { { name = "warehouse", url = os.getenv("WAREHOUSE_URL") } }
    end,
    open_scratch = function(spec)
      vim.cmd("botright new")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, spec.lines)
      vim.bo.filetype = "sql"
      vim.b.db = spec.url
    end,
  },
})
```

`connections` can be a list or a function returning a list. These lists must
contain tables with a name and an url.

`open_scratch` decides how to open an sql buffer when you press `o` in the statement window or `s` on a table.
It receives `{ url, lines, title }`. The default opens a split, sets `filetype=sql` and sets the connection via `b:db`,
which is where vim-dadbod and vim-dadbod-completion both look.

## Databases

**duckdb** is complete and its queries are verified against a real duckdb, by `fixture/duckdb.sql`.
It reads the `duckdb_*()` table functions rather than `information_schema`, so it gets the create
statement of every table and view, the sql of every index, and constraint names, and it avoids the
`.tables` dot command whose format changed in 1.5.1. It opens files read-only, leaving them
unlocked for your own duckdb session.

**postgres** is complete. It reads `pg_catalog`, uses `pg_get_viewdef`, `pg_get_indexdef` and
`pg_get_constraintdef` for definitions, and rebuilds `CREATE TABLE` from the catalog.

**sqlite and mysql** are not implemented yet. Adding one is a module under `lua/neo-tree-database/schemes/`
and a line in that directory's `init.lua`.

I have no immediate plans to support other databases.

## Layout

| File              | Holds                                                     |
|-------------------|-----------------------------------------------------------|
| `init.lua`        | the source: what expands and what fetches                 |
| `config.lua`      | the default config: renderers and keys                    |
| `commands.lua`    | what the keys do                                          |
| `components.lua`  | the icon and the detail text on each line                 |
| `privileges.lua`  | the privilege columns on a grant row                      |
| `highlights.lua`  | the highlight groups this source defines                  |
| `focus.lua`       | keeping `b:db` on the node under the cursor               |
| `items.lua`       | node ids, and the connections                             |
| `objects.lua`     | turning a fetched catalog into nodes                      |
| `routines.lua`    | each function's name, overloads, arguments and return     |
| `roles.lua`       | the Roles folder and each role                            |
| `grants.lua`      | the Grants folders, under an object and under a role      |
| `connections.lua` | reading the connection list                               |
| `client.lua`      | running a client, decoding json                           |
| `cache.lua`       | what has already been asked                               |
| `ddl/`            | the create, drop and change statements                    |
| `popup.lua`       | the window a statement or a description is shown in       |
| `scratch.lua`     | the default `open_scratch`                                |
| `quote.lua`       | putting a name into sql safely                            |
| `url.lua`         | reading a url, and naming a sibling database              |
| `schemes/`        | one module per database                                   |
