# Smoke test: ros2-cli + ros2-test-pub-jazzy (Linux, amd64)

End-to-end check that two snaps built with this toolchain can talk to
each other over ROS 2 topics. Both recipes are example recipes shipped
with the repo — this is not a test of a production app, it's a test of
the build flow.

The same flow works for Humble by swapping `jazzy` for `humble` in
every target and content-snap name. Rolling builds but has no usable
content snap yet, so runtime testing is not possible there.

snapd is required, so this only runs on Linux (or a Linux VM).

## Build and install

```bash
make build-image-jazzy
make example-clone-jazzy
make start-builder-jazzy
make example-pack-jazzy-ros2-cli
make example-pack-jazzy-test-pub

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
