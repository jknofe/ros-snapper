# Smoke test: pub + sub example pair (Linux, amd64)

End-to-end check that snaps built with this toolchain can talk to each
other over ROS 2 topics. Uses the two bundled example recipes
`ros2-test-pub-jazzy` and `ros2-test-sub-jazzy`. Optionally also installs
the Canonical `ros2-cli` example to poke at the topics from the
command line.

The same flow works for Humble by swapping `jazzy` for `humble` in
every target and content-snap name. Rolling builds but has no usable
content snap yet, so runtime testing is not possible there.

snapd is required, so this only runs on Linux (or a Linux VM).

## Build and install

```bash
make build-image-jazzy
make start-builder-jazzy
make example-pack-jazzy-test-pub
make example-pack-jazzy-test-sub

sudo snap install --dangerous --devmode snaps/ros2-test-pub-jazzy/ros2-test-pub-jazzy_*.snap
sudo snap install --dangerous --devmode snaps/ros2-test-sub-jazzy/ros2-test-sub-jazzy_*.snap
sudo snap connect ros2-test-pub-jazzy:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base
sudo snap connect ros2-test-sub-jazzy:ros-jazzy-ros-base ros-jazzy-ros-base:ros-jazzy-ros-base
```

Optional: also install `ros2-cli` to inspect topics directly.

```bash
make example-clone-jazzy
make example-pack-jazzy-ros2-cli
sudo snap install --dangerous snaps/ros2cli-snap-jazzy/ros2-cli_*.snap
```

Check connections:

```bash
snap connections ros2-test-pub-jazzy   # ros-jazzy-ros-base connected
snap connections ros2-test-sub-jazzy   # ros-jazzy-ros-base connected
```

## Run

Start the subscriber, then the publisher. Both must run under the same
user (see "Cross-snap ROS 2 communication" in the README).

```bash
ros2-test-sub-jazzy.sub &
sleep 2
ros2-test-pub-jazzy.pub &
sleep 4
```

Watch the subscriber's logs:

```bash
sudo snap logs -n 40 ros2-test-sub-jazzy
# expect lines like:
#   /test/string: 'hello from test snap #N'
#   /test/int32: N
#   /test/twist: linear.x=0.NNN, angular.z=0.500
#   /test/pointcloud #N: 2048x2048 (4194304 points, 48 MiB)
```

The pointcloud line appears about once per second (1 in 10 messages
logged) and confirms that the ~480 MB/s stream is being delivered.

Optional, using `ros2-cli`:

```bash
ros2-cli.ros2 topic list
# should include /test/string, /test/int32, /test/twist, /test/pointcloud

ros2-cli.ros2 topic echo /test/string --once
# data: 'hello from test snap #N'

timeout 6 ros2-cli.ros2 topic hz /test/string --window 4
# ~1 Hz

# Use best-effort QoS to subscribe to the pointcloud
timeout 4 ros2-cli.ros2 topic hz /test/pointcloud --window 8 --qos-reliability best_effort
# ~10 Hz (may be lower under load)
```

## Cleanup

```bash
sudo snap stop ros2-test-pub-jazzy ros2-test-sub-jazzy
sudo snap remove ros2-test-pub-jazzy
sudo snap remove ros2-test-sub-jazzy
sudo snap remove ros2-cli   # if installed
```
