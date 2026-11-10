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

wait "$MULE_PID"
