# Knowledge Base: Building ROS 2 Snaps with Snapcraft inside Docker

## Environment Profile

| Property | Value |
|----------|-------|
| OS | Ubuntu 24.04 LTS (Noble Numbat) |
| Architecture | arm64 (aarch64) |
| ROS distro | ROS 2 Jazzy Jalisco (`/opt/ros/jazzy`) |
| Python | 3.12.3 |
| CPU | 4 cores |
| RAM | ~1.8 GB total, ~1 GB available |
| Disk | ~51 GB available |
| User | root (snapcraft destructive mode requires write access to apt cache) |

---

## Container Capability Audit

The container is **NOT privileged**. Key findings:

### Missing capabilities (why snapd fails)
- `CAP_SYS_ADMIN` — required by snapd for mount namespaces, AppArmor
- `CAP_NET_ADMIN` — needed for network namespace operations
- No `/dev/fuse`, no `/dev/loop*` — cannot mount `.snap` files

### Consequence
snapd, LXD backend, and Multipass backend are all blocked. Only
`SNAPCRAFT_BUILD_ENVIRONMENT=host` (destructive mode) works.

---

## Snapcraft Installation

PyPI only carries snapcraft **4.x**. The current production line is **9.x**, available only from GitHub:

```bash
python3 -m venv --system-site-packages /opt/snapcraft
/opt/snapcraft/bin/pip install "git+https://github.com/canonical/snapcraft.git@9.0.0"
ln -s /opt/snapcraft/bin/snapcraft /usr/local/bin/snapcraft
ln -s /opt/snapcraft/bin/craftctl  /usr/local/bin/craftctl
```

`--system-site-packages` is required to expose `python3-apt` (a compiled C extension that cannot be pip-installed) to the venv. snapcraft uses python3-apt for its internal apt operations.

**Build command (snapcraft 9.x):**
```bash
snapcraft pack   # "snapcraft" alone is deprecated in 9.x
```

---

## Required Environment Variables

```bash
export SNAPCRAFT_BUILD_ENVIRONMENT=host          # skip LXD/Multipass
export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 # ros2-jazzy-ros-base is experimental
export PYTHONPATH=/usr/lib/python3/dist-packages  # ← critical, see below
source /opt/ros/jazzy/setup.bash
```

---

## Known Pitfalls and Fixes

### 1. `gpg` binary missing — `Cannot find package listed in 'build-packages': gpg`

**Cause:** craft_parts runs `gpg --dearmor` to install signing keys for package repositories. `gnupg-agent` (which installs `gpg-agent`, `gpgconf`) does NOT provide the `gpg` binary.

**Fix:** Add `gpg` and `dirmngr` explicitly to the apt install:
```
apt-get install -y gpg dirmngr ...
```

---

### 2. Conflicting `Signed-By` for the ROS 2 apt repository

**Cause:** `ros:jazzy-ros-base` ships `/etc/apt/sources.list.d/ros2.sources` with the signing key as an **inline PGP block**. craft_parts writes its own source file using a **keyring file path** (`Signed-By: /etc/apt/keyrings/craft-XXXXXXXX.gpg`). apt 2.7+ treats the same repository URL with two different `Signed-By` formats as a hard error:
```
E: Conflicting values set for option Signed-By regarding source http://packages.ros.org/ros2/ubuntu/ noble
```

Note: converting the inline PGP block to a keyring file does NOT resolve this — craft_parts still creates its own keyring file with a different path, causing the same conflict between two keyring-file paths.

**Fix in Dockerfile:** Delete `ros2.sources` after the apt install step so craft_parts is the sole owner of the ROS repository at build time:
```dockerfile
RUN rm -f /etc/apt/sources.list.d/ros2.sources
```
craft_parts re-adds the ROS repo with its own keyring file when snapcraft runs — no conflict.

---

### 3. Staged python3 cannot find `catkin_pkg`, `em`, `numpy` — **PYTHONPATH fix**

**Cause:** The colcon plugin downloads `python3.12` as a stage-package. That staged binary has a fully isolated `sys.path` that only sees the staged filesystem:
```
parts/ros2cli/install/usr/lib/python312.zip
parts/ros2cli/install/usr/lib/python3.12
parts/ros2cli/install/usr/lib/python3.12/lib-dynload
parts/ros2cli/install/usr/lib/python3/dist-packages   ← only has argcomplete
```

During the colcon build, CMake invokes the staged python3 for multiple operations:
- `ament_cmake_core/cmake/core/package_xml_2_cmake.py` → imports `catkin_pkg`
- `rosidl_adapter` (via `-m rosidl_adapter`) → imports `em` (empy)
- `find_package(Python3 COMPONENTS NumPy)` → needs `numpy.get_include()`

All three (`catkin_pkg`, `em`, `numpy`) are present on the host at `/usr/lib/python3/dist-packages/` but invisible to the staged python3.

**The naive (wrong) approach** is to copy these packages into the staged dist-packages inside an `override-build` block in the snap recipe. This pollutes the snap recipe with host-specific workarounds.

**The correct fix:** Set `PYTHONPATH=/usr/lib/python3/dist-packages` in the build environment. Python always prepends `PYTHONPATH` entries to `sys.path` and this is inherited by every subprocess — including the staged python3 — through the entire colcon/CMake call tree.

```bash
# In Dockerfile ENV:
ENV PYTHONPATH=/usr/lib/python3/dist-packages

# Verified to fix all three in one shot:
PYTHONPATH=/usr/lib/python3/dist-packages \
  parts/ros2cli/install/usr/bin/python3 \
  -c "import catkin_pkg, em, numpy; print('ALL OK')"
# → ALL OK
```

**No changes to the snap recipe are needed.**

---

### 4. Snapcraft extensions share path

**Cause:** pip places snapcraft's extension data under `site-packages/extensions/`, but snapcraft resolves it via `sys.prefix/share/snapcraft/extensions/`.

**Fix:**
```bash
mkdir -p /opt/snapcraft/share/snapcraft/extensions
cp -r /opt/snapcraft/lib/python3.12/site-packages/extensions/ros2 \
      /opt/snapcraft/share/snapcraft/extensions/
```

---

### 5. `empy` version in the snapcraft venv

**Cause:** `rosidl_adapter` (called from the host ROS installation, not the staged env) imports `em`. empy 4.x changed its API and is incompatible with ROS Jazzy's rosidl toolchain.

**Fix:** Pin to `empy<4.0` in the snapcraft venv. The system `python3-empy` (3.3.4) at `/usr/lib/python3/dist-packages/em.py` is also compatible and is the one exposed to the staged python3 via PYTHONPATH.

---

### 6. `osrf/ros:jazzy-desktop-full` is amd64-only — use `ros:jazzy-ros-base`

**Cause:** `osrf/ros:jazzy-desktop-full` only publishes a `linux/amd64` image. On arm64/aarch64 hosts it fails immediately with `exec /ros_entrypoint.sh: exec format error`.

**Fix:** Use `ros:jazzy-ros-base` from the official Docker library — it is a proper multi-arch image (amd64 + arm64). Already pre-installed: `gpg`, `dirmngr`, `python3-empy`, `python3-numpy`.

---

### 7. Non-root user blocked from apt cache — run as root

**Cause:** snapcraft destructive mode calls `apt.cache.Cache(rootdir="/")` (Python-level, not a subprocess) to check whether required packages are installed. This tries to create `/var/lib/apt/lists/partial` and fails for non-root users:
```
PermissionError: [Errno 13] Permission denied: '//var/lib/apt/lists/partial'
```

**Fix:** Run the container as root. Remove the `USER` directive from the Dockerfile. This is a build container — security tradeoffs are acceptable.

Additionally, `ros:jazzy-ros-base` ships with an `ubuntu` user at UID/GID 1000, so `groupadd`/`useradd` with those IDs also fails during image build.

---

### 8. `snap` binary required for both lint and pack — stub with mksquashfs

**Cause:** snapcraft 9.x delegates two operations to the `snap` CLI (part of snapd), which cannot run in a non-privileged container:
1. `snap pack --check-skeleton <prime>` — pre-pack structural validation
2. `snap lint <prime>` — metadata/library linting
3. `snap pack --filename F --compression C <prime> <outdir>` — actual squashfs creation

**Fix:** Install a stub `/usr/local/bin/snap` that:
- Returns 0 for `lint` and `pack --check-skeleton` (skips validation)
- Implements `pack` via `mksquashfs` (squashfs-tools already in the image)

```bash
RUN cat > /usr/local/bin/snap << 'EOF'
#!/bin/bash
set -e
case "$1" in
  lint) exit 0 ;;
  pack)
    shift
    for arg in "$@"; do [[ "$arg" == --check-skeleton ]] && exit 0; done
    filename=""; compression="xz"; prime_dir=""; output_dir="."
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --filename)    filename="$2";    shift 2 ;;
        --compression) compression="$2"; shift 2 ;;
        --*)           shift ;;
        *) [[ -z "$prime_dir" ]] && prime_dir="$1" || output_dir="$1"; shift ;;
      esac
    done
    mksquashfs "$prime_dir" "${output_dir}/${filename}" \
      -noappend -comp "$compression" -no-xattrs -all-root
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x /usr/local/bin/snap
```

---

## Snap Recipe

The snap recipe is the **unmodified** canonical recipe from https://github.com/canonical/ros2cli-snap with only one change: `source-branch: jazzy` instead of `source-tag: 0.32.1`.

```yaml
parts:
  ros2cli:
    plugin: colcon
    source: https://github.com/ros2/ros2cli.git
    source-branch: jazzy          # ← only change from canonical
    colcon-packages-ignore:
      - ros2pkg
      - ros2run
      - ros2launch
    build-packages:
      - ros-jazzy-rosidl-adapter
    stage-packages:
      - python3-argcomplete
    override-build: |             # ← identical to canonical
      # inject fake ros2cli_msgs meta-package
      ...
      craftctl default
```

The host python packages required for the build (`catkin_pkg`, `em`, `numpy`) are provided via `PYTHONPATH` — not by modifying the recipe.

---

## Host Packages Required

```bash
apt-get install -y \
  git \
  gpg \
  dirmngr \
  sudo \
  python3-venv \
  python3-apt \
  squashfs-tools \
  patchelf \
  python3-catkin-pkg \   # provides catkin_pkg + pyparsing + docutils for staged python3
  python3-numpy \        # provides numpy for staged python3
  python3-empy           # provides em.py (v3.3.4) for staged python3 (already in ros-base)
```

`python3-empy` is pre-installed in `ros:jazzy-ros-base`; listed here for completeness.

---

## Quick Reference

```bash
# Environment (must be set before snapcraft)
export SNAPCRAFT_BUILD_ENVIRONMENT=host
export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1
export PYTHONPATH=/usr/lib/python3/dist-packages
source /opt/ros/jazzy/setup.bash

# Build
cd /workspace/ros2cli-snap-jazzy
snapcraft pack

# Incremental rebuild (keeps downloaded stage packages)
snapcraft clean ros2cli
snapcraft pack
```

---

## Caveats

- **Destructive mode = no isolation.** Always `snapcraft clean` between full rebuilds.
- **Memory.** ~1 GB free RAM with 4 cores. If colcon OOMs, reduce parallelism via `--parallel-workers 2` in the `colcon-cmake-args` key.
- **apt lists wiped.** The Dockerfile does `rm -rf /var/lib/apt/lists/*` per layer. snapcraft runs its own internal `apt-get update` before resolving build-packages — this is fine as long as the Signed-By conflict is resolved first.
