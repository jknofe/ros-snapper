#!/bin/bash
# Smoke-test the jazzy pub+sub snaps without snapd.
#
# Unsquashes both snaps, sources the colcon install spaces, and runs
# all four nodes (simple pub/sub + pointcloud pub/sub) for a short time.
# Subscriber output appears in the terminal so you can confirm messages flow.
#
# Requires snap files to exist (build them first with make example-pack-jazzy-test-*).
# Run inside the jazzy builder container: docker exec snap-builder-jazzy test-snap

set -euo pipefail

PUB_DIR=/workspace/ros2-test-pub-jazzy
SUB_DIR=/workspace/ros2-test-sub-jazzy
WORK=/tmp/snap-test

cleanup() {
    kill "${PIDS[@]}" 2>/dev/null || true
    wait 2>/dev/null || true
}

# --- find snaps ---
PUB_SNAP=$(ls "$PUB_DIR"/*.snap 2>/dev/null | head -1 || true)
SUB_SNAP=$(ls "$SUB_DIR"/*.snap 2>/dev/null | head -1 || true)

if [ -z "$PUB_SNAP" ] || [ -z "$SUB_SNAP" ]; then
    cat >&2 <<'EOF'
ERROR: snap files not found. Build them first:
  make example-pack-jazzy-test-pub
  make example-pack-jazzy-test-sub
EOF
    exit 1
fi

echo "pub snap: $PUB_SNAP"
echo "sub snap: $SUB_SNAP"

# --- unsquash ---
echo ""
echo "Unsquashing snaps into $WORK..."
rm -rf "$WORK"
mkdir -p "$WORK"
unsquashfs -q -d "$WORK/pub" "$PUB_SNAP"
unsquashfs -q -d "$WORK/sub" "$SUB_SNAP"

# --- environment ---
# setup.bash chain-sources /opt/ros/jazzy (hardcoded, exists in this container)
# then uses dirname to find its own prefix — works regardless of where we unsquashed.
# The colcon setup scripts reference COLCON_TRACE and similar vars without defaults,
# so drop -u while sourcing them.
set +u
# shellcheck disable=SC1091
source "$WORK/pub/opt/ros/snap/setup.bash"
# Add sub packages without re-loading jazzy.
# shellcheck disable=SC1091
source "$WORK/sub/opt/ros/snap/local_setup.bash"
set -u

# Force UDP; no shared memory in a container (and not needed between processes that
# share a pid namespace, but explicit is better).
export FASTRTPS_DEFAULT_PROFILES_FILE="$WORK/pub/usr/share/fastdds_no_shared_memory.xml"

# Executables
PUB_SIMPLE="$WORK/pub/opt/ros/snap/lib/test_pub_simple/pub_simple"
SUB_SIMPLE="$WORK/sub/opt/ros/snap/lib/test_sub_simple/sub_simple"
PUB_PC="$WORK/pub/opt/ros/snap/lib/test_pub_pointcloud/pointcloud_publisher"
SUB_PC="$WORK/sub/opt/ros/snap/lib/test_sub_pointcloud/pointcloud_subscriber"

PIDS=()
trap cleanup EXIT

# --- run ---
# Start subscribers first so they are ready before the publishers announce.
echo ""
echo "=== Starting subscribers ==="
"$SUB_SIMPLE" &
PIDS+=($!)
"$SUB_PC" &
PIDS+=($!)

sleep 2

echo ""
echo "=== Starting publishers ==="
"$PUB_SIMPLE" &
PIDS+=($!)
"$PUB_PC" &
PIDS+=($!)

echo ""
echo "=== Running for 12 seconds ==="
echo "    simple:     expect ~12 lines from the string/int32/twist subscriber"
echo "    pointcloud: expect ~12 lines (every 10th of 120 messages at 10 Hz)"
echo ""
sleep 12

echo ""
echo "=== Stopping ==="
cleanup
trap - EXIT
echo "Done."
