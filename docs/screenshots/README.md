# API validation evidence

Add here after running `./scripts/test-api.sh` against the Ingress / LoadBalancer:

- `01-crud-test.png` — full output of `test-api.sh` (create, list, read, update, delete, 404)
- `02-pods.png` — `kubectl -n articles get pods -o wide` (pods spread across nodes/zones)
- `03-argocd.png` — Argo CD applications Synced / Healthy
- `04-grafana.png` — "Articles API" dashboard
- `05-failover.png` (optional) — API still serving after `kubectl -n articles delete pod mongodb-0`
