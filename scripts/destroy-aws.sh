#!/usr/bin/env bash
# Tear everything down in the right order, so nothing keeps billing:
#   1. delete the Argo CD root app (cascades: API, MongoDB, monitoring, the
#      Ingress -> the AWS Load Balancer Controller deletes the ALB)
#   2. remove Karpenter-launched nodes
#   3. terraform destroy layer 2, then layer 1
#   4. delete the EBS volumes the gp3 StorageClass kept (reclaimPolicy: Retain)
#
#   export TF_STATE_BUCKET=<same bucket as deploy>
#   ./scripts/destroy-aws.sh
set -euo pipefail
: "${TF_STATE_BUCKET:?set TF_STATE_BUCKET}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-articles-eks}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
L1="$ROOT/terraform/environments/aws/1-cluster"
L2="$ROOT/terraform/environments/aws/2-platform"
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

read -r -p "Destroy EVERYTHING for $CLUSTER in $REGION (data is lost)? type 'destroy': " ok
[ "$ok" = destroy ]

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

step "1. Delete the GitOps root app (cascade) and wait for the ALB to go"
kubectl -n argocd delete application root --ignore-not-found --timeout=15m || true
for _ in $(seq 1 60); do
  n=$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "length(LoadBalancers[?starts_with(LoadBalancerName, 'k8s-articles')])" --output text)
  [ "$n" = 0 ] && break; sleep 10
done
kubectl delete pvc --all -n articles --ignore-not-found --wait=false || true
kubectl delete pvc --all -n monitoring --ignore-not-found --wait=false || true

step "2. Remove Karpenter nodes"
kubectl delete nodepools --all --ignore-not-found --timeout=10m || true
kubectl delete nodeclaims --all --ignore-not-found --timeout=10m || true

step "3a. terraform destroy layer 2"
terraform -chdir="$L2" init -input=false >/dev/null
terraform -chdir="$L2" destroy -input=false -auto-approve

step "3b. terraform destroy layer 1"
terraform -chdir="$L1" init -input=false >/dev/null
terraform -chdir="$L1" destroy -input=false -auto-approve

step "4. Delete retained EBS volumes (MongoDB / Prometheus data)"
VOLS=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/name" "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text)
for v in $VOLS; do echo "  deleting $v"; aws ec2 delete-volume --region "$REGION" --volume-id "$v"; done

step "Leftover check"
aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text
aws ec2 describe-instances --region "$REGION" --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
  "Name=instance-state-name,Values=pending,running" --query 'Reservations[].Instances[].InstanceId' --output text
echo "Done. The Terraform state bucket ($TF_STATE_BUCKET) is kept; delete it yourself if no longer needed."
