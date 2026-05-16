# TODO for Next Agent — ros2cli Snap Build (Docker Daemon Approach)

## Goal
Build `ros2-cli_jazzy-dev_arm64.snap` from the `jazzy` branch of
https://github.com/ros2/ros2cli.git inside a Docker container, then iterate
on the Dockerfile until the build succeeds.

## Architecture

```
Host (has Docker)
  └─ docker build -t ros-snapcraft .        # build image from Dockerfile
  └─ docker run -d --name ros-snapcraft ... # start container as daemon
  └─ docker exec ros-snapcraft snapcraft pack  # build the snap inside
  └─ docker cp ros-snapcraft:/workspace/.../*.snap .  # copy out the result
```

## Base Image Change

Switch from `ros:jazzy-ros-base` to **`osrf/ros:jazzy-desktop-full`**.

**Why:** The desktop-full image ships the complete ROS 2 Jazzy stack including
all message packages, rosidl toolchain, Python tools, and build tools. This
eliminates the need to download hundreds of stage-packages (the ros2cli_msgs
meta-package has 165 message deps) and ensures build-tool packages like
`python3-catkin-pkg`, `python3-empy`, and `python3-numpy` are already present.

The Dockerfile is in `/prpject/Dockerfile` — update the `FROM` line and adjust
or remove apt installs that are no longer needed.

## Workflow

### 1. Build the Docker image
```bash
cd /prpject
docker build -t ros-snapcraft .
```

### 2. Start container as daemon
```bash
docker run -d --name ros-snapcraft \
  -v /prpject/ros2cli-snap-jazzy:/workspace \
  ros-snapcraft bash -c "tail -f /dev/null"
```

The snap project lives at `/prpject/ros2cli-snap-jazzy/` on the host
(already cloned, canonical recipe with `source-branch: jazzy`).
Mount it into `/workspace` inside the container.

If the directory doesn't exist yet, clone it first:
```bash
cd /prpject
git clone --depth=1 https://github.com/canonical/ros2cli-snap.git ros2cli-snap-jazzy
# Change source-branch in the snapcraft.yaml:
sed -i 's/source-tag: .*/source-branch: jazzy/' \
  ros2cli-snap-jazzy/snap/snapcraft.yaml
```

### 3. Build the snap
```bash
docker exec ros-snapcraft bash -c "
  source /opt/ros/jazzy/setup.bash &&
  export SNAPCRAFT_BUILD_ENVIRONMENT=host &&
  export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 &&
  export PYTHONPATH=/usr/lib/python3/dist-packages &&
  cd /workspace &&
  snapcraft pack
" 2>&1 | tee /tmp/snapcraft_build.log
```

### 4. On success — copy out the snap
```bash
docker cp ros-snapcraft:/workspace/ros2-cli_jazzy-dev_arm64.snap .
```

### 5. On error — iterate
- Read the error in `/tmp/snapcraft_build.log`
- Update `Dockerfile` accordingly
- Rebuild: `docker stop ros-snapcraft && docker rm ros-snapcraft && docker build -t ros-snapcraft . && docker run ...`
- For partial failures (colcon phase), use `docker exec` with `snapcraft clean <part>` then retry

## Key Environment Variables (must be set in every exec)
```bash
export SNAPCRAFT_BUILD_ENVIRONMENT=host
export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1
export PYTHONPATH=/usr/lib/python3/dist-packages
source /opt/ros/jazzy/setup.bash
```
These are also set as `ENV` in the Dockerfile so the container inherits them.

## Current Dockerfile State
All fixes from prior research are already in `/prpject/Dockerfile`:

| Fix | What it does |
|-----|-------------|
| `gpg` + `dirmngr` in apt | craft_parts needs `gpg --dearmor` for repo key install |
| Python heredoc RUN step | Converts `ros2.sources` inline PGP to keyring file — prevents apt Signed-By conflict |
| `PYTHONPATH=/usr/lib/python3/dist-packages` | Exposes host catkin_pkg, em, numpy to the isolated staged python3 |
| `--system-site-packages` venv | Exposes python3-apt (C extension) to the snapcraft venv |
| Extensions path copy | Fixes pip vs sys.prefix layout mismatch for ros2 extension |
| `empy<4.0` pinned | ROS Jazzy rosidl toolchain incompatible with empy 4.x |
| Non-root `builder` user | Runs as UID 1000, passwordless sudo for apt-get |

**With `osrf/ros:jazzy-desktop-full` many of these may become unnecessary** —
investigate what's already present in the base image and trim the Dockerfile.

## Known Snap Recipe Details
- Recipe source: https://github.com/canonical/ros2cli-snap
- Only change from canonical: `source-branch: jazzy` (was `source-tag: 0.32.1`)
- The `override-build` is canonical — **do not add injection code**
- All python module availability issues are fixed via PYTHONPATH, not recipe changes

## Investigating the Base Image
```bash
docker run --rm osrf/ros:jazzy-desktop-full bash -c "
  dpkg -l python3-catkin-pkg python3-numpy python3-empy python3-apt gpg 2>/dev/null | grep '^ii' | awk '{print \$2}'
  echo '---'
  python3 -c 'import catkin_pkg, em, numpy; print(\"All OK\")'
"
```

## Updating Files in This Repo
All edits to `/prpject/**` are pre-approved (no permission prompts).
All `docker exec` and `docker build/run/cp` commands are pre-approved.

After each Dockerfile change, commit with a short message describing what was fixed.
After a successful build, update `KNOWLEDGE_BASE.md` with the final working setup
and remove or archive this TODO file.
