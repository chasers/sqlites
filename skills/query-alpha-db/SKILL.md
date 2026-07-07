---
name: query-alpha-db
description: >-
  Run SQL against a live database on the smolsqls alpha deployment
  (https://alpha.smolsqls.com) via its HTTP query API. Use whenever the user
  wants to query alpha, inspect or smoke-test live data, verify the deployed
  query path end-to-end, or reproduce a query issue on the real server. Covers
  auth (per-database Bearer auth_token), the request/response contract, the SQL
  restrictions the server enforces, and provisioning a database if one isn't set
  up yet. Triggers on: "query alpha", "run this on alpha", "check the live db",
  "hit alpha.smolsqls.com".
---

# Query a live database on alpha.smolsqls.com

The smolsqls alpha deployment exposes the same HTTP API as local dev. Query
endpoints authenticate with a **per-database `auth_token`** (Bearer); management
endpoints (create db, backups, keys) authenticate with a **tenant `api_key`**.
`GET https://alpha.smolsqls.com/v1` returns the full live endpoint contract.

## Credentials — from the environment, never committed

This skill reads credentials from env vars. **Never hardcode a token in a file,
commit one, or echo one into the transcript.** Put them in an untracked file
(e.g. `.envrc.local` sourced by direnv, or your shell) — not in `.envrc`, which
is tracked.

| Var | Purpose | Default |
|---|---|---|
| `SMOLSQLS_ALPHA_URL` | Base URL | `https://alpha.smolsqls.com` |
| `SMOLSQLS_ALPHA_DB_ID` | Database id to query | — |
| `SMOLSQLS_ALPHA_DB_TOKEN` | Database `auth_token` (Bearer, for queries) | — |
| `SMOLSQLS_ALPHA_API_KEY` | Tenant `api_key` (only for provisioning/backups) | — |

If `SMOLSQLS_ALPHA_DB_ID` / `SMOLSQLS_ALPHA_DB_TOKEN` are unset, stop and either
ask the user for them or provision a database (see the last section) — do **not**
guess an id or invent a token.

## Preflight

```sh
: "${SMOLSQLS_ALPHA_URL:=https://alpha.smolsqls.com}"
[ -n "$SMOLSQLS_ALPHA_DB_ID" ]    || { echo "set SMOLSQLS_ALPHA_DB_ID"; exit 1; }
[ -n "$SMOLSQLS_ALPHA_DB_TOKEN" ] || { echo "set SMOLSQLS_ALPHA_DB_TOKEN"; exit 1; }
curl -sS "$SMOLSQLS_ALPHA_URL/v1" >/dev/null   # reachability + contract
```

## Run a query

`POST /v1/databases/:id/query` with `{"sql": "...", "args": [...]}`. `args` are
positional, bound to `?` placeholders, and optional.

```sh
curl -sS -X POST \
  "$SMOLSQLS_ALPHA_URL/v1/databases/$SMOLSQLS_ALPHA_DB_ID/query" \
  -H "authorization: Bearer $SMOLSQLS_ALPHA_DB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"sql": "SELECT * FROM sqlite_master WHERE type = ?", "args": ["table"]}'
```

Pipe through `| jq` (or `python3 -m json.tool`) to read the result. Keep SQL and
args in the JSON body — never string-interpolate user values into the SQL; use
`?` placeholders so the server binds them.

## Response contract

- **Success:** `{"data": {"columns": [...], "rows": [[...], ...], "num_changes": N}}`
  - `columns` — column names; `rows` — arrays aligned to `columns`;
    `num_changes` — affected rows for writes.
- **Error:** `{"error": {"code": "...", "message": "..."}}` with a matching HTTP
  status (401 unauthorized, 404 unknown database, 429 rate-limited, 4xx/5xx
  otherwise).

## What the server rejects (don't fight these)

- **Transaction control** (`BEGIN` / `COMMIT` / `ROLLBACK` / `SAVEPOINT`) over
  the REST query endpoint → `transactions_not_supported`. Send one autonomous
  statement per request; for multi-statement scripts use the Hrana `sequence`
  op, not this endpoint.
- **`ATTACH` / `DETACH` / `VACUUM`** (all forms, including `VACUUM INTO`) →
  `authorization denied`. Tenant SQL runs under an authorizer that denies these;
  backups/compaction are a control-plane concern, not a tenant query.
- **Rate limits & timeouts** are per-database (`429` when exceeded; long queries
  hit the resolved statement/query timeout). Back off rather than hammering.

## Safety on a live, shared deployment

Alpha is a real running server. Before running anything that mutates or is
expensive against live data — `INSERT`/`UPDATE`/`DELETE`, `DROP`, schema
changes, or an unbounded scan — confirm with the user first and prefer a
`SELECT` (or a `WHERE`-scoped statement) unless they explicitly asked to write.
Read-only queries are fine to run directly.

## If you don't have a database/token yet

Provision one with a tenant `api_key` (the `auth_token` is shown **only** in the
create response — capture it immediately):

```sh
# 1. Sign up a tenant (api_key returned once) — skip if you already have a key
curl -sS -X POST "$SMOLSQLS_ALPHA_URL/v1/tenants" \
  -H 'content-type: application/json' \
  -d '{"name": "My Org", "slug": "my-org"}'      # -> data.api_key

# 2. Create a database (auth_token + connection strings returned once)
curl -sS -X POST "$SMOLSQLS_ALPHA_URL/v1/databases" \
  -H "authorization: Bearer $SMOLSQLS_ALPHA_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"name": "scratch"}'                        # -> data.id, data.auth_token
```

Then export `SMOLSQLS_ALPHA_DB_ID` and `SMOLSQLS_ALPHA_DB_TOKEN` (in your
untracked env file) and query as above. Tell the user to store the secrets —
they are never echoed by later reads.
