# ros-snapper

Docker tooling to build your own ROS 2 snaps with snapcraft. snapcraft
runs in destructive mode inside the container — no LXD, no Multipass,
no privileged mode required.

Supports the Jazzy and Humble distros. Tested on amd64 and arm64
(including macOS Apple Silicon via Docker Desktop).

## Quick start

Lay your recipe out as a colcon workspace under `snaps/<my-recipe>/`:

```
snaps/my-recipe/
  snapcraft.yaml
  src/
    my_python_pkg/        # ament_python
      package.xml
      setup.cfg
      setup.py
      resource/my_python_pkg
      my_python_pkg/
        __init__.py
        node.py
    my_cpp_pkg/           # ament_cmake
      package.xml
      CMakeLists.txt
      include/my_cpp_pkg/
      src/
```

In `snapcraft.yaml` use the colcon plugin and the matching ROS 2
extension. Then:

```bash
make build-image-jazzy             # one-time per distro
make start-builder-jazzy           # one-time per session
make pack-jazzy SNAP=my-recipe
```

The resulting `<name>_<version>_<arch>.snap` is written back to
`snaps/<my-recipe>/`. Substitute `humble` for `jazzy` to build against
Humble.

Run `make help` for a target listing.

## Dockerfiles

One Dockerfile per distro: `Dockerfile.jazzy`, `Dockerfile.humble`.
Each layers snapcraft 9.x on top of `ros:<distro>-ros-base` and bakes
in the build environment.

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
- Humble (Ubuntu 22.04) installs old system packages that conflict with snapcraft's pydantic_core and pyparsing. Fixed by appending a sys.path reordering block to `/usr/lib/python3.X/sitecustomize.py` so the venv's packages take priority.
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

Bundled with the repo to smoke-test the toolchain. Not the point of
this repo — just realistic recipes to point it at.

### Bundled minimal publisher and subscriber

`snaps/ros2-test-pub-<distro>/` and `snaps/ros2-test-sub-<distro>/`
are each a colcon workspace with two ROS 2 packages:

- `test_{pub,sub}_simple` (Python, ament_python) — publishes/
  subscribes `/test/string`, `/test/int32`, `/test/twist` at 1 Hz
  (`std_msgs/String`, `Int32`, `geometry_msgs/Twist`).
- `test_{pub,sub}_pointcloud` (C++, ament_cmake) — publishes/
  subscribes a 2048x2048 `sensor_msgs/PointCloud2` on
  `/test/pointcloud` at 10 Hz, ~48 MiB per message, best-effort QoS.

Each snap exposes two apps (`simple` and `pointcloud`) that map to
those two binaries. The C++ side is in C++ because the publisher
needs to keep up with ~480 MB/s of payload at 10 Hz — that's
uncomfortable in Python.

```bash
make example-pack-jazzy-test-pub
make example-pack-jazzy-test-sub
# humble variants exist too
```

Approximate snap sizes (arm64, the colcon plugin + ros2 extension
auto-stage rclpy/rclcpp/ament packages):

| Snap | Jazzy | Humble |
|------|-------|--------|
| `ros2-test-pub-<distro>` | ~95 MB | ~95 MB |
| `ros2-test-sub-<distro>` | ~95 MB | ~95 MB |

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
`make example-pack-humble-ros2-cli`, …).

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
