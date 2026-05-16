# TODO for Next Agent — ros2cli Snap Build

## Goal
Build `ros2-cli_jazzy-dev_arm64.snap` from the `jazzy` branch of
https://github.com/ros2/ros2cli.git using the **unmodified** canonical snap
recipe from https://github.com/canonical/ros2cli-snap (only change: `source-branch:
jazzy` instead of `source-tag: 0.32.1`).

## Key Insight (do NOT modify the snap recipe)
All Python module failures (`catkin_pkg`, `em`, `numpy`) during the colcon build
are caused by the staged python3's isolated `sys.path`. The fix is a single
environment variable, already set in the Dockerfile and entrypoint.sh:

```bash
export PYTHONPATH=/usr/lib/python3/dist-packages
```

The snap recipe's `override-build` is **canonical and unchanged** — no injection
code needed.

## Current State

### Build #6 was started at session end
```bash
# Check the result first:
ls /workspace/ros2cli-snap-jazzy/*.snap 2>/dev/null
tail -40 /tmp/snapcraft_build6.log
```

### File locations
| Path | Description |
|------|-------------|
| `/prpject/Dockerfile` | Image definition — non-root builder, all env fixes |
| `/prpject/entrypoint.sh` | Container entrypoint |
| `/prpject/KNOWLEDGE_BASE.md` | All pitfalls documented |
| `/workspace/ros2cli-snap-jazzy/` | Build workspace (canonical recipe + `source-branch: jazzy`) |
| `/workspace/ros2cli-snap-jazzy/snap/snapcraft.yaml` | Snap recipe — verify `override-build` is canonical |
| `/tmp/snapcraft_build6.log` | Last build log |

### Environment already set up (persistent in this container)
- snapcraft 9.0.0 installed at `/opt/snapcraft`, symlinked to `/usr/local/bin/`
- ROS2 apt Signed-By conflict fixed in `/etc/apt/sources.list.d/ros2.sources`
- `gpg`, `dirmngr`, `python3-catkin-pkg`, `python3-numpy` installed
- Extensions copied to `/opt/snapcraft/share/snapcraft/extensions/ros2`
- rosdep initialized and updated

## Steps

### 1. Check build #6 result
```bash
ls /workspace/ros2cli-snap-jazzy/*.snap 2>/dev/null && echo "SUCCESS" || echo "no snap"
tail -50 /tmp/snapcraft_build6.log | grep -E "Finished|Failed|Aborted|Summary|EXIT|Packing|Staging"
```

### 2a. If successful
```bash
file /workspace/ros2cli-snap-jazzy/*.snap
unsquashfs -l /workspace/ros2cli-snap-jazzy/*.snap | head -30
```
Report success, update KNOWLEDGE_BASE "Caveats" with any remaining notes.

### 2b. If failed — retry with correct environment
```bash
export SNAPCRAFT_BUILD_ENVIRONMENT=host
export SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1
export PYTHONPATH=/usr/lib/python3/dist-packages
source /opt/ros/jazzy/setup.bash

cd /workspace/ros2cli-snap-jazzy

# Partial clean (keeps cached .deb downloads):
snapcraft clean ros2cli

# Full rebuild:
snapcraft pack 2>&1 | tee /tmp/snapcraft_build7.log
```

### 3. If new Python module errors appear
Check if the missing module is in `/usr/lib/python3/dist-packages`:
```bash
python3 -c "import <module>; print('found')"
```
If yes: PYTHONPATH already covers it — the staged python3 will find it automatically.
If no: install it via apt (`python3-<name>`) and it will be available via PYTHONPATH.
Do NOT modify the snap recipe.

### 4. If non-Python errors appear
Read the full colcon log:
```bash
cat /root/.local/state/snapcraft/log/snapcraft-*.log | tail -100
find /workspace/ros2cli-snap-jazzy/parts/ros2cli/build -name "*.log" | \
  xargs grep -l "Error\|error" 2>/dev/null | head -5
```

### 5. OOM during colcon (4 cores, ~1 GB RAM)
Add `--parallel-workers 1` to the colcon invocation. In snapcraft.yaml this is
done via `colcon-cmake-args` — but try with the default 4 workers first.

## Verification of the PYTHONPATH fix
```bash
# Should print "ALL OK" — if not, PYTHONPATH isn't set
PYTHONPATH=/usr/lib/python3/dist-packages \
  /workspace/ros2cli-snap-jazzy/parts/ros2cli/install/usr/bin/python3 \
  -c "import catkin_pkg, em, numpy; print('ALL OK')" 2>&1
```
(The staged python3 path only exists after `snapcraft pull` or a previous build attempt.)
