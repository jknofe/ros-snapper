# TODO for Next Agent — Build ROS 2 Jazzy Snaps on amd64

## Background

Both target snaps already build successfully on **arm64**:

| Snap | File | Size | Status |
|------|------|------|--------|
| `ros2-cli` | `ros2-cli_0.32.1_arm64.snap` | 168 MB | ✓ built |
| `ros2-nav2` | `ros2-nav2_1.3.11_arm64.snap` | 661 MB | ✓ built |

This agent runs on a native **amd64** Linux host. The goal is to produce the
same snaps for amd64. The Dockerfile and all pitfalls are already solved —
use the same workflow, just build natively.

---

## Goal

Build amd64 versions of both snaps:
- `ros2-cli_<version>_amd64.snap`
- `ros2-nav2_<version>_amd64.snap`

---

## Workflow

### Step 1 — Clone snap repos
```bash
mkdir -p snaps
cd snaps
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2cli-snap.git
git clone --depth=1 --branch jazzy https://github.com/canonical/ros2-nav2-snap.git
```

### Step 2 — Build the Docker image
```bash
docker build -t ros-snapcraft .
```

### Step 3 — Start daemon container
```bash
docker run -d --name snap-builder \
  -v $(pwd)/snaps:/workspace \
  ros-snapcraft \
  tail -f /dev/null
```

### Step 4 — Build snaps
```bash
docker exec snap-builder bash -c \
  "cd /workspace/ros2cli-snap && snapcraft pack" \
  2>&1 | tee /tmp/build_ros2cli.log
echo "exit: ${PIPESTATUS[0]}"

docker exec snap-builder bash -c \
  "cd /workspace/ros2-nav2-snap && snapcraft pack" \
  2>&1 | tee /tmp/build_ros2nav2.log
echo "exit: ${PIPESTATUS[0]}"
```

### Step 5 — On error, iterate on Dockerfile
- Read the error log
- Update `Dockerfile`, rebuild image, restart container, retry:
  ```bash
  docker rm -f snap-builder
  docker build -t ros-snapcraft .
  docker run -d --name snap-builder -v $(pwd)/snaps:/workspace ros-snapcraft tail -f /dev/null
  ```
- Consult `KNOWLEDGE_BASE.md` — all arm64 pitfalls are documented there and
  most will apply identically on amd64

### Step 6 — Verify and collect
```bash
docker exec snap-builder bash -c "
  find /workspace -name '*.snap' -exec ls -lh {} \;
  find /workspace -name '*.snap' -exec unsquashfs -l {} \; 2>/dev/null | head -10
"
```

---

## Known Arch-Specific Note: LD_LIBRARY_PATH

`LD_LIBRARY_PATH` is NOT set in the Dockerfile `ENV` — it was intentionally
removed because the path contains an arch-specific multiarch tuple:

| Arch | Tuple |
|------|-------|
| arm64 | `aarch64-linux-gnu` |
| amd64 | `x86_64-linux-gnu` |

The entrypoint sources `/opt/ros/jazzy/setup.bash` which sets the correct value
at runtime. snapcraft's colcon plugin manages its own environment during builds,
so this has not caused issues in practice.

---

## After Both Snaps Build

1. Verify `.snap` files exist and are valid squashfs.
2. Commit any Dockerfile changes with a short message describing what was fixed.
3. Update `KNOWLEDGE_BASE.md` with any new amd64-specific pitfalls.
4. Report final status: snap names, sizes, any new issues found.
