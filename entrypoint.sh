#!/bin/bash
set -e

source /opt/ros/jazzy/setup.bash

export SNAPCRAFT_BUILD_ENVIRONMENT=host
export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1
# Expose host dist-packages to the staged python3 that the colcon plugin
# downloads as a stage-package. Its sys.path is isolated, so catkin_pkg,
# em (empy), and numpy are invisible without this.
export PYTHONPATH=/usr/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}

if [ -f /workspace/snap/snapcraft.yaml ]; then
    cd /workspace
else
    echo "No snapcraft.yaml found at /workspace/snap/snapcraft.yaml"
    echo "Mount a snap project into /workspace or use: docker run ... bash"
    exec "$@"
    exit 0
fi

exec snapcraft pack
