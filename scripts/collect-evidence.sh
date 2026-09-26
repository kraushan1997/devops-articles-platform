#!/usr/bin/env bash
# Print the validation evidence for the running EKS deployment (assignment section 9).
# Run from AWS CloudShell (or any shell with aws + kubectl pointed at the cluster):
#
#   ./scripts/collect-evidence.sh | tee docs/evidence/eks-evidence.txt
set -uo pipefail
CLUSTER="${CLUSTER:-articles-eks}"
REGION="${AWS_REGION:-us-east-1}"
h() { printf '\n### %s\n$ %s\n' "$1" "$2"; }

echo "EKS evidence: cluster=$CLUSTER region=$REGION at $(date -u +%FT%TZ)"

h "Cluster" "aws eks describe-cluster"
aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.{name:name,version:version,status:status,platform:platformVersion,secretsEncryption:encryptionConfig[0].resources[0]}' --output table

h "Nodes, one per availability zone" "kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,karpenter.sh/capacity-type"
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,karpenter.sh/capacity-type

h "GitOps: Argo CD applications" "kubectl -n argocd get applications"
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'

h "Workloads spread across nodes/AZs" "kubectl -n articles get pods -o wide"
kubectl -n articles get pods -o custom-columns='POD:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,NODE:.spec.nodeName'

h "Storage, ingress, autoscaling, disruption budgets" "kubectl -n articles get pvc,ingress,hpa,pdb"
kubectl -n articles get pvc -o custom-columns='PVC:.metadata.name,STATUS:.status.phase,SIZE:.status.capacity.storage,CLASS:.spec.storageClassName'
kubectl -n articles get ingress
kubectl -n articles get hpa
kubectl -n articles get pdb

h "MongoDB replica set members" "rs.status() via mongosh"
kubectl -n articles exec mongodb-0 -c rs-init -- bash -c \
  'mongosh --quiet -u root -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "rs.status().members.forEach(m => print(m.name.split(\".\")[0], m.stateStr, \"health=\" + m.health))"' \
  || echo "(could not query rs.status)"

h "Karpenter node pool" "kubectl get nodepools,ec2nodeclasses,nodeclaims"
kubectl get nodepools,ec2nodeclasses 2>/dev/null
kubectl get nodeclaims 2>/dev/null

h "Prometheus is scraping the API" "PromQL: up / http_requests_total"
PROM_SVC=$(kubectl -n monitoring get svc -l app=kube-prometheus-stack-prometheus,self-monitor=true -o jsonpath='{.items[0].metadata.name}')
for q in 'up{namespace="articles"}' 'sum by (handler, status) (http_requests_total{namespace="articles", handler=~"/articles.*"})'; do
  echo "PromQL: $q"
  # query through the API server's service proxy (the Prometheus image has no curl/wget)
  kubectl get --raw "/api/v1/namespaces/monitoring/services/$PROM_SVC:http-web/proxy/api/v1/query?query=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$q")" \
    | python3 -c 'import sys,json;[print(" ", {k:v for k,v in r["metric"].items() if k in ("pod","handler","status","job")}, "=", r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]]'
done

h "Time sync on the nodes (NTP)" "SSM Run Command: chronyc tracking"
IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$IDS" ]; then
  CMD=$(aws ssm send-command --region "$REGION" --document-name AWS-RunShellScript \
    --instance-ids $IDS --parameters 'commands=["chronyc -n tracking | grep -E \"Reference ID|System time|Leap status\""]' \
    --query 'Command.CommandId' --output text)
  sleep 8
  for i in $IDS; do
    echo "-- $i"
    aws ssm get-command-invocation --region "$REGION" --command-id "$CMD" --instance-id "$i" \
      --query 'StandardOutputContent' --output text
  done
fi
