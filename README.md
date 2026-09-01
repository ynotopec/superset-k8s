# Superset K8s — Reproducible Deployment

One-command deploy of Apache Superset (v6.1.0) on any Kubernetes cluster. **Zero hardcoded dependencies** on your infrastructure.

## Quick Start

```bash
# 1. Copy and edit the environment config
cp .env.example .env
# Edit .env — change namespace, passwords, domain

# 2. Deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

That's it. The script substitutes variables at runtime — manifests stay unchanged in git.

## Variable Reference

Copy `.env.example` to `.env` and override any value:

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE` | `demo1` | K8s namespace |
| `DOMAIN` | `local.lan` | Domain suffix (builds SUPERSET_HOST) |
| `SUPERSET_PASSWORD` | `changeme` | PostgreSQL password |
| `SUPERSET_SECRET_KEY` | `changeme_superset_secret_key` | Superset secret key |
| `SUPERSET_ADMIN_USER` | `admin` | Admin username |
| `SUPERSET_ADMIN_PASSWORD` | `admin` | Admin password |
| `SUPERSET_HOST` | `superset.${NAMESPACE}.${DOMAIN}` | Full hostname for ingress TLS |

## How It Works

The script loads `.env`, then runs `sed` on every manifest to replace placeholders before piping to `kubectl apply`:

- `__NAMESPACE__` → namespace for all resources
- `__SUPERSET_PASSWORD__` → PostgreSQL password
- `__SUPERSET_SECRET_KEY__` → Superset secret key
- `__SUPERSET_ADMIN_USER__` / `__SUPERSET_ADMIN_PASSWORD__` → admin credentials
- `__SUPERSET_HOST__` → full hostname for ingress TLS

## Manual (kubectl)

```bash
# Apply manifests with variable substitution (or use deploy.sh)
for f in manifests/*.yaml; do
  sed -e "s|__NAMESPACE__|${NAMESPACE}|g" \
      -e "s|__SUPERSET_PASSWORD__|${SUPERSET_PASSWORD}|g" \
      -e "s|__SUPERSET_SECRET_KEY__|${SUPERSET_SECRET_KEY}|g" \
      -e "s|__SUPERSET_ADMIN_USER__|${SUPERSET_ADMIN_USER}|g" \
      -e "s|__SUPERSET_ADMIN_PASSWORD__|${SUPERSET_ADMIN_PASSWORD}|g" \
      -e "s|__SUPERSET_HOST__|${SUPERSET_HOST}|g" \
      "$f" | kubectl apply -f -
done

# Wait for init job
kubectl wait --for=condition=complete job/superset-init -n ${NAMESPACE} --timeout=300s
```

## Helm Alternative

```bash
helm repo add apache-superset https://apache-superset.github.io/helm-charts
helm repo update

# Edit manifests/superset-helm-values.yaml with your vars, then:
helm install superset apache-superset/superset \
  -n ${NAMESPACE} \
  -f manifests/superset-helm-values.yaml
```

## Access

- **Ingress:** `https://${SUPERSET_HOST}`
- **Port-forward:** `kubectl port-forward svc/superset-svc 8088:8088 -n ${NAMESPACE}` → `http://localhost:8088/superset/`

## Troubleshooting

| Symptom | Fix |
|---|---|
| Pod crashes immediately | Official image lacks `psycopg2`; build `Dockerfile.superset-fix` or use `amancevice/superset:6.1.0` |
| `/app/static` missing 404s | `kubectl exec <pod> -- sh -c "ln -sf /app/superset/static /app/static"` |
| Dashboard click → infinite load | Remove `rewrite-target` annotation from ingress |
| Init job stuck | Check `kubectl logs job/superset-init -n ${NAMESPACE}` |
| Helm install fails with secret conflict | `kubectl -n ${NAMESPACE} delete secret superset-env` then retry helm |

## Architecture

```
┌─────────────────────────────────────────────┐
│  Ingress (public, TLS via cert-manager)     │
│  https://superset.${NAMESPACE}.${DOMAIN}     │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│  superset-svc (ClusterIP:8088)              │
│  ┌────────────────┐ ┌───────────────────┐   │
│  │  superset pod  │ │  superset-init    │   │
│  │  :8088         │ │  (Job, runs once) │   │
│  └───────┬────────┘ └───────────────────┘   │
│          │                                   │
│  ┌───────▼────────┐                         │
│  │  PostgreSQL    │ ← superset-postgresql   │
│  │  :5432         │                         │
│  └────────────────┘                         │
│  ┌────────────────┐                         │
│  │  Redis         │ ← superset-redis        │
│  │  :6379         │                         │
│  └────────────────┘                         │
└─────────────────────────────────────────────┘
```

## File Layout

```
superset-k8s/
├── .env.example             # Config template — copy to .env and edit
├── .env                     # Local secrets (git-ignored)
├── .gitignore
├── README.md
├── manifests/
│   ├── superset-all.yaml    # All-in-one manifest (namespace, postgres, redis, superset, ingress, init job)
│   ├── superset-helm-values.yaml  # Helm chart overrides
│   └── Dockerfile.superset-fix   # Official image + psycopg2
└── scripts/
    └── deploy.sh            # One-command deploy (namespace → manifests → init wait → verify)
```

## Requirements

- Kubernetes cluster (any distribution)
- `kubectl` installed
- Ingress class `public` with cert-manager (for TLS) — or remove the ingress section from manifests
- Docker/podman (optional, only if building `Dockerfile.superset-fix`)
