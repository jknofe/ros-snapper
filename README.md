# ros-snapper

Docker tooling to build your own ROS 2 snaps with snapcraft. snapcraft
runs in destructive mode inside the container — no LXD, no Multipass,
no privileged mode required.

Supports the Jazzy, Humble, and Rolling distros. Tested on amd64 and
arm64 (including macOS Apple Silicon via Docker Desktop).

## Quick start

Put your snap recipe at `snaps/<my-recipe>/` so that
`snaps/<my-recipe>/snapcraft.yaml` (or
`snaps/<my-recipe>/snap/snapcraft.yaml`) exists. Then:

```bash
make build-image-jazzy             # one-time per distro
make start-builder-jazzy           # one-time per session
make pack-jazzy SNAP=my-recipe
```

The resulting `<name>_<version>_<arch>.snap` is written back to
`snaps/<my-recipe>/`. Substitute `humble` or `rolling` for `jazzy` to
build against those distros.

Run `make help` for a target listing.

## Dockerfiles

One Dockerfile per distro: `Dockerfile.jazzy`, `Dockerfile.humble`,
`Dockerfile.rolling`. Each layers snapcraft 9.x on top of
`ros:<distro>-ros-base` and bakes in the build environment.

## Requirements

- Docker (legacy `docker build` is fine, no buildx needed).
- Native hardware for each arch (no cross-compilation).

## How it works

Each Dockerfile adds snapcraft 9.x (not on PyPI, installed from GitHub)
on top of a `ros:<distro>-ros-base` image and sets
`SNAPCRAFT_BUILD_ENVIRONMENT=host`. A few things needed fixing:

- `snapd` is installed so `snap pack` works. The command is self-contained in the binary and doesn't need a running daemon, it just shells out to `mksquashfs`.
- The ROS apt source is deleted after package install so craft_parts can own it without a key conflict.
- `PYTHONPATH` is set to expose the host's dist-packages to the staged python3 that snapcraft downloads, which otherwise can't see catkin_pkg, empy, or numpy.
- Humble (Ubuntu 22.04) and Rolling (Ubuntu 24.04 with ROS deps) install old system packages that conflict with snapcraft's pydantic_core and pyparsing. Fixed by appending a sys.path reordering block to `/usr/lib/python3.X/sitecustomize.py` so the venv's packages take priority.
- snapcraft is run inside the container's writable layer (`/build/<recipe>`) by `scripts/pack-snap.sh`, not directly on the host bind mount. macOS Docker Desktop drops Linux user xattrs across the file-sharing bridge, and craft_parts writes those on every staged file. Building in-container sidesteps the issue and is a no-op on Linux hosts.

See [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md) for the full story.

## Multi-arch

The Dockerfiles work on both architectures unchanged. Run the same
steps on each host — the snap file name picks up the arch
automatically.

```
arm64 host                              amd64 host
make build-image-jazzy                  make build-image-jazzy
make pack-jazzy SNAP=my-recipe          make pack-jazzy SNAP=my-recipe
  -> my-recipe_X.Y_arm64.snap             -> my-recipe_X.Y_amd64.snap
```

## Examples

Three minimal in-tree recipes and two upstream Canonical recipes are
bundled to smoke-test the toolchain. They are not the point of this
repo — they're just realistic recipes to point it at.

### Bundled minimal publisher and subscriber

`snaps/ros2-test-pub-<distro>/` is a minimal `rclpy` node that
publishes:

- `/test/string`, `/test/int32`, `/test/twist` at 1 Hz (`std_msgs/String`, `Int32`, `geometry_msgs/Twist`)
- `/test/pointcloud` at 10 Hz — a 2048x2048 (`sensor_msgs/PointCloud2`, XYZ float32, ~48 MiB per message). Best-effort QoS to keep DDS retransmits sane.

`snaps/ros2-test-sub-<distro>/` is the matching subscriber. It listens
on all four topics and logs each message it receives (the pointcloud is
logged once per ~10 messages to avoid flooding the journal). Together
they form a complete pub/sub example to stress-test cross-snap ROS 2
communication on a single host.

```bash
make example-pack-jazzy-test-pub
make example-pack-jazzy-test-sub
# humble and rolling variants exist too
```

| Snap | Jazzy | Humble | Rolling |
|------|-------|--------|---------|
| `ros2-test-pub-<distro>` | 24 MB | ~32 MB | 24 MB |
| `ros2-test-sub-<distro>` | 18 MB | ~30 MB | 18 MB |

The pub snaps stage `python3-numpy` because the publisher builds the
pointcloud buffer with numpy. The subscriber doesn't touch numpy
itself and stays smaller.

Rolling packs fine but cannot connect to a content snap at runtime:
snapcraft 9.0 has no `ros2-rolling` extension and the Snap Store has no
`ros-rolling-ros-base` content snap yet.

### Canonical ros2-cli and ros2-nav2

```bash
make example-clone-jazzy              # clones the recipes into snaps/
make example-pack-jazzy-ros2-cli      # ~20 min, ~176 MB
make example-pack-jazzy-ros2-nav2     # ~40 min, ~769 MB
```

| Snap | Source |
|------|--------|
| `ros2-cli` | [canonical/ros2cli-snap](https://github.com/canonical/ros2cli-snap) |
| `ros2-nav2` | [canonical/ros2-nav2-snap](https://github.com/canonical/ros2-nav2-snap) |

Humble equivalents exist too (`make example-clone-humble`,
`make example-pack-humble-ros2-cli`, …). Canonical does not publish a
rolling branch.

### Smoke test: pub talking to sub (and to ros2-cli)

See [TEST_PLAN.md](TEST_PLAN.md) for installing the two bundled snaps
(and optionally the Canonical `ros2-cli`) on a Linux host and verifying
end-to-end topic flow.

## Cross-snap ROS 2 communication

This is a runtime concern, not a build concern, but worth noting if you
follow the smoke test:

All cooperating snaps need to run as the same user. FastDDS uses
shared-memory transport by default and SHM segments from one UID can't
be read by another, so a snap started by systemd (root) and a user-run
client won't talk to each other. The bundled `ros2-test-pub-*` and
`ros2-test-sub-*` snaps and the Canonical `ros2-cli` example all ship
`fastdds_no_shared_memory.xml` to force UDP instead.
