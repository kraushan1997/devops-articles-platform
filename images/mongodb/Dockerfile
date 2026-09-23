# MongoDB image used by the Helm chart.
# Based on the official image, with the replica-set bootstrap script baked in so
# the chart does not need a ConfigMap-mounted script, and so the exact image that
# runs in the cluster is versioned and pushed to our own registry (GHCR).
FROM mongo:8.0

LABEL org.opencontainers.image.source="https://github.com/kraushan1997/devops-articles-platform" \
      org.opencontainers.image.description="MongoDB 8.0 + replica-set bootstrap script"

COPY --chmod=0755 rs-init.sh /usr/local/bin/rs-init.sh

# The official image already runs mongod as the 'mongodb' user (uid 999)
# when started via its entrypoint; the chart also enforces runAsUser: 999.
