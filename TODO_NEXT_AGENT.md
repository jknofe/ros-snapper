# TODO for Next Agent — Build ROS 2 Jazzy Snaps

## Goal
Build the following ROS 2 Jazzy snaps inside a Docker container, iterating
on the Dockerfile until every snap builds successfully:

| # | Repo | Snap name | Branch |
|---|------|-----------|--------|
| 1 | https://github.com/canonical/ros2cli-snap.git | `ros2-cli` | `jazzy` |
| 2 | https://github.com/canonical/ros2-nav2-snap.git | `ros2-nav2` | `jazzy` |

These are the two test examples. The Dockerfile, tooling knowledge, and all
discovered pitfalls are already documented — start from what works and extend.

---

## Architecture

```
Host (has Docker)
  └─ docker build -t ros-snapcraft .           # build image from Dockerfile
  └─ docker run -d --name snap-builder \
       -v $(pwd)/snaps:/workspace ros-snapcraft \
       tail -f /dev/null                        # daemon container
  └─ docker exec snap-builder bash -c "cd /workspace/ros2cli-snap && snapcraft pack"
  └─ docker exec snap-builder bash -c "cd /workspace/ros2-nav2-snap && snapcraft pack"
  └─ docker cp snap-builder:/workspace/ros2cli-snap/*.snap .
  └─ docker cp snap-builder:/workspace/ros2-nav2-snap/*.snap .
```

---

## Base Image

Use **`ros:jazzy-ros-base`** (the official Docker library multi-arch image).

**Why:** `osrf/ros:jazzy-desktop-full` only has a linux/amd64 image — it
fails with "exec format error" on arm64/aarch64 hosts. `ros:jazzy-ros-base`
is multi-arch and runs natively on arm64.

**Already present in `ros:jazzy-ros-base` (no need to install):**
- `gpg`, `dirmngr`, `python3-empy`, `python3-numpy`

**Still needed (installed in Dockerfile):**
- `python3-apt`, `python3-catkin-pkg`, `python3-venv`, `squashfs-tools`, `patchelf`, `sudo`, `git`

---

## Workflow

### Step 1 — Prepare snap repos on the host
```bash
mkdir -p snaps
cd snaps

git clone --depth=1 --branch jazzy https://github.com/canonical/ros2cli-snap.git
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2-nav2-snap.git
```
No changes to the snap recipes — use them exactly as cloned.

### Step 2 — Build the Docker image
```bash
# Run from the repo root (where the Dockerfile lives)
docker build -t ros-snapcraft .
```

### Step 3 — Start daemon container
```bash
docker run -d --name snap-builder \
  -v $(pwd)/snaps:/workspace \
  ros-snapcraft \
  tail -f /dev/null
```

### Step 4 — Build snaps via docker exec
Build one at a time, capture logs:

```bash
# ros2cli
docker exec snap-builder bash -c "
  source /opt/ros/jazzy/setup.bash &&
  export SNAPCRAFT_BUILD_ENVIRONMENT=host &&
  export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 &&
  export PYTHONPATH=/usr/lib/python3/dist-packages &&
  cd /workspace/ros2cli-snap &&
  snapcraft pack
" 2>&1 | tee /tmp/build_ros2cli.log
echo "ros2cli exit: $?"

# ros2-nav2
docker exec snap-builder bash -c "
  source /opt/ros/jazzy/setup.bash &&
  export SNAPCRAFT_BUILD_ENVIRONMENT=host &&
  export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 &&
  export PYTHONPATH=/usr/lib/python3/dist-packages &&
  cd /workspace/ros2-nav2-snap &&
  snapcraft pack
" 2>&1 | tee /tmp/build_ros2nav2.log
echo "ros2-nav2 exit: $?"
```

### Step 5 — On error, iterate on Dockerfile
- Read the error log
- Update `Dockerfile` in the repo root
- Rebuild image: `docker stop snap-builder && docker rm snap-builder && docker build -t ros-snapcraft .`
- Restart daemon and retry from Step 3
- For colcon-only failures (build phase already passed pull), use:
  ```bash
  docker exec snap-builder bash -c "cd /workspace/<snap> && snapcraft clean <part> && snapcraft pack"
  ```

### Step 6 — Collect results
```bash
docker cp snap-builder:/workspace/ros2cli-snap/ros2-cli_*.snap ./snaps/
docker cp snap-builder:/workspace/ros2-nav2-snap/ros2-nav2_*.snap ./snaps/
ls -lh ./snaps/*.snap
```

---

## Known Working Fixes (already in Dockerfile)

| Fix | Why needed |
|-----|-----------|
| `gpg` + `dirmngr` in apt | craft_parts calls `gpg --dearmor` for repo signing keys |
| Python RUN step: convert `ros2.sources` PGP → keyring file | apt 2.7+ errors on conflicting Signed-By formats |
| `ENV PYTHONPATH=/usr/lib/python3/dist-packages` | Staged python3 (isolated sys.path) needs catkin_pkg, em, numpy |
| `--system-site-packages` venv for snapcraft | Exposes python3-apt (C extension) to snapcraft venv |
| Extensions path: copy ros2 to `sys.prefix/share/` | pip layout ≠ snapcraft expected layout |
| `empy<4.0` pinned in snapcraft venv | ROS Jazzy rosidl incompatible with empy 4.x API |
| Non-root `builder` user, passwordless sudo for apt-get | Security best practice |

With `osrf/ros:jazzy-desktop-full` some of these may be redundant — trim as you verify.

---

## Key Principle: No Snap Recipe Modifications

All python module errors (`catkin_pkg`, `em`, `numpy`) in the staged python3
are fixed via **`PYTHONPATH=/usr/lib/python3/dist-packages`** in the environment.
Do not add injection code to the snap recipes' `override-build` sections.
If a new module is missing, check if it's installable as `python3-<name>` on
the host and it will be visible via PYTHONPATH automatically.

---

## After Each Snap Builds

1. Verify the `.snap` file exists and is valid:
   ```bash
   file *.snap
   unsquashfs -l *.snap | head -20
   ```
2. Commit any Dockerfile changes with a short message describing what was fixed.
3. Update `KNOWLEDGE_BASE.md` with any new pitfalls discovered.
4. Report final status: which snaps built, which failed, snap file sizes.
