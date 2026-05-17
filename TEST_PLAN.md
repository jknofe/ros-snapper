# Test: ros2-cli + ros2-test-pub-jazzy (amd64)

Verifies that the two snaps can talk to each other over ROS 2 topics.

The same flow works for Humble by swapping `jazzy` for `humble` in every
target and content-snap name. Rolling builds but has no usable content snap
yet, so runtime testing is not possible.

## Build and install

```bash
make build-image-jazzy
make clone-snaps-jazzy
make start-builder-jazzy
make build-jazzy-ros2-cli
make build-jazzy-test-pub

sudo snap install --dangerous snaps/ros2cli-snap-jazzy/ros2-cli_*.snap
sudo snap install --dangerous --devmode snaps/ros2-test-pub-jazzy/ros2-test-pub-jazzy_*.snap
sudo snap connect ros2-test-pub-jazzy:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base
```

Check connections:

```bash
snap connections ros2-cli            # ros-jazzy-ros-base should be connected
snap connections ros2-test-pub-jazzy # same
```

## Run

```bash
ros2-test-pub-jazzy.pub &
sleep 4

ros2-cli.ros2 topic list
# should include /test/string, /test/int32, /test/twist

ros2-cli.ros2 topic echo /test/string --once
# data: 'hello from test snap #N'

ros2-cli.ros2 topic echo /test/twist --once
# linear.x non-zero, angular.z 0.5

timeout 6 ros2-cli.ros2 topic hz /test/string --window 4
# ~1 Hz
```

## Results (2026-05-16, amd64, snapd 2.74.1)

All checks passed. Topics visible, echo returned messages, hz reported ~1 Hz.

## Cleanup

```bash
sudo snap remove ros2-test-pub-jazzy
sudo snap remove ros2-cli
```
