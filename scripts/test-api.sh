#!/usr/bin/env bash
# Exercise all five Articles endpoints against a running deployment.
#
#   ./scripts/test-api.sh                         # k3d: http://localhost:8080
#   ./scripts/test-api.sh http://<alb-hostname>   # EKS
#
# Output is formatted for screenshots / screen recording (assignment section 9).
set -euo pipefail
BASE="${1:-http://localhost:8080}"
RESP="$(mktemp)"; trap 'rm -f "$RESP"' EXIT
pretty() { if command -v jq >/dev/null; then jq .; else python3 -m json.tool; fi; }
step()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
call()   { # method path [json-body]
  local m=$1 p=$2 body=${3:-}
  printf '\033[0;33m$ curl -X %s %s%s %s\033[0m\n' "$m" "$BASE" "$p" "${body:+-d '$body'}"
  if [ -n "$body" ]; then
    curl -sS -X "$m" "$BASE$p" -H 'Content-Type: application/json' -d "$body" -w '\n%{http_code}' > "$RESP"
  else
    curl -sS -X "$m" "$BASE$p" -w '\n%{http_code}' > "$RESP"
  fi
  CODE=$(tail -n1 "$RESP"); BODY=$(sed '$d' "$RESP")
  echo "HTTP $CODE"; [ -n "$BODY" ] && echo "$BODY" | pretty || true
}

step "0. Health"
call GET /readyz

step "1. CREATE  POST /articles"
call POST /articles '{"title":"Hello Kubernetes","content":"Running on a 3-member MongoDB replica set","author":"raushan","tags":["k8s","mongodb"]}'
[ "$CODE" = 201 ] || { echo "create failed"; exit 1; }
ID=$(echo "$BODY" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')

step "2. LIST    GET /articles"
call GET /articles

step "3. READ    GET /articles/$ID"
call GET "/articles/$ID"

step "4. UPDATE  PUT /articles/$ID"
call PUT "/articles/$ID" '{"title":"Hello Kubernetes (updated)","tags":["k8s","mongodb","helm"]}'
[ "$CODE" = 200 ] || { echo "update failed"; exit 1; }

step "5. DELETE  DELETE /articles/$ID"
call DELETE "/articles/$ID"
[ "$CODE" = 204 ] || { echo "delete failed"; exit 1; }

step "6. READ after delete (expect 404)"
call GET "/articles/$ID"
[ "$CODE" = 404 ] && printf '\n\033[1;32mAll CRUD operations passed.\033[0m\n'
