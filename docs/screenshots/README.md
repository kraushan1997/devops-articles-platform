# API validation evidence

Captured from the local k3d cluster (1 server + 3 agents), deployed by Argo CD.

| File | Shows |
|---|---|
| `api-test-output.txt` | Full text output of `test-api.bat` / `scripts/test-api.ps1`: all five operations plus a read-after-delete |
| `01-api-crud-create-list-read.png` | POST (201), GET list (200), GET by id (200) through the Ingress on `localhost:8080` |
| `02-api-crud-update-delete.png` | PUT (200), DELETE (204), GET after delete (404), "All CRUD operations passed" |
| `03-pods-spread-across-nodes.png` | `kubectl -n articles get pods -o wide`: API and MongoDB pods on three different agent nodes |
| `04-argocd-apps-healthy.png` | Argo CD: root app-of-apps plus kube-prometheus-stack, mongodb and articles-api, all Synced/Healthy |
| `05-grafana.png` | Grafana from kube-prometheus-stack |

Re-create: `bootstrap-local.bat` (Windows) or `./scripts/bootstrap-local.sh`, then `test-api.bat` / `./scripts/test-api.sh`.
