# neo-tree-database

⚠️ This is a work in progress. What you see here today is **100% unreviewed AI slop**. ⚠️

A neo-tree source that browses postgres, mysql, mariadb and duckdb databases: connections,
catalogs, schemas, tables and views, each relation's columns, indexes and constraints, sequences,
functions, roles, and the grants on all of them.

This is a replacement for the tree in vim-dadbod-ui. It runs its queries through
[db-query.nvim](https://github.com/cseickel/db-query.nvim), and the sql buffers it opens work with
vim-dadbod and db-query alike.

## Installing

```lua
{
  "nvim-neo-tree/neo-tree.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "cseickel/db-query.nvim",
    "path/to/neo-tree-database",
  },
  config = function()
    require("neo-tree").setup({
      sources = { "filesystem", "neo-tree-database" },
    })
  end,
}
```

Open it with `:Neotree database`.

The tree needs db-query.nvim to load anything, because every query it runs goes through db-query's
`read`. Without it, expanding a node shows that db-query is not installed. db-query runs each query
read-only, with the client for the url's database, `psql`, `duckdb`, `mysql` or `mariadb`, which
has to be on your `PATH`. A query is killed after db-query's `catalog.timeout` setting, which is 5
minutes by default.

## Connections

Connections are read from `connections.json` under `g:db_ui_save_location`, which defaults to
`~/.local/share/db_ui`, and from `g:dbs`. That is the file vim-dadbod-ui uses, so a config that
already names its databases needs nothing new. Nothing here writes to either, and a connection is
added by editing the file.

```json
[
  { "name": "warehouse", "url": "postgres://chris@localhost:5432/warehouse" },
  { "name": "shop", "url": "mysql://chris@localhost/shop" },
  { "name": "scratch", "url": "duckdb:/home/chris/scratch.duckdb" }
]
```

A postgres connection lists every database on its server, each reached by its own url, so one entry
covers the whole server. A mysql or mariadb connection also lists every database on its server, and
reads each one through the connection's own url. A duckdb connection lists the catalogs its own
process can see, which is the file the url names.

mysql has no schema level, so a mysql or mariadb database opens straight onto Tables, Views,
Functions, Procedures and Grants, each shown only when it holds something. A mariadb database also
has a Sequences folder when it holds sequences.

An index opens onto its key parts in key order, each named as the database writes it, such as
`lower(email)`. `i`, `d` and `c` on a key part show the index's statements.

## Saved results

The tree reads two kinds of result from a database: a connection's list of databases, and the
contents of one database. It keeps each result in memory and saves it to disk, so expanding a node
whose result is saved shows it at once, even in a new Neovim session. When the tree cannot build a
node's children from a saved result, it deletes that result and reads it again from the database.
For a connection's list of databases, that deletes every result saved for the connection.

With `auto_refresh` on, which is the default, the tree shows a saved result and then reads it again
in the background. If the result changed, the node's children are drawn again, and the nodes that
were open under it stay open. If the read fails, the saved result stays and a warning is logged.
With `auto_refresh` off, a saved result is used until you press `R`.

`R` reads the node's results again while the old ones stay shown. On a node inside a database,
that is the database's result. On a connection, it is the connection's list of databases and every
database result the tree holds in memory for it, so the databases open under the connection stay
open and show current data. Each result that changed replaces the old one in memory and on disk,
and the node's children are drawn again with the open nodes kept open. When a read fails, the old
result stays and a warning is logged. A node with no result in memory, such as one that showed an
error, is read the way it is on its first expand.

While a query runs for a node, on its first expand, in the background or after `R`, a spinner
takes the place of the node's icon.

The results are saved under `stdpath("cache")/neo-tree-database/`, which is
`~/.cache/nvim/neo-tree-database/` by default, in one directory per connection. The directory is
named by a hash of the format number of the saved results, the connection's url without its
password, and its `features`. Changing any of them starts an empty directory, so results saved by a
version of the tree with an older format number are never read. The files list every table and
column, so each directory is readable only by you: the directory has mode 0700 and its files 0600.

## Rows and sizes

A table or materialized view shows its size on disk and its row estimate in two columns at the
right edge of the window, size first. A database, a schema, an index and a sequence show their size
alone, with a blank rows cell so that every size lines up. A view stores nothing and shows neither.

```
app                                                    1.2 GB
└─ public                                              1.1 GB
   ├─ Tables
   │  ├─ orders                                        840 MB ~1.2M rows
   │  │  └─ Indexes
   │  │     └─ orders_pkey   unique                     26 MB
   │  │        └─ id
   │  └─ customers                                      12 MB  ~48K rows
   └─ Sequences
      └─ order_ids                                     8.0 KB
```

The row estimate is the database's own, so it is marked `~` and can be far from the true count. A
table of one row reads `~1 row`. Rows are written in K, M, B and T, and sizes in B, KB, MB, GB and
TB, where a KB is 1024 bytes. Both carry one decimal below 10.

In postgres a table's size includes its indexes and toast, a partitioned table's size is the sum
of its partitions, and a schema's size is everything its tables, materialized views and sequences
store. A database's size comes from `pg_database_size`, which is blank for a database the
connecting role cannot connect to. The row estimate is blank until the table has been vacuumed or
analyzed.

Measuring a size in postgres takes a lock on the relation, so a table under an exclusive lock,
such as one being rewritten by `VACUUM FULL`, would hold up the whole catalog. The catalog query
runs with a `lock_timeout` of 5 seconds. When that runs out, the catalog is read again with sizes
estimated from the page counts in `pg_class`, which takes no locks. An estimated size is marked
`~`, as in `~840 MB`. Those page counts are only as fresh as the last vacuum or analyze, so a table
never vacuumed reads `~0 B`. The estimates stay until the node is refreshed with `R`, which tries
the exact sizes again.

mysql and mariadb take a table's size, its data plus its indexes, and its row estimate from
`information_schema.tables`, and every size is marked `~`, as in `~64 KB`. A database and an index
show no size. Reading those two columns makes the server open every table, which on one server took
4 s against 0.38 s to list the tables without them. To skip them on a slow server, set `read_sizes`
to `false` in `features`, described under Configuration.

duckdb reports a row estimate for each table and the size of the database file, and no size for
a schema, table, index or sequence. A database held in memory has no file and shows no size.

The columns are the `size` and `rows` components. Each cell is coloured by its unit, so the big
ones stand out: a size in B or KB is dimmed by half, one in MB is dimmed a little, and one in GB or
TB is bold. A row estimate under 1M is dimmed by half, one in M is dimmed a little, and one in B or
T is bold. The groups are listed under Highlights.

The text after a name is the `detail` component. The renderer's `align` sets where it goes.

A column's type, and an argument's or a returned column's type, follow the name as in a CREATE
TABLE. Every type among siblings starts 2 cells after the widest sibling name. A type too long for
the window runs to its edge and is cut there. These renderers give `{ "detail" }` with no `align`.

```
id          integer not null
email       text
created_at  timestamptz not null
```

Every other detail goes in a column of its own just left of the size column, 21 cells wide by
default. That is a constraint's type, a count, a role's attributes, a connection's scheme, a
function's return, and an index's `unique`. These renderers give `{ "detail", align = "right" }`.
The text starts at the left of the column, and text wider than the column is cut and ends in `…`.
A node with no text gets a blank cell, so the column lines up. To change the width, set it on the
component, as `{ "detail", align = "right", width = 30 }`. A count, which is a schema's
`2 relations` or `empty`, a function's `2 overloads` or an overload's `1 arg`, is shown only while
its node is collapsed.

The detail shows a type whose name is long by its short alias, in lowercase. The name is
matched in any case, and a precision, a length or a trailing `[]` is kept, so
`timestamp(3) with time zone` is shown as `timestamptz(3)`. A function's `SETOF` return is
shortened the same way, as `SETOF timestamptz`. `i` shows the full names.

| Type                          | Shown as      |
|-------------------------------|---------------|
| `timestamp with time zone`    | `timestamptz` |
| `timestamp without time zone` | `timestamp`   |
| `time with time zone`         | `timetz`      |
| `time without time zone`      | `time`        |
| `character varying(n)`        | `varchar(n)`  |
| `character(n)`                | `char(n)`     |
| `double precision`            | `float8`      |
| `bit varying(n)`              | `varbit(n)`   |

`rows` is dropped from every line when the window is narrower than 50 columns, and `size` and the
right-aligned `detail` when it is narrower than 40. The name has the same `zindex` as these
columns, so in a window too narrow for all of them, the columns keep their width and the name is
cut.

## Functions

A schema, or a mysql database, lists its functions in a folder per kind: Functions, Procedures and
Aggregates in postgres, Functions and Procedures in mysql and mariadb, Macros and Table Macros in
duckdb. Each function is listed once by its name. A name with several overloads opens onto
`overload 1` to `overload N`, numbered in the order the catalog lists them. While collapsed, the
name shows how many overloads it has, and each overload shows how many arguments it takes.

A function, or one overload, opens onto:

- **Args**: the arguments a call passes, each with its type and default. An INOUT or VARIADIC
  argument is marked as such, and one declared without a name is numbered the way the function's
  body refers to it, such as `$1`.
- **return**: what it returns, such as `integer`, `SETOF text` or `TABLE`. Where it returns a
  table or a composite type, the row opens onto the columns. OUT arguments and the columns of a
  RETURNS TABLE are listed here, and an OUT argument declared without a name is `column1`, as
  postgres names it.
- **Grants**: who was granted what on it. mysql and mariadb functions and procedures have no
  Grants folder.

A function with none of those is a leaf. A procedure has no return row unless it has OUT
arguments. A duckdb macro has only its Args, because duckdb keeps neither a return type nor a
definition for it, and a macro parameter declared without a type shows none.

`i` on a function shows its definition, and on a name with several overloads the definition of
every overload. `d` on that name drops every overload in one statement, and `c` renames each of
them. duckdb drops every overload of a macro at once, so `d` on one overload of a macro is refused,
and so is `c` on any macro. mysql cannot rename a function or a procedure, so `c` on one is
refused.

mysql shows a routine's body only to a user who defined it or holds privileges to read it. For any
other user, `i` on the routine says it has no definition.

`y` copies `schema.name(argument types)` on a function, and `schema.name` on a name with several
overloads.

## Roles and grants

A postgres, mysql or mariadb connection has a Roles folder beside its databases. Each role opens
onto:

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
`bob (email)`, and under a role the same grant is named `public.orders.email`. In postgres, an
object that was never granted on shows its owner holding every privilege, which is what postgres
gives an owner by default.

Under a role, a grant on a function is named without its argument types, as `public.calc`. Where
the name has several overloads, a role holding the same privileges on every overload gets one row,
and `i` on that row writes a GRANT naming every overload. Otherwise the role gets one row per
overload it holds anything on, numbered as the tree numbers them, as `public.calc (2)`.

Only direct grants are shown. What a role can reach through another role is found by opening its
Member of folder. Grants on objects the tree does not list are not shown, such as a partition, an
object an extension created, or anything in `pg_catalog`.

duckdb has no roles or grants. Setting `read_grants` to `false` in `features`, described under
Configuration, removes every Grants folder and keeps the roles.

### mysql and mariadb

The Roles folder lists every account, named as `'app'@'%'`. A mysql role is an account, and a
mariadb role is named with an empty host, as `'auditor'@''`. Reading accounts takes SELECT on the
`mysql` schema, so a user without it gets no Roles folder.

Grants come from `information_schema`, which lists only the grants the connecting user may see:
their own, or everyone's when they can read the `mysql` schema. A database's Grants folder lists
grants on the whole database, which a GRANT writes as `shop.*`, and each table and view lists its
own and those on its columns. Grants on functions and procedures are not shown.

`i` on an account shows its CREATE USER, and on a mariadb role its CREATE ROLE.

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
default columns, which leave out REFERENCES, TRIGGER and MAINTAIN. The name has the same `zindex`
as the columns, so in a window too narrow for both, the columns keep their width and the name is
cut.

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

`grants` takes only the privileges psql has a letter for: SELECT, INSERT, UPDATE, DELETE,
TRUNCATE, REFERENCES, TRIGGER, MAINTAIN, CREATE, CONNECT, TEMPORARY, EXECUTE and USAGE. A mysql
privilege outside that list, such as DROP or ALTER, shows only in the GRANT that `i` writes.

`levels` on a column sets the window widths where it switches form. The default is
`{ full = 75, three = 50, two = 45 }`, and below `two` it uses the codes. Those numbers are worked
out for the default columns, so columns of your own need numbers of their own. Give every column the
same `levels`, or they will switch form at different widths and stop lining up.

Each column is as wide as its longest privilege. When a row's object can have more than one of the
privileges a column lists, the column shows all of them and shortens them further until they fit.
In postgres no kind of object can have two of the privileges one default column lists. In mysql a
table can have both SELECT and CREATE, which the first default column shows as `SEL CRE` in a
window of full words, and a database can also have EXECUTE, which it shows as `r C X`.

A privilege held with grant option is drawn in `NeoTreeDatabasePrivilegeGrantable`, which is
underlined by default. Set `grant_option = "asterisk"` on a column to mark it with a `*` after the
privilege instead, the way psql does.

## Highlights

| Group                               | Default                                | Draws                               |
|-------------------------------------|----------------------------------------|-------------------------------------|
| `NeoTreeDatabaseDetail`             | links to `Comment`                     | the text after a name               |
| `NeoTreeDatabaseType`               | links to `Type`                        | a column, argument or return type   |
| `NeoTreeDatabasePrivilege`          | links to `Keyword`                     | a held privilege                    |
| `NeoTreeDatabasePrivilegeNotHeld`   | links to `NeoTreeDimText`              | a privilege not held                |
| `NeoTreeDatabasePrivilegeGrantable` | `NeoTreeDatabasePrivilege`, underlined | one with grant option               |
| `NeoTreeDatabaseSize`               | links to `Number`                      | nothing itself                      |
| `NeoTreeDatabaseSizeKB`             | `NeoTreeDatabaseSize`, dimmed 50%      | a size in B or KB                   |
| `NeoTreeDatabaseSizeMB`             | `NeoTreeDatabaseSize`, dimmed 10%      | a size in MB                        |
| `NeoTreeDatabaseSizeGB`             | `NeoTreeDatabaseSize`, bold            | a size in GB or TB                  |
| `NeoTreeDatabaseRows`               | links to `String`                      | nothing itself                      |
| `NeoTreeDatabaseRowsK`              | `NeoTreeDatabaseRows`, dimmed 50%      | rows under 1M                       |
| `NeoTreeDatabaseRowsM`              | `NeoTreeDatabaseRows`, dimmed 10%      | rows in M                           |
| `NeoTreeDatabaseRowsB`              | `NeoTreeDatabaseRows`, bold            | rows in B or T                      |

Every group is defined with `default`, so one you set yourself is kept. The underlined, dimmed and
bold groups are copies of their base, taken when the source sets up and again after every
colorscheme loads, so set the base before then, such as in your colorscheme, for them to pick it
up. A dimmed group takes its base's foreground moved the given share of the way into the tree's
background, which is `NeoTreeNormal`'s or else `Normal`'s. When the base has no foreground colour
or the background has none, there is nothing to blend: the 50% groups link to `NeoTreeDimText`,
and the 10% groups link to their base.

## Keys

| Key                    | Does                                            |
|------------------------|-------------------------------------------------|
| `<cr>`, `l`, `<space>` | Expand or collapse                              |
| `R`                    | Read the current node again from the database   |
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

`R` is described under Saved results.

`i`, `d` and `c` open a window with the sql command for that action but do
not run it. From there `y` copies it, `o` opens it in a buffer with the
connection set, and `q` closes it. On a grant, `i` shows the GRANT and `d` the
REVOKE. On a role, `i` shows the CREATE ROLE with its attributes.

`K` shows db-query's description of the object in the same window, where `y` copies it and `q`
closes it. db-query reads a database's catalog the first time it is asked, so the first `K` in a
database starts that read. Press `K` again once it finishes.

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
    features = function(connection)
      return {
        read_grants = connection.scheme ~= "mysql",
        read_sizes = not connection.name:match("SRSE"),
      }
    end,
    auto_refresh = true,
    open_scratch = function(spec)
      vim.cmd("botright new")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, spec.lines)
      vim.bo.filetype = "sql"
      vim.b.db = spec.url
    end,
  },
})
```

`connections` is a list, or a function that returns a list, of tables that each have a `name` and
a `url`.

`features` sets what the tree reads from each connection. Both settings default to `true`.

| Setting       | When `false`                                                                     |
|---------------|----------------------------------------------------------------------------------|
| `read_sizes`  | The tree reads no sizes or row estimates, so the size and rows columns are blank |
| `read_grants` | The tree skips the grant queries, so no object or role has a Grants folder       |

`features` is either a table, which applies to every connection, or a function. The function is
called for each connection with `{ name, url, scheme }`, where `scheme` is the url's scheme in
lowercase, such as `postgres`, `mariadb` or `duckdb`. It returns a table, or nil for the defaults.
The table is merged over the defaults, so it only needs the settings it changes. When the function
raises an error or returns something other than a table, the tree shows that error in place of the
connections.

`auto_refresh` defaults to `true`, which reads a result shown from disk again in the background.
Set it to `false` to read a saved result again only when you press `R`. Saved results describes
both.

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

**mysql and mariadb** read `information_schema`, and the `mysql` schema for accounts. `CREATE
TABLE` and each routine's `CREATE FUNCTION` or `CREATE PROCEDURE` are rebuilt from those tables.
mariadb adds DELETE HISTORY to the privileges a table can hold.

**sqlite** is not implemented yet. I have no immediate plans to support other databases.

Adding a database is a folder under `lua/neo-tree-database/databases/` and a line in
`MODULE_BY_URL_SCHEME` in that directory's `init.lua`. The folder's `init.lua` returns the
`dbtree.Scheme` that file declares. Two of its fields are optional:

- `statements` replaces the shared statement builders whose sql the database does not accept. It
  holds `info`, `drop` and `change` tables keyed by node type, and any builder it leaves out falls
  back to the shared one.
- `privileges` lists the privileges each kind of grant target can hold, keyed by kind, such as
  `database`, `table` or `column`. The privilege columns read it. A database without it has no
  grants.

## Layout

The code is under `lua/neo-tree-database/`, in one folder per job.

| Path                  | Holds                                                                   |
|-----------------------|-------------------------------------------------------------------------|
| `init.lua`            | the neo-tree source, which builds the tree from the connections         |
| `config.lua`          | the default config: renderers and keys                                  |
| `databases/`          | reading the connection list, and running each query through db-query and decoding its json |
| `databases/init.lua`  | which database handles a url, and the results every database returns   |
| `databases/<name>/`   | one database: `init.lua` its requests, `sql.lua` the catalog queries, `ddl.lua` the CREATE statements, `statements.lua` the builders it replaces |
| `nodes/`              | one file per kind of node, building its children from the fetched json  |
| `nodes/init.lua`      | which file builds each node's children, and reading their results first |
| `nodes/results.lua`   | which results a node is built from, kept in memory and on disk          |
| `state/`              | the results in memory and on disk, the queries still running, the open nodes, `b:db` |
| `components/`         | the icon, name, detail, size, rows and privilege columns on each line   |
| `actions/`            | what the keys do                                                        |
| `popups/`             | the window a statement or a description is shown in                     |
| `popups/statements/`  | the create, drop and change statements                                  |
| `shared/`             | quoting, urls and highlight groups, which several folders use           |
