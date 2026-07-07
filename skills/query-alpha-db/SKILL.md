---
name: query-alpha-db
description: >-
  Context and operations for the smolsqls ALPHA deployment
  (https://alpha.smolsqls.com): the auth model, provisioning a tenant/database
  via the management API, and safety when touching live shared data. To actually
  RUN SQL against alpha, use the `query-db` skill with `--db alpha` — this skill
  covers everything around that. Triggers on: "query alpha", "run this on alpha",
  "check the live db", "hit alpha.smolsqls.com", "create a database on alpha",
  "provision an alpha db".
---

# The smolsqls alpha deployment

Alpha (`https://alpha.smolsqls.com`) runs the same HTTP API as local dev.
`GET https://alpha.smolsqls.com/v1` returns the full live endpoint contract.

## Running SQL → use `query-db`

Querying alpha is just the shared tool with the `alpha` preset — this skill does
not repeat the query mechanics (args, `--file`, output, the server's
one-statement / no-`ATTACH`-`DETACH`-`VACUUM` rules). See the **`query-db`**
skill; in short:

```sh
elixir skills/query-db/smolsqls_query.exs --db alpha "SELECT * FROM sqlite_master WHERE type = ?" --args '["table"]'
```

## Auth model

- **Query endpoints** authenticate with a **per-database `auth_token`** (Bearer).
  `query-db --db alpha` reads it from `SMOLSQLS_ALPHA_DB_TOKEN` / the git-ignored
  `.claude/alpha-db.env`.
- **Management endpoints** (create db, backups, keys) authenticate with a
  **tenant `api_key`** — kept separately in `.claude/alpha.env` as
  `SMOLSQLS_ALPHA_API_KEY`.

Never hardcode, commit, or echo a token. If you need one and don't have it, ask
the user — don't guess.

## Safety on a live, shared deployment

Alpha is a real running server. Before running anything that mutates or is
expensive against live data — `INSERT`/`UPDATE`/`DELETE`, `DROP`, schema
changes, or an unbounded scan — confirm with the user first and prefer a
`SELECT` (or a `WHERE`-scoped statement) unless they explicitly asked to write.
Read-only queries are fine to run directly.

## Provisioning (management API — not the query tool)

Creating a tenant/database uses the management endpoints, so these are plain
HTTP calls. Secrets (`api_key`, `auth_token`) are returned **only** in the
create response — capture them immediately.

```sh
# 1. Sign up a tenant (api_key returned once) — skip if you already have a key
curl -sS -X POST "https://alpha.smolsqls.com/v1/tenants" \
  -H 'content-type: application/json' \
  -d '{"name": "My Org", "slug": "my-org"}'      # -> data.api_key

# 2. Create a database (auth_token + connection strings returned once)
curl -sS -X POST "https://alpha.smolsqls.com/v1/databases" \
  -H "authorization: Bearer $SMOLSQLS_ALPHA_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"name": "scratch"}'                        # -> data.id, data.auth_token
```

Then store `SMOLSQLS_ALPHA_DB_ID` / `SMOLSQLS_ALPHA_DB_TOKEN` in the git-ignored
`.claude/alpha-db.env` (auto-loaded by `query-db`) and query with
`query-db --db alpha`. Tell the user to store the secrets — they are never echoed
by later reads.
