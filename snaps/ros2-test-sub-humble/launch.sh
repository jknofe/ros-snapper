#!/bin/bash
set -e

UNDERLAY="$SNAP/opt/ros/underlay_ws"
ARCH_TRIPLET="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || uname -m | sed 's/aarch64/aarch64-linux-gnu/;s/x86_64/x86_64-linux-gnu/')"

# Source ROS underlay if present (sets AMENT_PREFIX_PATH etc.)
if [ -f "$UNDERLAY/opt/ros/humble/local_setup.bash" ]; then
    # shellcheck disable=SC1090
    source "$UNDERLAY/opt/ros/humble/local_setup.bash"
fi

export PYTHONPATH="$UNDERLAY/opt/ros/humble/lib/python3/dist-packages:$UNDERLAY/usr/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
export LD_LIBRARY_PATH="$UNDERLAY/opt/ros/humble/lib:$UNDERLAY/usr/lib/$ARCH_TRIPLET:$UNDERLAY/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export FASTRTPS_DEFAULT_PROFILES_FILE="$SNAP/usr/share/fastdds_no_shared_memory.xml"
export ROS_DISTRO=humble
export ROS_VERSION=2
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

exec "$SNAP/usr/bin/python3" "$SNAP/usr/share/sub.py"
