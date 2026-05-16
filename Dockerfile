FROM ros:jazzy-ros-base

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=builder
ARG USER_UID=1000
ARG USER_GID=1000

# gpg/dirmngr: craft_parts runs gpg --dearmor for repo keys
# snapd: provides /usr/bin/snap for "snap pack" (no daemon needed, just calls mksquashfs)
# python3-apt: C extension, can't be pip-installed
# sudo: snapcraft needs it to run apt-get at build time
# python3-catkin-pkg, python3-numpy: ament/rosidl build tools call the staged
#   python3 which has an isolated sys.path - these need to be reachable via PYTHONPATH
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        gpg \
        dirmngr \
        sudo \
        python3-venv \
        python3-apt \
        squashfs-tools \
        snapd \
        patchelf \
        python3-catkin-pkg \
        python3-numpy \
    && rm -rf /var/lib/apt/lists/*

# ros:jazzy-ros-base ships ros2.sources with an inline PGP block.
# craft_parts adds its own keyring file for the same URL, and apt rejects
# two different Signed-By values for the same repo. Deleting it here lets
# craft_parts be the sole owner.
RUN rm -f /etc/apt/sources.list.d/ros2.sources

# snapcraft destructive mode needs write access to /var/lib/apt/lists/partial
RUN mkdir -p /root

# PyPI only has snapcraft 4.x; 9.x is git-only.
# --system-site-packages exposes python3-apt (compiled C extension) to the venv.
RUN python3 -m venv --system-site-packages /opt/snapcraft \
    && /opt/snapcraft/bin/pip install --quiet --upgrade pip \
    && /opt/snapcraft/bin/pip install --quiet \
        "git+https://github.com/canonical/snapcraft.git@9.0.0" \
    && ln -s /opt/snapcraft/bin/snapcraft   /usr/local/bin/snapcraft \
    && ln -s /opt/snapcraft/bin/craftctl    /usr/local/bin/craftctl

# pip puts the extension data under site-packages/extensions/ but snapcraft
# looks for it at sys.prefix/share/snapcraft/extensions/
RUN mkdir -p /opt/snapcraft/share/snapcraft/extensions \
    && cp -r /opt/snapcraft/lib/python3.12/site-packages/extensions/ros2 \
             /opt/snapcraft/share/snapcraft/extensions/

# ROS Jazzy toolchain isn't compatible with empy 4.x
RUN /opt/snapcraft/bin/pip install --quiet "empy<4.0" lark

# initialize as root so /etc/ros/rosdep/sources.list.d is writable
RUN rosdep init 2>/dev/null || true \
    && rosdep update --rosdistro jazzy

# PYTHONPATH: the colcon plugin stages its own python3 with an isolated sys.path.
# Setting this here makes catkin_pkg, empy, and numpy visible to it without
# touching the snap recipe.
ENV SNAPCRAFT_BUILD_ENVIRONMENT=host \
    SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 \
    ROS_DISTRO=jazzy \
    ROS_VERSION=2 \
    ROS_PYTHON_VERSION=3 \
    AMENT_PREFIX_PATH=/opt/ros/jazzy \
    PYTHONPATH=/usr/lib/python3/dist-packages:/opt/ros/jazzy/lib/python3.12/site-packages
# LD_LIBRARY_PATH is not set here - it contains an arch-specific multiarch tuple.
# The entrypoint sources setup.bash which sets it correctly.

RUN echo "source /opt/ros/jazzy/setup.bash" >> /root/.bashrc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

# docker build -t ros-snapcraft .
# docker run --rm -v $(pwd)/ros2cli-snap-jazzy:/workspace ros-snapcraft
# docker run --rm -it ros-snapcraft bash
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
