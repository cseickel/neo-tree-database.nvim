# Fixtures

`duckdb.sql` builds a small database in memory and then runs both queries
`schemes/duckdb.lua` sends, with `@catalog` already filled in as `'memory'`. The
sql in it is otherwise character for character what the module sends.

Run it:

```
duckdb -noheader -list -f fixture/duckdb.sql
```

Two json documents come back, one per query. The second should hold two schemas,
`analytics` and `main`, with `trades` carrying four columns, one index and three
constraints, and `large_trades` carrying its `CREATE VIEW` text.

This is how a change to the duckdb queries gets checked without a server, and it
is the only scheme that can be checked this way, because duckdb is the only one
of these clients that needs no database to talk to.
