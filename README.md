# ros-snapper

Builds ROS 2 snaps inside Docker using snapcraft in destructive mode. No LXD, no privileged container needed.

Supports Jazzy, Humble, and Rolling. Tested on amd64 (arm64 tested for Jazzy).

## Dockerfiles

One Dockerfile per distro: `Dockerfile.jazzy`, `Dockerfile.humble`, `Dockerfile.rolling`.

## Snaps

| Snap | Source | Jazzy | Humble | Rolling |
|------|--------|-------|--------|---------|
| `ros2-cli` | [canonical/ros2cli-snap](https://github.com/canonical/ros2cli-snap) | 176 MB | 180 MB | - |
| `ros2-nav2` | [canonical/ros2-nav2-snap](https://github.com/canonical/ros2-nav2-snap) | 769 MB | - | - |
| `ros2-test-pub` | [`snaps/ros2-test-pub*/`](snaps/) | 18 MB | 30 MB | 18 MB |

`ros2-test-pub` variants are minimal publishers used to verify cross-snap ROS 2 communication.

Rolling builds work but runtime testing is blocked: snapcraft 9.0 has no `ros2-rolling` extension and the Snap Store has no `ros-rolling-ros-base` content snap. `ros2cli-snap` also has no rolling branch. `ros2-test-pub-rolling` packs fine but cannot connect to a content snap at runtime.

## Requirements

- Docker (legacy `docker build` is fine, no buildx needed)
- Native hardware for each arch (no cross-compilation)

## Usage

```bash
# build the image for a distro
make build-image-jazzy     # or -humble / -rolling

# clone upstream snap recipes
make clone-snaps-jazzy

# start the build container
make start-builder-jazzy

# build snaps
make build-jazzy-ros2-cli    # ~20 min
make build-jazzy-ros2-nav2   # ~40 min
make build-jazzy-test-pub    # ~1 min

# or build everything at once
make all-jazzy
make all-humble
```

Install and smoke-test:

```bash
sudo snap install --dangerous snaps/ros2cli-snap-jazzy/ros2-cli_*.snap
sudo snap install --dangerous --devmode snaps/ros2-test-pub/ros2-test-pub_*.snap
sudo snap connect ros2-test-pub:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base

ros2-test-pub.pub &
ros2-cli.ros2 topic list
ros2-cli.ros2 topic echo /test/string --once
```

## Multi-arch

The Dockerfiles work on both architectures unchanged. Run the same steps on each host:

```
arm64 host                             amd64 host
make build-image-jazzy                 make build-image-jazzy
make build-jazzy-ros2-cli  -> _arm64  make build-jazzy-ros2-cli  -> _amd64
```

## How it works

Each Dockerfile adds snapcraft 9.x (not on PyPI, installed from GitHub) on top of a `ros:X-ros-base` image and sets `SNAPCRAFT_BUILD_ENVIRONMENT=host`. A few things needed fixing:

- `snapd` is installed so `snap pack` works. The command is self-contained in the binary and doesn't need a running daemon, it just shells out to `mksquashfs`.
- The ROS apt source is deleted after package install so craft_parts can own it without a key conflict.
- `PYTHONPATH` is set to expose the host's dist-packages to the staged python3 that snapcraft downloads, which otherwise can't see catkin_pkg, empy, or numpy.
- Humble (Ubuntu 22.04) and Rolling (Ubuntu 24.04 with ROS deps) install old system packages that conflict with snapcraft's pydantic_core and pyparsing. Fixed by appending a sys.path reordering block to `/usr/lib/python3.X/sitecustomize.py` so the venv's packages take priority.

See [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md) for the full story.

## Cross-snap communication

Both snaps need to run as the same user. FastDDS uses shared memory transport by default and SHM segments from one UID can't be read by another, so a snap started by systemd (root) and `ros2-cli` run as a user won't talk to each other. Both snaps ship `fastdds_no_shared_memory.xml` to force UDP instead.
