#!/bin/bash
# Set up the ROS environment for whatever command runs inside the container.
# The build flow is driven from outside via "docker exec ... pack-snap <recipe>"
# (see scripts/pack-snap.sh and the Makefile), so this entrypoint stays small.
set -e

source /opt/ros/${ROS_DISTRO}/setup.bash

exec "$@"
