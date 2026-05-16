# ros-snapper

Builds ROS 2 Jazzy snaps inside Docker using snapcraft in destructive mode. No LXD, no privileged container needed.

Tested on Ubuntu 24.04, amd64 and arm64.

## Snaps

| Snap | Source | arm64 | amd64 |
|------|--------|-------|-------|
| `ros2-cli` | [canonical/ros2cli-snap@jazzy](https://github.com/canonical/ros2cli-snap) | 168 MB | 176 MB |
| `ros2-nav2` | [canonical/ros2-nav2-snap@jazzy](https://github.com/canonical/ros2-nav2-snap) | 661 MB | 769 MB |
| `ros2-test-pub` | [`snaps/ros2-test-pub/`](snaps/ros2-test-pub/) | - | 18 MB |

`ros2-test-pub` is a minimal publisher used to verify cross-snap ROS 2 communication.

## Requirements

- Docker (legacy `docker build` is fine, no buildx needed)
- Native hardware for each arch (no cross-compilation)

## Usage

```bash
# build the image once
make build-image

# clone upstream snap recipes
make clone-snaps

# start the build container
make start-builder

# build snaps (first run downloads all ROS deps - takes a while)
make build-ros2-cli       # ~20 min
make build-ros2-nav2      # ~40 min
make build-test-pub       # ~1 min
```

Install and smoke-test:

```bash
sudo snap install --dangerous snaps/ros2cli-snap/ros2-cli_*.snap
sudo snap install --dangerous --devmode snaps/ros2-test-pub/ros2-test-pub_*.snap
sudo snap connect ros2-test-pub:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base

ros2-test-pub.pub &
ros2-cli.ros2 topic list
ros2-cli.ros2 topic echo /test/string --once
```

## Multi-arch

The Dockerfile works on both architectures unchanged. Run the same steps on each host:

```
arm64 host                       amd64 host
make build-image                 make build-image
make build-ros2-cli  -> _arm64   make build-ros2-cli  -> _amd64
make build-ros2-nav2 -> _arm64   make build-ros2-nav2 -> _amd64
```

## How it works

The Dockerfile adds snapcraft 9.x (not on PyPI, installed from GitHub) on top of `ros:jazzy-ros-base` and sets `SNAPCRAFT_BUILD_ENVIRONMENT=host`. A few things needed fixing:

- `snapd` is installed so `snap pack` works. The command is self-contained in the binary and doesn't need a running daemon, it just shells out to `mksquashfs`.
- The ROS apt source is deleted after package install so craft_parts can own it without a key conflict.
- `PYTHONPATH` is set to expose the host's dist-packages to the staged python3 that snapcraft downloads, which otherwise can't see catkin_pkg, empy, or numpy.

See [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md) for the full story.

## Cross-snap communication

Both snaps need to run as the same user. FastDDS uses shared memory transport by default and SHM segments from one UID can't be read by another, so a snap started by systemd (root) and `ros2-cli` run as a user won't talk to each other. Both snaps ship `fastdds_no_shared_memory.xml` to force UDP instead.
