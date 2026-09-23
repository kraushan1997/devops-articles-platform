#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Replica-set + user bootstrap for the MongoDB StatefulSet.
#
# Runs as a lightweight sidecar in EVERY mongod pod (same network namespace, so
# it can use MongoDB's "localhost exception" before any user exists). Only
# ordinal 0 acts; the other pods just idle. It is idempotent: on every restart
# it re-checks state and only does what is missing.
#
#   1. wait for the local mongod to answer ping
#   2. if root auth does not work yet -> rs.initiate() over localhost, wait for
#      PRIMARY, create the root user (localhost exception closes after this)
#   3. with root auth: ensure the app user (readWrite on $APP_DB) and the metrics
#      user (clusterMonitor, for the Prometheus exporter) exist with the
#      passwords currently in the Secret (rotating the Secret rotates the user)
#   4. sleep forever (container must keep running as a sidecar)
#
# Required env: STATEFULSET_NAME SERVICE_NAME NAMESPACE MONGO_ROOT_PASSWORD
#               APP_USER APP_PASSWORD APP_DB METRICS_PASSWORD
# Optional env: REPLICA_SET(rs0) REPLICAS(3) CLUSTER_DOMAIN(cluster.local)
# -----------------------------------------------------------------------------
set -euo pipefail

REPLICA_SET="${REPLICA_SET:-rs0}"
REPLICAS="${REPLICAS:-3}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
ordinal="${HOSTNAME##*-}"

log()  { echo "[rs-init] $(date -u +%FT%TZ) $*"; }
idle() { log "$*; idling"; exec sleep infinity; }
member() { echo "${STATEFULSET_NAME}-$1.${SERVICE_NAME}.${NAMESPACE}.svc.${CLUSTER_DOMAIN}:27017"; }

log "waiting for local mongod"
until mongosh --quiet --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1; do sleep 2; done

[ "$ordinal" = "0" ] || idle "ordinal ${ordinal} is not the bootstrap member"

ROOT_AUTH=(-u root -p "$MONGO_ROOT_PASSWORD" --authenticationDatabase admin)

if ! mongosh --quiet "${ROOT_AUTH[@]}" --eval 'db.adminCommand("ping").ok' >/dev/null 2>&1; then
  log "root auth not available -> first-time bootstrap via localhost exception"

  members="["
  for i in $(seq 0 $((REPLICAS - 1))); do
    prio=1; [ "$i" = "0" ] && prio=2          # prefer pod-0 as primary when healthy
    members+="{_id:${i},host:'$(member "$i")',priority:${prio}},"
  done
  members="${members%,}]"

  # rs.initiate needs every listed member reachable -> retry until they are up
  until mongosh --quiet --eval "
      try { rs.status().ok; print('already-initiated') }
      catch (e) {
        if (e.codeName !== 'NotYetInitialized') throw e;
        rs.initiate({_id:'${REPLICA_SET}', members:${members}}); print('initiated')
      }"; do
    log "rs.initiate not possible yet (members not reachable?), retrying"; sleep 5
  done

  log "waiting to become PRIMARY"
  until [ "$(mongosh --quiet --eval 'db.hello().isWritablePrimary')" = "true" ]; do sleep 2; done

  mongosh --quiet admin --eval "
    db.createUser({user:'root', pwd:process.env.MONGO_ROOT_PASSWORD, roles:['root']})"
  log "root user created"
fi

# Connect via the replica-set seed list so user writes go to the current PRIMARY,
# which may not be pod-0 after a failover.
seeds=""
for i in $(seq 0 $((REPLICAS - 1))); do seeds+="$(member "$i"),"; done
RS_HOST="${REPLICA_SET}/${seeds%,}"

log "ensuring application and metrics users"
until mongosh --quiet --host "$RS_HOST" "${ROOT_AUTH[@]}" --eval '
  function ensure(dbName, user, pwd, roles) {
    const d = db.getSiblingDB(dbName);
    if (d.getUser(user)) { d.updateUser(user, {pwd: pwd, roles: roles}); print("updated " + user); }
    else { d.createUser({user: user, pwd: pwd, roles: roles}); print("created " + user); }
  }
  ensure(process.env.APP_DB, process.env.APP_USER, process.env.APP_PASSWORD,
         [{role: "readWrite", db: process.env.APP_DB}]);
  ensure("admin", "metrics", process.env.METRICS_PASSWORD,
         [{role: "clusterMonitor", db: "admin"}, {role: "read", db: "local"}]);
'; do log "user sync failed, retrying"; sleep 5; done

idle "bootstrap complete"
