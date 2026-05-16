# TODO for Next Agent — Multi-Arch Docker Image (arm64 + amd64)

## Background

Both target snaps already build successfully on **arm64**:

| Snap | File | Size | Status |
|------|------|------|--------|
| `ros2-cli` | `ros2-cli_0.32.1_arm64.snap` | 168 MB | ✓ built |
| `ros2-nav2` | `ros2-nav2_1.3.11_arm64.snap` | 661 MB | ✓ built |

The Dockerfile, all pitfalls, and the complete fix history are in `KNOWLEDGE_BASE.md`.
The working Dockerfile is in this repo root.

---

## Goal

Extend the build to produce **amd64 snaps** as well, by making the Docker image
build for both platforms.

Desired outcome:
- `ros2-cli_0.32.1_amd64.snap`
- `ros2-nav2_1.3.11_amd64.snap`

---

## What Needs to Change

### 1. Docker multi-arch build (docker buildx)

The current `docker build` only targets the host architecture. Use `docker buildx`
to build the image for both `linux/amd64` and `linux/arm64`:

```bash
# One-time setup (if not already done)
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap

# Build multi-arch image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ros-snapcraft:latest \
  --load \        # or --push if pushing to a registry
  .
```

For amd64 snap builds on an arm64 host, Docker uses QEMU emulation automatically
via the `docker-container` buildx driver. The builds will be slower but correct.

### 2. Running amd64 snap builds

To build the amd64 snaps, run the container explicitly with `--platform linux/amd64`:

```bash
docker run -d --name snap-builder-amd64 \
  --platform linux/amd64 \
  -v $(pwd)/snaps-amd64:/workspace \
  ros-snapcraft:latest \
  tail -f /dev/null

docker exec snap-builder-amd64 bash -c "cd /workspace/ros2cli-snap && snapcraft pack"
docker exec snap-builder-amd64 bash -c "cd /workspace/ros2-nav2-snap && snapcraft pack"
```

### 3. Prepare amd64 snap repos

Clone the same repos into a separate directory for the amd64 build (keep arm64
artifacts separate to avoid conflicts):

```bash
mkdir -p snaps-amd64
cd snaps-amd64
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2cli-snap.git
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2-nav2-snap.git
```

---

## Known Arch-Specific Issue: LD_LIBRARY_PATH

The ROS setup script (`source /opt/ros/jazzy/setup.bash`) sets `LD_LIBRARY_PATH`
with an architecture-specific multiarch tuple:

| Arch | Library path |
|------|-------------|
| arm64 | `/opt/ros/jazzy/lib/aarch64-linux-gnu:/opt/ros/jazzy/lib` |
| amd64 | `/opt/ros/jazzy/lib/x86_64-linux-gnu:/opt/ros/jazzy/lib` |

**`LD_LIBRARY_PATH` is intentionally NOT in the Dockerfile `ENV`** — it was
removed because hardcoding `aarch64-linux-gnu` would break amd64 builds.
`setup.bash` sets it correctly at container startup via the entrypoint.

For `docker exec` sessions that need `LD_LIBRARY_PATH`: either run
`source /opt/ros/jazzy/setup.bash` first, or confirm that snapcraft's build
works without it (it has in testing — the colcon plugin handles its own env).

---

## Workflow Summary

### Step 1 — Enable buildx multi-arch support
```bash
docker buildx create --name multiarch --driver docker-container --use
docker buildx inspect --bootstrap
```

### Step 2 — Build the multi-arch image
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t ros-snapcraft --load .
```

If `--load` fails with multi-platform (docker limitation), build per-arch:
```bash
docker buildx build --platform linux/amd64 -t ros-snapcraft:amd64 --load .
docker buildx build --platform linux/arm64 -t ros-snapcraft:arm64 --load .
```

### Step 3 — Clone snap repos for amd64
```bash
mkdir -p snaps-amd64
cd snaps-amd64
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2cli-snap.git
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2-nav2-snap.git
```

### Step 4 — Start amd64 container and build snaps
```bash
docker run -d --name snap-builder-amd64 \
  --platform linux/amd64 \
  -v $(pwd)/snaps-amd64:/workspace \
  ros-snapcraft:amd64 \
  tail -f /dev/null

docker exec snap-builder-amd64 bash -c \
  "cd /workspace/ros2cli-snap && snapcraft pack" \
  2>&1 | tee /tmp/build_ros2cli_amd64.log
echo "exit: ${PIPESTATUS[0]}"

docker exec snap-builder-amd64 bash -c \
  "cd /workspace/ros2-nav2-snap && snapcraft pack" \
  2>&1 | tee /tmp/build_ros2nav2_amd64.log
echo "exit: ${PIPESTATUS[0]}"
```

### Step 5 — On error, iterate on Dockerfile
Apply the same iteration loop as before:
- Read the log, identify the error
- Update Dockerfile, rebuild image, restart container, retry
- Consult `KNOWLEDGE_BASE.md` for known pitfalls — most should already be solved

### Step 6 — Verify and collect results
```bash
docker exec snap-builder-amd64 bash -c "
  unsquashfs -l /workspace/ros2cli-snap/*.snap | head -10
  unsquashfs -l /workspace/ros2-nav2-snap/*.snap | head -10
"
ls -lh snaps-amd64/ros2cli-snap/*.snap snaps-amd64/ros2-nav2-snap/*.snap
```

---

## After Both Arches Build

1. Commit any new Dockerfile fixes.
2. Update `KNOWLEDGE_BASE.md` with any new amd64-specific pitfalls.
3. Report: both snap files for both arches, sizes, any regressions.
