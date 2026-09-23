#!/usr/bin/env bash
# One-command local environment:
#   1. Terraform layer 1  -> k3d cluster (3 servers + 3 agents)
#   2. Terraform layer 2  -> namespaces, secrets, Argo CD, root GitOps app
#   3. wait for Argo CD to sync MongoDB + API + monitoring
#   4. run the API test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="${TF:-terraform}"   # TF=tofu to use OpenTofu

for bin in docker k3d kubectl "$TF"; do
  command -v "$bin" >/dev/null || { echo "missing prerequisite: $bin"; exit 1; }
done

echo "==> [1/4] k3d cluster"
$TF -chdir="$ROOT/terraform/environments/local/1-cluster" init -input=false
$TF -chdir="$ROOT/terraform/environments/local/1-cluster" apply -auto-approve

echo "==> [2/4] platform (Argo CD + secrets)"
$TF -chdir="$ROOT/terraform/environments/local/2-platform" init -input=false
$TF -chdir="$ROOT/terraform/environments/local/2-platform" apply -auto-approve

echo "==> [3/4] waiting for Argo CD applications to become Healthy (first run pulls images: ~5-10 min)"
for app in kube-prometheus-stack mongodb articles-api; do
  until kubectl -n argocd get application "$app" >/dev/null 2>&1; do sleep 5; done
  kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy "application/$app" --timeout=900s
done
kubectl -n articles rollout status statefulset/mongodb --timeout=600s
kubectl -n articles rollout status deployment/articles-api --timeout=300s
kubectl -n articles get pods -o wide

echo "==> [4/4] API smoke test"
"$ROOT/scripts/test-api.sh" http://localhost:8080
