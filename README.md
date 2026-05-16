# ros-snapper

Docker-based build environment for packaging **ROS 2 Jazzy** snaps on native **arm64** and **amd64** hardware.

Produces canonical snap packages without a privileged container or LXD — snapcraft runs in destructive mode inside a purpose-built Docker image.

## What's in the box

| Snap | Source | arm64 | amd64 |
|------|--------|-------|-------|
| `ros2-cli` | [canonical/ros2cli-snap@jazzy](https://github.com/canonical/ros2cli-snap) | 168 MB | 176 MB |
| `ros2-nav2` | [canonical/ros2-nav2-snap@jazzy](https://github.com/canonical/ros2-nav2-snap) | 661 MB | 769 MB |
| `ros2-test-pub` | [`snaps/ros2-test-pub/`](snaps/ros2-test-pub/) | — | 18 MB |

`ros2-test-pub` is a minimal publisher snap used to verify cross-snap ROS 2 communication after installation.

## Prerequisites

- Docker (any version; legacy `docker build` is fine — no buildx needed)
- Native hardware for each target arch (arm64 host for arm64 snaps, amd64 host for amd64 snaps)

## Quick start

```bash
# 1. Build the snapcraft image (once per arch, ~5 min)
make build-image

# 2. Clone the upstream snap recipes
make clone-snaps          # creates snaps/ros2cli-snap/ and snaps/ros2-nav2-snap/

# 3. Start the build container
make start-builder

# 4. Build the snaps (long — colcon downloads all ROS deps)
make build-ros2-cli       # ~20 min first run
make build-ros2-nav2      # ~40 min first run
make build-test-pub       # ~1 min (no compilation)

# 5. Install and test
sudo snap install --dangerous snaps/ros2cli-snap/ros2-cli_*.snap
sudo snap install --dangerous --devmode snaps/ros2-test-pub/ros2-test-pub_*.snap
sudo snap connect ros2-test-pub:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base

ros2-test-pub.pub &
ros2-cli.ros2 node list
ros2-cli.ros2 topic echo /test/string --once
ros2-cli.ros2 topic hz /test/twist
```

## Parallel arm64 / amd64 builds

The Dockerfile is architecture-agnostic — `ros:jazzy-ros-base` is a multi-arch image. Run the same commands on each host:

```
arm64 host                          amd64 host
──────────────────────────────────  ──────────────────────────────────
make build-image                    make build-image
make clone-snaps                    make clone-snaps
make start-builder                  make start-builder
make build-ros2-cli   → *_arm64     make build-ros2-cli   → *_amd64
make build-ros2-nav2  → *_arm64     make build-ros2-nav2  → *_amd64
make build-test-pub   → *_arm64     make build-test-pub   → *_amd64
```

## How it works

`ros:jazzy-ros-base` gives us a full ROS 2 Jazzy environment. On top of it, the Dockerfile:

1. Installs system packages needed by snapcraft (gpg, squashfs-tools, snapd, python3-apt, …)
2. Removes the conflicting ROS apt source (`ros2.sources`) so craft_parts can own it
3. Installs snapcraft 9.x from GitHub (PyPI only has 4.x)
4. Sets `SNAPCRAFT_BUILD_ENVIRONMENT=host` to use destructive mode

`snap pack` (called internally by snapcraft) is self-contained in the `snap` binary and needs no running daemon — it shells out to `mksquashfs` from PATH. Installing the `snapd` package is sufficient.

See [`KNOWLEDGE_BASE.md`](KNOWLEDGE_BASE.md) for the full list of pitfalls and fixes.

## Snap-to-snap communication

Cross-snap ROS 2 topic echo works when both snaps run as the **same user**. Key rule:

- **FastDDS shared-memory (SHM)** transport silently fails between different UIDs (e.g. a root systemd service and a user-space process)
- Both snaps ship `fastdds_no_shared_memory.xml` (UDP-only transport) to avoid SHM negotiation issues

The `ros2-test-pub` snap demonstrates this: launched as a user process, it publishes three topics that `ros2-cli.ros2 topic echo` can subscribe to immediately.
