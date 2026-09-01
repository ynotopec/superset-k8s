#!/usr/bin/env bash
set -euo pipefail
#
# Deploy Apache Superset on K8s — all-in-one script
# Usage: ./scripts/deploy.sh [namespace]
# Prerequisite: copy .env.example to .env and edit, then run.
#

# Load environment variables from .env (skip if already exported)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a; . "${ENV_FILE}"; set +a
else
  # Defaults (non-production safe — warn user)
  NAMESPACE="${NAMESPACE:-demo1}"
  DOMAIN="${DOMAIN:-local.lan}"
  SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-changeme}"
  SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY:-changeme_superset_secret_key}"
  SUPERSET_ADMIN_USER="${SUPERSET_ADMIN_USER:-admin}"
  SUPERSET_ADMIN_PASSWORD="${SUPERSET_ADMIN_PASSWORD:-admin}"
  export NAMESPACE DOMAIN SUPERSET_PASSWORD SUPERSET_SECRET_KEY
  export SUPERSET_ADMIN_USER SUPERSET_ADMIN_PASSWORD
  SUPERSET_HOST="superset.${NAMESPACE}.${DOMAIN}"
  echo "[WARN] No .env found — using defaults. Copy .env.example and edit first."
fi

# Merge optional CLI arg with .env
NAMESPACE="${1:-${NAMESPACE}}"
SUPERSET_HOST="superset.${NAMESPACE}.${DOMAIN}"
export NAMESPACE SUPERSET_HOST

echo "=== Deploying Superset to namespace ${NAMESPACE} ==="

# 0. Verify .env was loaded (non-default)
if [ "${SUPERSET_PASSWORD}" = "changeme" ] && [ "${SUPERSET_SECRET_KEY}" = "changeme_superset_secret_key" ]; then
  echo "[WARN] Using default passwords! Copy .env.example to .env and edit before production use."
fi

# 1. Namespace
echo "[1/5] Creating namespace '${NAMESPACE}'..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 2. Substitute variables in manifests and apply
echo "[2/5] Applying manifests (with variable substitution)..."
for f in "${SCRIPT_DIR}"/manifests/*.yaml; do
  sed -e "s|__NAMESPACE__|${NAMESPACE}|g" \
      -e "s|__SUPERSET_PASSWORD__|${SUPERSET_PASSWORD}|g" \
      -e "s|__SUPERSET_SECRET_KEY__|${SUPERSET_SECRET_KEY}|g" \
      -e "s|__SUPERSET_ADMIN_USER__|${SUPERSET_ADMIN_USER}|g" \
      -e "s|__SUPERSET_ADMIN_PASSWORD__|${SUPERSET_ADMIN_PASSWORD}|g" \
      -e "s|__SUPERSET_HOST__|${SUPERSET_HOST}|g" \
      "$f" | kubectl apply -f -
done

# 3. Wait for init job
echo "[3/5] Waiting for initialization job to complete..."
kubectl wait --for=condition=complete job/superset-init -n "${NAMESPACE}" --timeout=300s

# 4. Verify
echo "[4/5] Verifying deployment..."
echo ""
echo "--- Pods ---"
kubectl get pods -n "${NAMESPACE}" -l app=superset
echo ""
echo "--- Services ---"
kubectl get svc -n "${NAMESPACE}" | grep superset
echo ""
echo "--- Ingress ---"
kubectl get ingress -n "${NAMESPACE}" | grep superset

# 5. Summary
echo ""
echo "=== Done ==="
echo "Access Superset at:"
echo "  Ingress:  https://${SUPERSET_HOST}"
echo "  Port-fwd: kubectl port-forward svc/superset-svc 8088:8088 -n ${NAMESPACE}"
echo ""
echo "Admin credentials: ${SUPERSET_ADMIN_USER} / ${SUPERSET_ADMIN_PASSWORD}"
