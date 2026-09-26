#!/usr/bin/env bash
# High-availability check on EKS: keep calling the API through the ALB while the
# MongoDB PRIMARY pod is deleted, then report how many requests failed and which
# member took over.
#
#   ./scripts/failover-test.sh            # 60 s of traffic, primary killed at t=10 s
set -uo pipefail
DURATION="${DURATION:-60}"
ALB=$(kubectl -n articles get ingress articles-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
BASE="http://$ALB"
primary() {
  kubectl -n articles exec mongodb-0 -c rs-init -- bash -c \
    'mongosh --quiet -u root -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.hello().primary"' 2>/dev/null \
    | cut -d. -f1
}
OUT=$(mktemp)
BEFORE=$(primary)
echo "API: $BASE"
echo "primary before: $BEFORE"

end=$((SECONDS + DURATION)); killed=0
while [ $SECONDS -lt $end ]; do
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -X POST "$BASE/articles" \
    -H 'Content-Type: application/json' \
    -d '{"title":"failover probe","content":"written during primary loss","author":"failover-test"}')
  echo "$(date +%T) POST $code" >> "$OUT"
  if [ $killed = 0 ] && [ $((end - SECONDS)) -le $((DURATION - 10)) ]; then
    echo "$(date +%T) deleting primary pod $BEFORE"
    kubectl -n articles delete pod "$BEFORE" --wait=false >/dev/null; killed=1
  fi
  sleep 0.5
done

sleep 5
echo "primary after:  $(primary)"
echo "requests by HTTP status:"
awk '{print $3}' "$OUT" | sort | uniq -c
echo "non-201 responses (if any):"
grep -v ' 201$' "$OUT" || echo "  none"

echo "elections seen in the mongod logs:"
for p in mongodb-0 mongodb-1 mongodb-2; do
  echo "== $p"
  kubectl -n articles logs "$p" -c mongod --since=15m 2>/dev/null \
    | jq -rR 'fromjson? | select(.msg|test("Transition to primary complete|Stepping down from primary|Starting an election")) | "\(.t["$date"]) \(.msg)"'
done

# tidy up the probe documents
for id in $(curl -s "$BASE/articles?limit=500" | python3 -c 'import sys,json;[print(a["id"]) for a in json.load(sys.stdin) if a.get("author")=="failover-test"]'); do
  curl -s -o /dev/null -X DELETE "$BASE/articles/$id"
done
rm -f "$OUT"
