.PHONY: help \
  build-image-jazzy build-image-humble \
  start-builder-jazzy start-builder-humble \
  stop-builder-jazzy stop-builder-humble \
  pack-jazzy pack-humble \
  test-jazzy \
  example-clone-jazzy example-clone-humble \
  example-pack-jazzy-ros2-cli example-pack-jazzy-ros2-nav2 \
  example-pack-jazzy-test-pub example-pack-jazzy-test-sub \
  example-pack-humble-ros2-cli example-pack-humble-ros2-nav2 \
  example-pack-humble-test-pub example-pack-humble-test-sub

# scripts/pack-snap.sh is invoked inside the container. It copies the recipe
# into /build/<recipe>, runs snapcraft there, and copies the .snap back to the
# host bind mount. See KNOWLEDGE_BASE.md for the xattr reason.
PACK = pack-snap

help:
	@echo "Build your own snap (any recipe at snaps/<NAME>/):"
	@echo "  make build-image-<distro>             build the snapcraft image"
	@echo "  make start-builder-<distro>           run the build container"
	@echo "  make pack-<distro> SNAP=<NAME>        pack snaps/<NAME>/"
	@echo "  make stop-builder-<distro>            remove the build container"
	@echo ""
	@echo "Test (no snapd required — unsquashes snaps and runs nodes in-container):"
	@echo "  make test-jazzy                       run jazzy pub+sub inside the builder"
	@echo ""
	@echo "Bundled examples (smoke-test the toolchain):"
	@echo "  make example-pack-<distro>-test-pub   bundled minimal publisher"
	@echo "  make example-pack-<distro>-test-sub   bundled minimal subscriber"
	@echo "  make example-clone-<distro>           clone canonical ros2-cli + ros2-nav2"
	@echo "  make example-pack-<distro>-ros2-cli   pack canonical ros2-cli"
	@echo "  make example-pack-<distro>-ros2-nav2  pack canonical ros2-nav2"
	@echo ""
	@echo "<distro> = jazzy | humble"

# ============================================================================
# Core build flow — generic; works for any recipe at snaps/<SNAP>/
# ============================================================================

build-image-jazzy:
	docker build -f Dockerfile.jazzy -t ros-snapcraft-jazzy .

start-builder-jazzy:
	docker run -d --name snap-builder-jazzy \
	  -v "$(CURDIR)/snaps:/workspace" \
	  ros-snapcraft-jazzy tail -f /dev/null

stop-builder-jazzy:
	docker rm -f snap-builder-jazzy

pack-jazzy:
	@test -n "$(SNAP)" || { echo "usage: make pack-jazzy SNAP=<recipe-dir>"; exit 2; }
	docker exec snap-builder-jazzy $(PACK) $(SNAP)

build-image-humble:
	docker build -f Dockerfile.humble -t ros-snapcraft-humble .

start-builder-humble:
	docker run -d --name snap-builder-humble \
	  -v "$(CURDIR)/snaps:/workspace" \
	  ros-snapcraft-humble tail -f /dev/null

stop-builder-humble:
	docker rm -f snap-builder-humble

pack-humble:
	@test -n "$(SNAP)" || { echo "usage: make pack-humble SNAP=<recipe-dir>"; exit 2; }
	docker exec snap-builder-humble $(PACK) $(SNAP)

test-jazzy:
	docker exec snap-builder-jazzy test-snap

# ============================================================================
# Examples — convenience targets for the bundled in-tree publishers and the
# canonical Canonical recipes. Skip these for your own work; use pack-<distro>
# above. Each example target is a thin wrapper over the same docker exec.
# ============================================================================

example-clone-jazzy:
	mkdir -p snaps
	[ -d snaps/ros2cli-snap-jazzy ]   || git clone --branch jazzy https://github.com/canonical/ros2cli-snap   snaps/ros2cli-snap-jazzy
	[ -d snaps/ros2-nav2-snap-jazzy ] || git clone --branch jazzy https://github.com/canonical/ros2-nav2-snap snaps/ros2-nav2-snap-jazzy

example-pack-jazzy-ros2-cli:
	docker exec snap-builder-jazzy $(PACK) ros2cli-snap-jazzy

example-pack-jazzy-ros2-nav2:
	docker exec snap-builder-jazzy $(PACK) ros2-nav2-snap-jazzy

example-pack-jazzy-test-pub:
	docker exec snap-builder-jazzy $(PACK) ros2-test-pub-jazzy

example-pack-jazzy-test-sub:
	docker exec snap-builder-jazzy $(PACK) ros2-test-sub-jazzy

example-clone-humble:
	mkdir -p snaps
	[ -d snaps/ros2cli-snap-humble ]   || git clone --branch humble https://github.com/canonical/ros2cli-snap   snaps/ros2cli-snap-humble
	[ -d snaps/ros2-nav2-snap-humble ] || git clone --branch humble https://github.com/canonical/ros2-nav2-snap snaps/ros2-nav2-snap-humble

example-pack-humble-ros2-cli:
	docker exec snap-builder-humble $(PACK) ros2cli-snap-humble

example-pack-humble-ros2-nav2:
	docker exec snap-builder-humble $(PACK) ros2-nav2-snap-humble

example-pack-humble-test-pub:
	docker exec snap-builder-humble $(PACK) ros2-test-pub-humble

example-pack-humble-test-sub:
	docker exec snap-builder-humble $(PACK) ros2-test-sub-humble
