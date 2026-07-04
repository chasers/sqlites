#!/usr/bin/env bash
# End-to-end smoke test against the kind cluster: agent lifecycle over
# the NodePort, cluster placement across pods, and operator-reported
# SqliteNode status.
set -euo pipefail

BASE=${BASE:-http://localhost:8080}

echo "==> API index"
curl -sf "$BASE/v1" >/dev/null

echo "==> tenant signup"
SIGNUP=$(curl -sf -X POST "$BASE/v1/tenants" -H 'content-type: application/json' \
  -d "{\"name\":\"Kind Smoke\",\"slug\":\"kind-smoke-$RANDOM\"}")
API_KEY=$(echo "$SIGNUP" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['api_key'])")

echo "==> create databases (placement should spread across pods)"
NODES=""
for i in 1 2 3 4 5 6; do
  DB=$(curl -sf -X POST "$BASE/v1/databases" -H "authorization: Bearer $API_KEY" \
    -H 'content-type: application/json' -d "{\"name\":\"smoke-$i\"}")
  DB_ID=$(echo "$DB" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['id'])")
  DB_TOKEN=$(echo "$DB" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['auth_token'])")

  RESULT=$(curl -sf -X POST "$BASE/v1/databases/$DB_ID/query" \
    -H "authorization: Bearer $DB_TOKEN" -H 'content-type: application/json' \
    -d '{"sql":"CREATE TABLE t (v TEXT)"}')

  curl -sf -X POST "$BASE/v1/databases/$DB_ID/query" \
    -H "authorization: Bearer $DB_TOKEN" -H 'content-type: application/json' \
    -d "{\"sql\":\"INSERT INTO t VALUES (?)\",\"args\":[\"pod-check-$i\"]}" >/dev/null

  ROW=$(curl -sf -X POST "$BASE/v1/databases/$DB_ID/query" \
    -H "authorization: Bearer $DB_TOKEN" -H 'content-type: application/json' \
    -d '{"sql":"SELECT v FROM t"}' | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['rows'][0][0])")
  [ "$ROW" = "pod-check-$i" ] || { echo "FAIL: round-trip mismatch"; exit 1; }
done

echo "==> placement spread"
kubectl exec -n sqlites sqlites-0 -- /app/bin/sqlites rpc \
  'IO.inspect(Enum.frequencies(for {_, d} <- :ets.tab2list(Sqlites.ReadModel.Databases), d.node != nil, do: d.node))'

echo "==> cluster membership from inside a pod"
kubectl exec -n sqlites sqlites-0 -- /app/bin/sqlites rpc 'IO.inspect(Node.list())'

echo "==> SqliteNode statuses (operator-reported)"
kubectl -n sqlites get sqlitenodes

echo "==> replication slots on metadb"
kubectl exec -n sqlites postgres-0 -- psql -U postgres -d sqlites -c \
  "SELECT slot_name, active, wal_status FROM pg_replication_slots"

echo "SMOKE OK"
