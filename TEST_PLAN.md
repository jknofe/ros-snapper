# Test: ros2-cli + ros2-test-pub (amd64)

Verifies that the two snaps can talk to each other over ROS 2 topics.

## Build and install

```bash
make build-image
make start-builder
make build-ros2-cli
make build-test-pub

sudo snap install --dangerous snaps/ros2cli-snap/ros2-cli_*.snap
sudo snap install --dangerous --devmode snaps/ros2-test-pub/ros2-test-pub_*.snap
sudo snap connect ros2-test-pub:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base
```

Check connections:

```bash
snap connections ros2-cli      # ros-jazzy-ros-base should be connected
snap connections ros2-test-pub # same
```

## Run

```bash
ros2-test-pub.pub &
sleep 4

ros2-cli.ros2 topic list
# should include /test/string, /test/int32, /test/twist

ros2-cli.ros2 topic echo /test/string --once
# data: 'hello from test snap #N'

ros2-cli.ros2 topic echo /test/twist --once
# linear.x non-zero, angular.z 0.5

timeout 6 ros2-cli.ros2 topic hz /test/string --window 4
# ~2 Hz
```

## Results (2026-05-16, amd64, snapd 2.74.1)

All checks passed. Topics visible, echo returned messages, hz reported ~2 Hz.

## Cleanup

```bash
sudo snap remove ros2-test-pub
sudo snap remove ros2-cli
```
