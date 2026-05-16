#!/bin/bash
set -e

source /opt/ros/${ROS_DISTRO}/setup.bash

export SNAPCRAFT_BUILD_ENVIRONMENT=host
export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1

if [ -f /workspace/snap/snapcraft.yaml ]; then
    cd /workspace
else
    echo "No snapcraft.yaml found at /workspace/snap/snapcraft.yaml"
    echo "Mount a snap project into /workspace or use: docker run ... bash"
    exec "$@"
    exit 0
fi

exec snapcraft pack
