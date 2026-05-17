.PHONY: \
  build-image-jazzy build-image-humble build-image-rolling \
  clone-snaps-jazzy clone-snaps-humble \
  start-builder-jazzy start-builder-humble start-builder-rolling \
  stop-builder-jazzy stop-builder-humble stop-builder-rolling \
  build-jazzy-ros2-cli build-jazzy-ros2-nav2 build-jazzy-test-pub \
  build-humble-ros2-cli build-humble-ros2-nav2 build-humble-test-pub \
  build-rolling-test-pub \
  all-jazzy all-humble all-rolling

# Build inside the container's local filesystem, not on the host bind mount.
# craft_parts writes user.* xattrs on staged files, which the macOS Docker
# Desktop bind-mount bridge does not support. See scripts/pack-snap.sh.
PACK = pack-snap

# ---------- jazzy ----------

build-image-jazzy:
	docker build -f Dockerfile.jazzy -t ros-snapcraft-jazzy .

clone-snaps-jazzy:
	mkdir -p snaps
	[ -d snaps/ros2cli-snap-jazzy ]   || git clone --branch jazzy https://github.com/canonical/ros2cli-snap   snaps/ros2cli-snap-jazzy
	[ -d snaps/ros2-nav2-snap-jazzy ] || git clone --branch jazzy https://github.com/canonical/ros2-nav2-snap snaps/ros2-nav2-snap-jazzy

start-builder-jazzy:
	docker run -d --name snap-builder-jazzy \
	  -v "$(CURDIR)/snaps:/workspace" \
	  ros-snapcraft-jazzy tail -f /dev/null

stop-builder-jazzy:
	docker rm -f snap-builder-jazzy

build-jazzy-ros2-cli:
	docker exec snap-builder-jazzy $(PACK) ros2cli-snap-jazzy

build-jazzy-ros2-nav2:
	docker exec snap-builder-jazzy $(PACK) ros2-nav2-snap-jazzy

build-jazzy-test-pub:
	docker exec snap-builder-jazzy $(PACK) ros2-test-pub

all-jazzy: build-image-jazzy clone-snaps-jazzy start-builder-jazzy build-jazzy-ros2-cli build-jazzy-test-pub

# ---------- humble ----------

build-image-humble:
	docker build -f Dockerfile.humble -t ros-snapcraft-humble .

clone-snaps-humble:
	mkdir -p snaps
	[ -d snaps/ros2cli-snap-humble ]   || git clone --branch humble https://github.com/canonical/ros2cli-snap   snaps/ros2cli-snap-humble
	[ -d snaps/ros2-nav2-snap-humble ] || git clone --branch humble https://github.com/canonical/ros2-nav2-snap snaps/ros2-nav2-snap-humble

start-builder-humble:
	docker run -d --name snap-builder-humble \
	  -v "$(CURDIR)/snaps:/workspace" \
	  ros-snapcraft-humble tail -f /dev/null

stop-builder-humble:
	docker rm -f snap-builder-humble

build-humble-ros2-cli:
	docker exec snap-builder-humble $(PACK) ros2cli-snap-humble

build-humble-ros2-nav2:
	docker exec snap-builder-humble $(PACK) ros2-nav2-snap-humble

build-humble-test-pub:
	docker exec snap-builder-humble $(PACK) ros2-test-pub-humble

all-humble: build-image-humble clone-snaps-humble start-builder-humble build-humble-ros2-cli build-humble-test-pub

# ---------- rolling ----------
# snapcraft 9.0 has no ros2-rolling extension and the store has no
# ros-rolling-ros-base content snap. ros2cli rolling is not yet packagable
# this way. test-pub builds but cannot be connected at runtime.

build-image-rolling:
	docker build -f Dockerfile.rolling -t ros-snapcraft-rolling .

start-builder-rolling:
	docker run -d --name snap-builder-rolling \
	  -v "$(CURDIR)/snaps:/workspace" \
	  ros-snapcraft-rolling tail -f /dev/null

stop-builder-rolling:
	docker rm -f snap-builder-rolling

build-rolling-test-pub:
	docker exec snap-builder-rolling $(PACK) ros2-test-pub-rolling

all-rolling: build-image-rolling start-builder-rolling build-rolling-test-pub
