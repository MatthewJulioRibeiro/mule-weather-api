#!/bin/sh
# Mule Enterprise/Community Standalone logs to a file, not stdout by default.
# Start it in the background, tail its log to stdout for `docker logs`, and
# make sure the container exits if the Mule process dies.
set -e

mkdir -p /opt/mule/logs
touch /opt/mule/logs/mule_ee.log

/opt/mule/bin/mule &
MULE_PID=$!

tail -F /opt/mule/logs/mule_ee.log &

# Ships each new structured access-log line to the observability stack's
# ingest endpoint, in addition to it staying in the local rotated file.
# Only forwards lines written from here on (-n0), so a container restart
# doesn't re-ship old history. INGEST_URL/INGEST_TOKEN are optional -- the
# app runs fine without them, it just stays local-only.
if [ -n "$INGEST_URL" ] && [ -n "$INGEST_TOKEN" ]; then
  ( tail -F -n0 /opt/mule/logs/weather-api-access.json.log 2>/dev/null | while IFS= read -r line; do
      curl -s -o /dev/null --max-time 5 -X POST "$INGEST_URL" \
        -H "Content-Type: application/json" \
        -H "X-Ingest-Token: $INGEST_TOKEN" \
        -d "$line" || true
    done ) &
fi

wait "$MULE_PID"
