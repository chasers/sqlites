# RFC: exact SQL classification (read-only detection)

**Status: recommendation made, implementation not started.**

## Problem

Idle-stop ships a `VACUUM INTO` snapshot on *every* session because the
keyword classifier (`Sqlites.DataPlane.Sql`) is not trusted with
durability decisions — one misclassified write loses data (decided
2026-07-04). Read-heavy fleets therefore pay one S3 PUT per idle-stop
per database for sessions that changed nothing. Hrana
`describe.is_readonly` is also heuristic.

## Options

### A. `sqlite3_stmt_readonly()` (recommended)

The engine itself answers per prepared statement: true iff the program
makes no direct changes to the database file (SELECT, EXPLAIN, read
pragmas; false for DML/DDL/write pragmas, BEGIN IMMEDIATE, etc.).
Exqlite already prepares every statement in `run_query`; the check is
a NIF call on the handle we already hold.

- Exqlite does not expose it today. Options: upstream PR (function is
  a 5-line NIF: `enif_make_int(env, sqlite3_stmt_readonly(stmt))`), or
  vendor a tiny NIF of our own against the same sqlite3.c. Upstream
  first — the maintainers accepted `transaction_status/1`, which is
  the same shape.
- Semantics fit exactly: `sqlite3_stmt_readonly` is conservative in
  our safe direction (unknown → not readonly), and SQLite documents it
  as stable API.
- `sequence` (multi-statement scripts) stays always-dirty — scripts
  run through `sqlite3_exec` without per-statement handles. Fine:
  scripts are migrations, they *are* writes.

### B. Authorizer callback (`sqlite3_set_authorizer`)

Engine-exact too, and would also enable statement allow-listing
(blocking `ATTACH`, etc.) later. But it is a per-connection global
callback with re-entrancy constraints in a NIF, far more invasive than
option A, and answers a question we can already get per-statement.
Revisit only if we want authorization policy, not classification.

### C. Full SQL grammar in Elixir

Most work, duplicates the engine's parser imperfectly, and drifts with
SQLite versions. Only worth it if we ever need query *rewriting* or
routing decisions before reaching the owner node. Not now.

## Plan (when picked up)

1. PR `stmt_readonly/1` to exqlite (fallback: minimal vendored NIF).
2. `Database.Server.run_query`: after prepare, record
   `Sqlite3.stmt_readonly(statement)`; a session becomes dirty on the
   first non-readonly statement that returns `{:ok, _}`. `sequence`
   always dirties. Restore the skip-ship-when-clean behavior in
   `ship_if_needed/1` (the generation-0 first-ship rule stays).
3. `describe.is_readonly` uses the same call; delete heuristic
   `Sql.write?/1`. `Sql.transaction_control?/1` stays for the
   stateless edges' BEGIN rejection.
4. Invariant unchanged: anything not *provably* read-only is a write.

## Go / no-go

Go, pending the exqlite upstream conversation — no schema or protocol
impact, purely additive. Tracked as phase 5 §6.
