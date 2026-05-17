#!/bin/bash
# Pack a snap inside the container's local filesystem and copy the resulting
# .snap back to the host bind mount.
#
# Why this exists: craft_parts writes user.* extended attributes on every
# staged file. Linux native filesystems handle this, but the macOS Docker
# Desktop bind-mount bridge does not. Running the build under /build (which
# lives on the container's writable layer) keeps the xattrs off the host fs.
#
# Usage: pack-snap <recipe-dir>
#   recipe-dir is the subdirectory under /workspace that contains the
#   snapcraft.yaml (or snap/snapcraft.yaml). The .snap is written back to
#   that same directory on the host.

set -e

if [ $# -ne 1 ]; then
    echo "usage: pack-snap <recipe-dir>" >&2
    exit 2
fi

recipe="$1"
src="/workspace/$recipe"
build="/build/$recipe"

if [ ! -f "$src/snapcraft.yaml" ] && [ ! -f "$src/snap/snapcraft.yaml" ]; then
    echo "no snapcraft.yaml under $src" >&2
    exit 1
fi

mkdir -p /build
rm -rf "$build"
cp -a "$src" "$build"
# Drop any artefacts that may have leaked back from a prior interrupted run.
rm -rf "$build/parts" "$build/stage" "$build/prime" "$build/overlay" "$build/.craft"

cd "$build"
set +e
snapcraft pack 2>&1 | tee "$src/build.log"
rc=${PIPESTATUS[0]}
set -e

# Copy any produced .snap files back to the host. Glob may be empty on failure.
shopt -s nullglob
for snap in "$build"/*.snap; do
    cp -f "$snap" "$src/"
done

exit "$rc"
