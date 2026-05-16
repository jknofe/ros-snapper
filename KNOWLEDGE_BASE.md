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
| User | non-root `builder` (UID 1000), passwordless sudo for apt-get |

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

**Fix in Dockerfile:** Convert `ros2.sources` to use a keyring file before snapcraft runs:
```python
# Python heredoc in a RUN step
import re, subprocess, os

src = '/etc/apt/sources.list.d/ros2.sources'
keyring = '/etc/apt/keyrings/ros2-jazzy.gpg'

with open(src) as f:
    content = f.read()

m = re.search(r'(-----BEGIN PGP PUBLIC KEY BLOCK-----.*?-----END PGP PUBLIC KEY BLOCK-----)',
              content, re.DOTALL)
pgp = '\n'.join(line.lstrip(' .') for line in m.group(1).splitlines())
result = subprocess.run(['gpg', '--dearmor'], input=pgp.encode(), capture_output=True, check=True)
os.makedirs('/etc/apt/keyrings', exist_ok=True)
with open(keyring, 'wb') as f:
    f.write(result.stdout)
new = re.sub(r'Signed-By:.*?-----END PGP PUBLIC KEY BLOCK-----\n',
             f'Signed-By: {keyring}\n', content, flags=re.DOTALL)
with open(src, 'w') as f:
    f.write(new)
```

After the fix, apt emits a harmless **warning** about duplicate sources (both files reference the same URL+suite) but no longer errors.

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
