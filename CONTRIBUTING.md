# Contributing to smolsqls

Thanks for your interest. This is an early, opinionated project; see
[`README.md`](README.md) for the architecture and what smolsqls is.

## Dev setup

Prerequisites (match [`.github/workflows/ci.yml`](.github/workflows/ci.yml) —
currently **OTP 29.0.2 / Elixir 1.20.2**) plus a Postgres for the control-plane
metadb, started with logical replication:

```sh
docker run -d --name metadb \
  -e POSTGRES_PASSWORD=postgres -p 5432:5432 \
  postgres:16 -c wal_level=logical -c max_replication_slots=16

mix setup        # deps.get + ecto.setup + assets
mix phx.server   # http://localhost:4000  (GET /v1 for the API index)
```

## Tests

```sh
mix test                                             # unit + integration
epmd -daemon && mix test --include distributed --only distributed   # multi-node
(cd operator && mix test)                            # the Kubernetes operator
```

## Quality gate — run before opening a PR

CI runs these; they must be green:

```sh
mix ci         # compile -Werror, format, credo --strict, sobelow, audits, reach arch policy
mix dialyzer   # type analysis (own CI job)
```

## Pull requests

1. Branch off `main`.
2. Keep changes focused; update `README.md` (and other docs) in the same change
   when behavior/commands/structure move.
3. Get `mix ci` + `mix dialyzer` + tests green locally.
4. Open a PR against `main` with a clear what/why.

## Claude Code skills & the project tracker

This repo ships [Claude Code](https://code.claude.com) skills in
[`skills/`](skills/) — including **`smolsqls-pm`**, a project tracker (projects,
plans, tasks) that we dogfood in a live smolsqls database rather than in local
markdown. Enable the skills locally:

```sh
./skills/install.sh            # link into ./.claude/skills (this repo)
./skills/install.sh --global   # link into ~/.claude/skills (any directory)
```

The tracker and the `query-alpha-db` skill talk to a shared, live database on
the alpha deployment via the Elixir tool `skills/smolsqls_query.exs`. That data
is real and single-instance, so there's nothing to self-provision — **if you
genuinely need to read or update the tracker, get the database credentials from
the project owner.** (Store them in a git-ignored `.claude/*.env`; never commit
a token.)
