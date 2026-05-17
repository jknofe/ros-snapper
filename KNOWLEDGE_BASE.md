# Build notes: ROS 2 snaps with snapcraft inside Docker

Collected pitfalls and fixes from getting snapcraft 9.x to run cleanly inside Docker on top of `ros:<distro>-ros-base`, for Jazzy, Humble, and Rolling. The sizes below are from the example recipes bundled with this repo (`snaps/ros2-test-pub-*`) and the upstream Canonical recipes used as smoke tests (`ros2-cli`, `ros2-nav2`).

## Setup

- OS: Ubuntu 24.04 (Noble) for Jazzy and Rolling containers; Ubuntu 22.04 (Jammy) for Humble
- Run as root - snapcraft destructive mode needs write access to `/var/lib/apt/lists/partial`
- Dockerfile per distro: `Dockerfile.jazzy`, `Dockerfile.humble`, `Dockerfile.rolling`

## Build results

| Distro | Snap | amd64 size |
|--------|------|-----------|
| Jazzy | ros2-cli_0.32.1_amd64.snap | 176 MB |
| Jazzy | ros2-nav2_1.3.11_amd64.snap | 769 MB |
| Jazzy | ros2-test-pub-jazzy_0.1_amd64.snap | 18 MB |
| Humble | ros2-cli_0.18.11_amd64.snap | 180 MB |
| Humble | ros2-test-pub-humble_0.1_amd64.snap | ~30 MB |
| Rolling | ros2-test-pub-rolling_0.1_amd64.snap | 18 MB |

Rolling has no snapcraft extension and no store content snap yet. test-pub builds but can't be tested at runtime.

arm64 results: ros2-cli 168 MB, ros2-nav2 661 MB, ros2-test-pub-jazzy 18 MB (all Jazzy).

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

### System packages conflicting with snapcraft's venv (Humble and Rolling)

The snapcraft venv uses `--system-site-packages` so that python3-apt (a C extension) is accessible. When `PYTHONPATH` points to the system dist-packages, old system packages get prepended to sys.path and override the venv's pinned versions:

- Humble (Ubuntu 22.04): `pyparsing 2.4.7` is too old for craft_application's launchpadlib, which calls `pp.Word(...).set_name(...)` (API added in pyparsing 3.1).
- Rolling: `ros:rolling-ros-base` installs an old `typing_extensions` that doesn't have `Sentinel` (added in 4.12). pydantic_core needs it.

The fix: append to the system `sitecustomize.py` so the venv's site-packages come first in sys.path when running snapcraft. The appended code checks for the venv path in sys.path and only runs when the venv Python is active - it's a no-op for the staged python3, which has a completely different sys.path.

```dockerfile
# In Dockerfile.humble (Python 3.10)
RUN printf '\nimport sys as _sys\n_sp = "/opt/snapcraft/lib/python3.10/site-packages"\nif _sp in _sys.path:\n    _sys.path.remove(_sp)\n    _sys.path.insert(0, _sp)\n' \
    >> /usr/lib/python3.10/sitecustomize.py
```

The key reason this works: `/usr/lib/python3.X/sitecustomize.py` is read by the system Python, which is what the snapcraft venv's Python is based on. The staged python3 that the colcon plugin downloads ALSO reads this file, but the `if _sp in _sys.path:` guard makes it a no-op there since the venv path is not in the staged python3's sys.path.

---

### Snapcraft extensions path

pip installs the extension data under `site-packages/extensions/` but snapcraft looks for it at `sys.prefix/share/snapcraft/extensions/`. Fix:

```bash
mkdir -p /opt/snapcraft/share/snapcraft/extensions
cp -r /opt/snapcraft/lib/python3.12/site-packages/extensions/ros2 \
      /opt/snapcraft/share/snapcraft/extensions/
```

For Humble (python3.10), the path is `lib/python3.10/site-packages/extensions/ros2`.

---

### empy version

`rosidl_adapter` imports `em`. empy 4.x changed its API and ROS isn't compatible with it yet. Pin to `empy<4.0` in the venv.

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

### macOS bind mounts can't hold Linux user xattrs

craft_parts tags every staged file with a `user.craft_parts.origin_stage_package` xattr to track which stage-package contributed it. Linux native filesystems handle this fine, but Docker Desktop on macOS bridges bind mounts to APFS through gRPC-FUSE/VirtioFS, which silently rejects Linux user xattrs. The first extracted shared library crashes the build:

```
Unable to write extended attribute.
Failed to write attribute 'user.craft_parts.origin_stage_package' on
'/workspace/.../libssl.so.3'
```

Fix: run snapcraft inside the container's writable layer (under `/build/<recipe>`) and copy only the resulting `.snap` back to the host mount. `scripts/pack-snap.sh` does this and every Makefile build target invokes it via `docker exec snap-builder-<distro> pack-snap <recipe-dir>`.

Linux hosts don't need the workaround (the bind mount supports xattrs natively), but the helper has zero cost there and keeps a single code path for both.

---

### Rolling has no snap packaging infrastructure yet

snapcraft 9.0.0 has no `ros2-rolling-*` extension (only jazzy and humble). The Snap Store has no `ros-rolling-ros-base` content snap. The canonical/ros2cli-snap repo has no rolling branch (master tracks foxy).

Dockerfile.rolling builds and snapcraft works, but you can only build content-snap-free snaps. ros2-test-pub-rolling builds but can't connect to a content snap at runtime.

---

### Humble test-pub snap needs python3-numpy staged

The `ros-humble-ros-base` content snap's `geometry_msgs` imports numpy at import time. Unlike jazzy, numpy is not available through the underlay's dist-packages alone. Stage `python3-numpy` in the test-pub snap and add `$UNDERLAY/usr/lib/python3/dist-packages` to the snap's PYTHONPATH in `launch.sh`.

---

## Example snap recipes shipped with the repo

The repo bundles two kinds of example recipes used only to smoke-test the build flow. Your own snap recipe does not need to follow either layout.

- `snaps/ros2-test-pub-jazzy/`, `snaps/ros2-test-pub-humble/`, `snaps/ros2-test-pub-rolling/` — minimal in-tree publishers, owned by this repo.
- Upstream Canonical recipes, cloned by `make example-clone-<distro>`:
  - Jazzy ros2cli: unmodified from https://github.com/canonical/ros2cli-snap (branch jazzy)
  - Humble ros2cli: unmodified from https://github.com/canonical/ros2cli-snap (branch humble)
  - ros2-nav2: unmodified from https://github.com/canonical/ros2-nav2-snap

---

## Environment variables

All baked into each Dockerfile, no manual export needed:

```
SNAPCRAFT_BUILD_ENVIRONMENT=host
SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1
ROS_DISTRO=<jazzy|humble|rolling>
ROS_VERSION=2
ROS_PYTHON_VERSION=3
AMENT_PREFIX_PATH=/opt/ros/<distro>
PYTHONPATH=/usr/lib/python3/dist-packages:/opt/ros/<distro>/lib/python3.X/site-packages
```

`LD_LIBRARY_PATH` is not set here because it contains an arch-specific multiarch tuple. The entrypoint sources `setup.bash` which sets it correctly.

---

## Useful commands

```bash
# incremental rebuild after a partial failure
snapcraft clean <part-name>
snapcraft pack

# restart a builder after a Dockerfile change
docker rm -f snap-builder-jazzy
docker build -f Dockerfile.jazzy -t ros-snapcraft-jazzy .
docker run -d --name snap-builder-jazzy \
  -v $(pwd)/snaps:/workspace ros-snapcraft-jazzy tail -f /dev/null
```

---

## Caveats

- Destructive mode has no isolation. Always `snapcraft clean` between full rebuilds.
- `cmd | tee log` hides the real exit code. Use `${PIPESTATUS[0]}` to catch snapcraft failures.
- ros2-nav2 is a large build and will OOM on low-memory machines. Reduce parallelism with `--parallel-workers 2` in colcon-cmake-args if needed.

---

## Cross-snap ROS 2 communication

Both snaps need to run as the same user. FastDDS uses shared-memory transport by default, and SHM segments are created with the publisher's UID - a subscriber under a different UID can't attach to them and the failure is silent. The UDP fallback doesn't activate automatically.

The `ros2-cli` and `ros2-test-pub-*` snaps all ship `fastdds_no_shared_memory.xml` and set `FASTRTPS_DEFAULT_PROFILES_FILE` to it, forcing UDP.

### ros2 daemon

`ros2-cli` starts a background daemon on first use that caches DDS discovery. Short commands (`node list`, `topic list`) use its cached view. Long-running commands (`topic echo`) create a fresh DDS participant. If `topic echo` gets no output, try stopping the daemon first with `ros2 daemon stop`.

### ros2-test-pub-* design

Three variants:
- `snaps/ros2-test-pub-jazzy/` (Jazzy, content snap: `ros-jazzy-ros-base`, base: core24)
- `snaps/ros2-test-pub-humble/` (Humble, content snap: `ros-humble-ros-base`, base: core22)
- `snaps/ros2-test-pub-rolling/` (Rolling, no usable content snap yet, base: core24)

All use `plugin: nil` with an override-build that installs `pub.py` (rclpy node publishing three topics at 1 Hz) and `launch.sh` (sets PYTHONPATH and LD_LIBRARY_PATH from the content snap mount point). No compilation. Jazzy and rolling build in ~30 seconds; humble is ~60 seconds (stages numpy).

`ARCH_TRIPLET` in `launch.sh` is auto-detected at runtime via `dpkg-architecture`.
