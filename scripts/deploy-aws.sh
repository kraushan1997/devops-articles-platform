#!/usr/bin/env bash
# Deploy the whole stack to AWS, exactly as it was run for the assignment
# (from AWS CloudShell, which already has aws, kubectl and credentials).
#
#   export TF_STATE_BUCKET=<an S3 bucket you own, versioning on>
#   ./scripts/deploy-aws.sh
#
# Layer 1 (terraform/environments/aws/1-cluster): VPC, EKS, node group, add-ons,
#          Karpenter, AWS Load Balancer Controller, ECR           (~17 min)
# Layer 2 (terraform/environments/aws/2-platform): namespaces, secrets, gp3
#          StorageClass, Karpenter NodePool, Argo CD + root app    (~4 min)
# Argo CD then syncs kube-prometheus-stack, MongoDB and the API from git.
set -euo pipefail
: "${TF_STATE_BUCKET:?set TF_STATE_BUCKET to the S3 bucket for Terraform state}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-articles-eks}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

backend() { # $1 = layer dir, $2 = state key
  cat > "$1/backend_override.tf" <<HCL
terraform {
  backend "s3" {
    bucket       = "$TF_STATE_BUCKET"
    key          = "articles-platform/aws/$2.tfstate"
    region       = "$REGION"
    encrypt      = true
    use_lockfile = true
  }
}
HCL
}

L1="$ROOT/terraform/environments/aws/1-cluster"
L2="$ROOT/terraform/environments/aws/2-platform"

step "Layer 1: network + EKS cluster"
backend "$L1" 1-cluster
[ -f "$L1/terraform.tfvars" ] || cp "$L1/terraform.tfvars.example" "$L1/terraform.tfvars"
terraform -chdir="$L1" init -input=false
terraform -chdir="$L1" plan -input=false -out=tfplan
read -r -p "Apply layer 1 (starts AWS billing)? [y/N] " ok; [ "$ok" = y ]
terraform -chdir="$L1" apply -input=false tfplan

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes -L topology.kubernetes.io/zone

step "Layer 2: platform bootstrap (Argo CD takes over from here)"
backend "$L2" 2-platform
terraform -chdir="$L2" init -input=false
terraform -chdir="$L2" plan -input=false -out=tfplan
read -r -p "Apply layer 2? [y/N] " ok; [ "$ok" = y ]
terraform -chdir="$L2" apply -input=false tfplan

step "Waiting for Argo CD to sync everything"
for app in kube-prometheus-stack mongodb articles-api; do
  printf '  %-22s' "$app"
  for _ in $(seq 1 120); do
    [ "$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null)" = Healthy ] && break
    sleep 10
  done
  kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'
done
kubectl -n articles rollout status statefulset/mongodb --timeout=600s
kubectl -n articles rollout status deployment/articles-api --timeout=300s

step "Waiting for the ALB"
for _ in $(seq 1 60); do
  ALB=$(kubectl -n articles get ingress articles-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [ -n "$ALB" ] && curl -sf -o /dev/null "http://$ALB/readyz" && break
  sleep 10
done
echo "API: http://$ALB"

step "CRUD test"
"$ROOT/scripts/test-api.sh" "http://$ALB"
