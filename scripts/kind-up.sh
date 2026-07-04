#!/usr/bin/env bash
# Boots the full sqlites stack in a local kind cluster:
# 3 data-plane pods (each with a Litestream sidecar), Postgres with
# wal_level=logical, and MinIO as the S3 replica target.
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER=sqlites

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --config deploy/overlays/kind/kind-config.yaml
fi

echo "==> building images"
docker build -t sqlites:dev .
docker build -t sqlites-operator:dev operator/

echo "==> loading images into kind"
kind load docker-image sqlites:dev --name "$CLUSTER"
kind load docker-image sqlites-operator:dev --name "$CLUSTER"

echo "==> applying manifests"
kubectl apply -k deploy/overlays/kind 2>/dev/null || true
kubectl wait --for condition=established crd/sqlitenodes.sqlites.supabase.com --timeout=60s
kubectl apply -k deploy/overlays/kind

echo "==> waiting for postgres"
kubectl -n sqlites rollout status statefulset/postgres --timeout=180s

echo "==> waiting for sqlites"
kubectl -n sqlites rollout status statefulset/sqlites --timeout=300s

echo "==> done — API available at http://localhost:8080/v1"
kubectl -n sqlites get pods
