IMAGE   := ros-snapcraft
BUILDER := snap-builder

.PHONY: build-image clone-snaps start-builder stop-builder \
        build-ros2-cli build-ros2-nav2 build-test-pub

build-image:
	docker build -t $(IMAGE) .

clone-snaps:
	mkdir -p snaps
	[ -d snaps/ros2cli-snap ]   || git clone --branch jazzy https://github.com/canonical/ros2cli-snap   snaps/ros2cli-snap
	[ -d snaps/ros2-nav2-snap ] || git clone --branch jazzy https://github.com/canonical/ros2-nav2-snap snaps/ros2-nav2-snap

start-builder:
	docker run -d --name $(BUILDER) \
	  -v "$(CURDIR)/snaps:/workspace" \
	  $(IMAGE) tail -f /dev/null

stop-builder:
	docker rm -f $(BUILDER)

build-ros2-cli:
	docker exec $(BUILDER) bash -c \
	  'cd /workspace/ros2cli-snap && snapcraft pack 2>&1 | tee /workspace/ros2cli-snap/build.log; exit $${PIPESTATUS[0]}'

build-ros2-nav2:
	docker exec $(BUILDER) bash -c \
	  'cd /workspace/ros2-nav2-snap && snapcraft pack 2>&1 | tee /workspace/ros2-nav2-snap/build.log; exit $${PIPESTATUS[0]}'

build-test-pub:
	docker exec $(BUILDER) bash -c \
	  'cd /workspace/ros2-test-pub && snapcraft pack 2>&1 | tee /workspace/ros2-test-pub/build.log; exit $${PIPESTATUS[0]}'
