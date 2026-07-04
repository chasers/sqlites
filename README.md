# sqlites

A multitenant, globally clusterable SQLite database service written in
Elixir/Phoenix. Sign up for a tenant, create SQLite databases over a REST
API (or a small LiveView UI), get a connection string back, and connect
with any stock libSQL client or plain HTTP.

## Architecture

Built for ~1M databases per cluster across ~10 data-plane nodes.

**Control plane** (Postgres-backed): tenants, databases, auth tokens, and
placement decisions. Postgres is the source of truth for writes but never
sits on the query path: every node keeps a **full ETS replica** of the
request-path tables, bootstrapped with `COPY` at startup and kept current
by streaming the WAL over a per-node permanent logical replication slot
(`Postgrex.ReplicationConnection` + a minimal pgoutput decoder). Postgres
downtime pauses create/delete; queries and auth keep working.

**Data plane**: one `Sqlites.DataPlane.Database.Server` GenServer per
database owns the single `exqlite` connection to that SQLite file (WAL
mode) and serializes all writes. Servers activate **lazily on first
query** and stay hot for a configurable idle TTL (default 1h), so boot is
cold and traffic warms the set. Processes register in
[`syn`](https://hex.pm/packages/syn) under the `:sqlites_databases`
scope, so every node knows which node owns which database; registration
happens before the SQLite file is opened, which guarantees a single
writer even under racing activations. Cross-node query traffic travels
over [`gen_rpc`](https://hex.pm/packages/gen_rpc) — Erlang distribution
carries only cluster membership, syn gossip, and
[libcluster_postgres](https://github.com/supabase/libcluster_postgres)
node discovery (LISTEN/NOTIFY on the metadb), never query payloads.
On boot each node walks its data volume and claims any database whose
file is local but whose record points elsewhere — the volume, not the
node name, is the source of truth for placement.

**Client access** — no custom client needed:

- **libSQL / Hrana**: any stock libSQL client (`@libsql/client`, etc.)
  connects with the `libsql://host:port?authToken=...` string returned
  at creation time. The server speaks a Hrana v1/v2 subset over
  WebSocket; the auth token identifies the database.
- **Plain HTTP**: `POST /v1/databases/:id/query` with
  `{"sql": "...", "args": [...]}` and the database auth token as a
  Bearer token.

**Durability** is an infrastructure concern owned by the Kubernetes
operator in [`operator/`](operator/): PVC-backed data directories,
Litestream replication, and CRD-driven backup/restore. The control plane
talks to it exclusively through the `Sqlites.Infra` port by manipulating
`SqliteDatabase` custom resources (`Sqlites.Infra.Kubernetes`); dev and
test use `Sqlites.Infra.Local` (backups via `VACUUM INTO`).

## Agent-friendly by design

The full lifecycle is drivable over HTTP with no human steps:

```sh
# discover the API
curl http://localhost:4000/v1

# sign up (api_key returned once)
curl -X POST http://localhost:4000/v1/tenants \
  -H 'content-type: application/json' \
  -d '{"name": "My Org", "slug": "my-org"}'

# create a database (returns auth_token + connection strings)
curl -X POST http://localhost:4000/v1/databases \
  -H "authorization: Bearer $API_KEY" \
  -H 'content-type: application/json' \
  -d '{"name": "task-db"}'

# query it
curl -X POST http://localhost:4000/v1/databases/$DB_ID/query \
  -H "authorization: Bearer $DB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"sql": "SELECT 1"}'

# trigger / list backups, restore
curl -X POST http://localhost:4000/v1/databases/$DB_ID/backups \
  -H "authorization: Bearer $API_KEY"
curl -X POST http://localhost:4000/v1/databases/$DB_ID/restore \
  -H "authorization: Bearer $API_KEY" \
  -H 'content-type: application/json' \
  -d "{\"backup_id\": \"$BACKUP_ID\"}"
```

Or with a stock libSQL client:

```js
import { createClient } from "@libsql/client";

const client = createClient({
  url: "ws://localhost:4000",
  authToken: process.env.DB_TOKEN,
});
await client.execute("SELECT 1");
```

## Running locally

Requires Erlang/OTP 27+, Elixir 1.18+, and Postgres on `localhost:5432`
(`postgres`/`postgres`).

```sh
mix setup
iex --sname sqlites -S mix phx.server
```

The LiveView UI is at [`localhost:4000`](http://localhost:4000) — sign
up or paste a tenant API key, then create/delete databases, reveal
connection strings, and trigger backups from the dashboard.

## Tests

```sh
mix test                        # unit + integration (needs Postgres)
mix test --include distributed  # + multi-node syn/gen_rpc tests (needs epmd)
```

The distributed tests boot a real peer BEAM node with `:peer`, place a
database server on it, and assert that syn resolves it from the primary
node and that queries round-trip over gen_rpc (on a distinct TCP port),
including deregistration when the peer dies.

## Repo layout

```
lib/sqlites/control_plane*    # tenants, databases, placement metadata (Ecto/Postgres)
lib/sqlites/data_plane*       # per-database servers, syn registry, gen_rpc router
lib/sqlites/infra*            # port to the durability layer (Local / Kubernetes adapters)
lib/sqlites_web/controllers/  # REST API (see GET /v1 for the index)
lib/sqlites_web/hrana/        # Hrana (libSQL) WebSocket endpoint
lib/sqlites_web/live/         # LiveView dashboard
operator/                     # Bonny-based Kubernetes operator (SqliteDatabase CRD)
```
