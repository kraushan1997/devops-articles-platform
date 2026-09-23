#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="${TF:-terraform}"
# layer 2 state only lives inside the cluster; deleting the cluster removes it
$TF -chdir="$ROOT/terraform/environments/local/1-cluster" destroy -auto-approve
rm -f "$ROOT/terraform/environments/local/2-platform/terraform.tfstate"*
