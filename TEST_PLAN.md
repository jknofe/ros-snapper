# Test Plan: ros2-cli + ros2-test-pub amd64 Snaps

## Goal

Verify that locally built amd64 snaps install and communicate correctly: the
`ros2-test-pub` snap publishes ROS 2 topics and `ros2-cli` can discover and
echo them.

## Snaps Under Test

| Snap | File | Installed as |
|------|------|--------------|
| `ros2-cli` | `ros2-cli_0.32.1_amd64.snap` | `x2` (local) |
| `ros2-test-pub` | `ros2-test-pub_0.1_amd64.snap` | `x1` (local, devmode) |

Content provider already installed: `ros-jazzy-ros-base`.

---

## Step 0 — Build snaps

```bash
# Build Docker image
make build-image

# Start builder container
make start-builder

# Build ros2-cli snap
make build-ros2-cli

# Build ros2-test-pub snap
make build-test-pub
```

---

## Step 1 — Install snaps

```bash
sudo snap install --dangerous snaps/ros2cli-snap/ros2-cli_0.32.1_amd64.snap
sudo snap install --dangerous --devmode snaps/ros2-test-pub/ros2-test-pub_0.1_amd64.snap
```

Connect the content interface for ros2-test-pub (ros2-cli connects automatically):

```bash
sudo snap connect ros2-test-pub:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base
```

Verify:

```bash
snap list ros2-cli ros2-test-pub
snap connections ros2-cli        # content[ros-jazzy-ros-base] must be connected
snap connections ros2-test-pub   # content[ros-jazzy-ros-base] must be connected
```

---

## Step 2 — Run the publisher

```bash
ros2-test-pub.pub &
sleep 4
```

---

## Step 3 — Verify topics

```bash
ros2-cli.ros2 topic list
```

Expected to include at minimum: `/test/string`, `/test/twist`, `/test/int32`.

---

## Step 4 — Echo messages

```bash
ros2-cli.ros2 topic echo /test/string --once
# Expected: data: 'hello from test snap #<N>'

ros2-cli.ros2 topic echo /test/twist --once
# Expected: linear.x and angular.z non-zero, linear.y and linear.z zero
```

---

## Step 5 — Measure publish rate

```bash
timeout 6 ros2-cli.ros2 topic hz /test/string --window 4
# Expected: average rate ~2.0 Hz
```

---

## Step 6 — Teardown

```bash
# Stop the publisher (kill the background process from Step 2)
# Remove snaps if rebuilding:
sudo snap remove ros2-test-pub
sudo snap remove ros2-cli
```

---

## Pass / Fail Criteria

| Test | Pass condition |
|------|---------------|
| Snap install | `snap list` shows both snaps |
| Content interfaces | Both `ros-jazzy-ros-base` slots connected |
| Topic list | `/test/string`, `/test/twist`, `/test/int32` present |
| topic echo /test/string | `data: 'hello from test snap #N'` printed |
| topic echo /test/twist | YAML message with non-zero linear.x printed |
| topic hz /test/string | Rate ~2 Hz reported |

---

## Confirmed Results (2026-05-16, amd64)

```
ros2-cli_0.32.1_amd64.snap    built with real snap binary (snapd 2.74.1)
ros2-test-pub_0.1_amd64.snap  built with real snap binary (snapd 2.74.1)

topic echo /test/string: data: 'hello from test snap #8280'
topic echo /test/twist:  linear.x=828.2  angular.z=0.5
topic hz /test/string:   avg 2.0 Hz  window 4
```

All pass criteria met.
