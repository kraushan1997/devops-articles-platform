# Validation screenshots (live EKS run, us-east-1, 2026-09-26)

Taken in AWS CloudShell against the `articles-eks` cluster. Every API call went through
the public ALB created by the AWS Load Balancer Controller. The full text of each is in
[`../evidence/`](../evidence).

| File | Shows |
|---|---|
| `01-eks-crud-create-list-read.jpg` | `scripts/test-api.sh`: readyz 200, POST 201, GET list 200, GET by id 200 |
| `02-eks-crud-update-delete.jpg` | PUT 200, DELETE 204, GET after delete 404, "All CRUD operations passed" |
| `03-eks-cluster-argocd-pods-across-azs.jpg` | `scripts/collect-evidence.sh` part 1: EKS 1.35 ACTIVE (KMS secrets), 3 nodes in us-east-1a/1b/1c, 4 Argo CD apps Synced/Healthy, API + MongoDB pods one per AZ, gp3 PVCs, ALB Ingress |
| `04-eks-mongo-rs-karpenter-prometheus-ntp.jpg` | part 2: HPA, PDBs, replica set PRIMARY/SECONDARY/SECONDARY, Karpenter NodePool + EC2NodeClass, Prometheus targets and request counts, chrony on every node synced to 169.254.169.123 |
| `05-eks-mongodb-failover-ebs-volumes.jpg` | `scripts/failover-test.sh`: primary deleted under write load, 111/111 writes OK, election timeline from the mongod logs; encrypted gp3 EBS volumes per AZ |

Re-create: `./scripts/test-api.sh`, `./scripts/collect-evidence.sh`, `./scripts/failover-test.sh`.
