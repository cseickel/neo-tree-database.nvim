# neo-tree-database

⚠️ This is a work in progress. What you see here today is **100% unreviewed AI slop**. ⚠️
 
A neo-tree source that browses databases: connections, catalogs, schemas, tables and views, and
each relation's columns, indexes and constraints.

This is a replacemnt for the tree in vim-dadbod-ui. I use it along with vim-dadbod, which manages the actual db connections and executes queries.

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

## Keys

| Key                    | Does                                            |
|------------------------|-------------------------------------------------|
| `<cr>`, `l`, `<space>` | Expand or collapse                              |
| `R`                    | Refresh the current node                        |
| `y`                    | Copy the sql name of the thing under the cursor |
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

`i`, `d` and `c` open a window with the sql command for that action but does
not run it. From there `y` copies it, `o` opens it in a buffer with the
connection set, and `q` closes it.

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

- `init.lua` — the source: what expands, what fetches, the default config
- `commands.lua` — what the keys do
- `components.lua` — the icon and the detail text on each line
- `items.lua` — turning a fetched catalog into nodes, and every node id
- `connections.lua` — reading the connection list
- `client.lua` — running a client, decoding json
- `cache.lua` — what has already been asked
- `ddl.lua` — the create, drop and change statements
- `popup.lua` — the window a statement is shown in
- `scratch.lua` — the default `open_scratch`
- `quote.lua` — putting a name into sql safely
- `url.lua` — reading a url, and naming a sibling database
- `schemes/` — one module per database
