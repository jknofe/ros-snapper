# Build notes: ROS 2 snaps with snapcraft inside Docker

Collected pitfalls and fixes from building `ros2-cli` and `ros2-nav2` on arm64 and amd64.

## Setup

- OS: Ubuntu 24.04 (Noble)
- ROS: Jazzy Jalisco at `/opt/ros/jazzy`
- Python: 3.12
- Run as root - snapcraft destructive mode needs write access to `/var/lib/apt/lists/partial`

## Build results

| Arch | Snap | Size |
|------|------|------|
| arm64 | ros2-cli_0.32.1_arm64.snap | 168 MB |
| arm64 | ros2-nav2_1.3.11_arm64.snap | 661 MB |
| arm64 | ros2-test-pub_0.1_arm64.snap | ~18 MB |
| amd64 | ros2-cli_0.32.1_amd64.snap | 176 MB |
| amd64 | ros2-nav2_1.3.11_amd64.snap | 769 MB |
| amd64 | ros2-test-pub_0.1_amd64.snap | 18 MB |

## Container capability audit

The container runs without privileges, so there's no `CAP_SYS_ADMIN`, no `/dev/loop*`, no mount namespaces. snapd, LXD, and Multipass all fail. Only `SNAPCRAFT_BUILD_ENVIRONMENT=host` (destructive mode) works.

---

## Pitfalls

### gpg binary missing

craft_parts runs `gpg --dearmor` when installing repo keys. `gnupg-agent` doesn't provide `gpg` itself.

Fix: add `gpg` and `dirmngr` to the apt install.

---

### Conflicting Signed-By for the ROS apt repo

`ros:jazzy-ros-base` ships `/etc/apt/sources.list.d/ros2.sources` with the key as an inline PGP block. craft_parts writes its own source file pointing to a keyring file at a different path. apt 2.7+ rejects two different Signed-By values for the same URL:

```
E: Conflicting values set for option Signed-By regarding source http://packages.ros.org/ros2/ubuntu/ noble
```

Converting the inline block to a keyring file doesn't help - craft_parts still uses a different path. The only fix that works is deleting `ros2.sources` before snapcraft runs so craft_parts owns the repo entry entirely:

```dockerfile
RUN rm -f /etc/apt/sources.list.d/ros2.sources
```

---

### Staged python3 can't find catkin_pkg, empy, or numpy

The colcon plugin downloads `python3.12` as a stage-package. That binary has an isolated `sys.path` - it only sees its own staged filesystem, not the host's dist-packages.

During the build, CMake invokes this staged python3 for several things:
- `package_xml_2_cmake.py` imports `catkin_pkg`
- `rosidl_adapter` imports `em` (empy)
- `find_package(Python3 COMPONENTS NumPy)` needs numpy

All three are on the host at `/usr/lib/python3/dist-packages/` but the staged python3 can't see them.

Python prepends `PYTHONPATH` entries to `sys.path` regardless of how isolated the interpreter is. Setting it in the Dockerfile ENV fixes all three at once and is inherited by every subprocess through the entire colcon/CMake call tree:

```dockerfile
ENV PYTHONPATH=/usr/lib/python3/dist-packages
```

No changes to the snap recipe needed.

---

### Snapcraft extensions path

pip installs the extension data under `site-packages/extensions/` but snapcraft looks for it at `sys.prefix/share/snapcraft/extensions/`. Fix:

```bash
mkdir -p /opt/snapcraft/share/snapcraft/extensions
cp -r /opt/snapcraft/lib/python3.12/site-packages/extensions/ros2 \
      /opt/snapcraft/share/snapcraft/extensions/
```

---

### empy version

`rosidl_adapter` imports `em`. empy 4.x changed its API and ROS Jazzy isn't compatible with it yet. Pin to `empy<4.0` in the venv.

---

### Use ros:jazzy-ros-base, not osrf/ros:jazzy-desktop-full

`osrf/ros:jazzy-desktop-full` only has a `linux/amd64` image. On arm64 it fails with `exec format error`. `ros:jazzy-ros-base` is a proper multi-arch image.

---

### Run as root

snapcraft destructive mode calls `apt.cache.Cache(rootdir="/")` at the Python level (not a subprocess), which needs write access to `/var/lib/apt/lists/partial`. Non-root users get a permission error.

Also, `ros:jazzy-ros-base` already has a `ubuntu` user at UID 1000, so creating a builder user with the same ID fails. Just run as root.

---

### snap pack doesn't need a daemon

snapcraft calls `snap pack --check-skeleton <prime>` and `snap pack <prime> <output>`. Neither requires a running snapd daemon - both operations are self-contained in the `snap` binary.

`snap pack` validates the snap metadata in-process and then calls `mksquashfs` from PATH. It tries `/snap/snapd/current/usr/bin/mksquashfs` first, but since that path doesn't exist in Docker it falls back to the system `mksquashfs` from `squashfs-tools`.

`snap lint` doesn't exist as a subcommand in current snapd and snapcraft 9.x doesn't call it.

Installing the `snapd` package is enough - no daemon, no stub script needed. This is the same approach used by the official [canonical/snapcraft-rocks](https://github.com/canonical/snapcraft-rocks) image.

---

## Snap recipe

Using the unmodified canonical recipe from https://github.com/canonical/ros2cli-snap with one change: `source-branch: jazzy` instead of `source-tag: 0.32.1`.

The host packages needed during build (`catkin_pkg`, `empy`, `numpy`) are exposed via `PYTHONPATH` - the snap recipe itself is untouched.

---

## Environment variables

All of these are baked into the Dockerfile, no manual export needed in `docker exec` sessions:

```
SNAPCRAFT_BUILD_ENVIRONMENT=host
SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1
ROS_DISTRO=jazzy
ROS_VERSION=2
ROS_PYTHON_VERSION=3
AMENT_PREFIX_PATH=/opt/ros/jazzy
PYTHONPATH=/usr/lib/python3/dist-packages:/opt/ros/jazzy/lib/python3.12/site-packages
```

`LD_LIBRARY_PATH` is not set here because it contains an arch-specific multiarch tuple (`aarch64-linux-gnu` vs `x86_64-linux-gnu`). The entrypoint sources `setup.bash` which sets it correctly.

---

## Useful commands

```bash
# incremental rebuild after a partial failure
snapcraft clean <part-name>
snapcraft pack

# restart the builder after a Dockerfile change
docker rm -f snap-builder
docker build -t ros-snapcraft .
docker run -d --name snap-builder \
  -v $(pwd)/snaps:/workspace ros-snapcraft tail -f /dev/null
```

---

## Caveats

- Destructive mode has no isolation. Always `snapcraft clean` between full rebuilds.
- `cmd | tee log` hides the real exit code. Use `${PIPESTATUS[0]}` to catch snapcraft failures.
- ros2-nav2 is a large build and will OOM on low-memory machines. Reduce parallelism with `--parallel-workers 2` in colcon-cmake-args if needed.

---

## Cross-snap ROS 2 communication

Both snaps need to run as the same user. FastDDS uses shared-memory transport by default, and SHM segments are created with the publisher's UID - a subscriber under a different UID can't attach to them and the failure is silent. The UDP fallback doesn't activate automatically.

Both `ros2-cli` and `ros2-test-pub` ship `fastdds_no_shared_memory.xml` and set `FASTRTPS_DEFAULT_PROFILES_FILE` to it, forcing UDP.

### ros2 daemon

`ros2-cli` starts a background daemon on first use that caches DDS discovery. Short commands (`node list`, `topic list`) use its cached view. Long-running commands (`topic echo`) create a fresh DDS participant. If `topic echo` gets no output, try stopping the daemon first with `ros2 daemon stop`.

### ros2-test-pub design

Located in `snaps/ros2-test-pub/`. Uses `plugin: nil` with an override-build that installs two files: `pub.py` (a simple rclpy node publishing three topics at 1 Hz) and `launch.sh` (sets up PYTHONPATH and LD_LIBRARY_PATH from the content snap mount point). No compilation, builds in ~30 seconds.

`ARCH_TRIPLET` in `launch.sh` is auto-detected at runtime via `dpkg-architecture`.
