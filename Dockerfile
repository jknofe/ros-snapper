FROM ros:jazzy-ros-base

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME=builder
ARG USER_UID=1000
ARG USER_GID=1000

# ── System packages ────────────────────────────────────────────────────────────
# gpg + dirmngr   : craft_parts calls gpg --dearmor when installing repo keys;
#                   must be present BEFORE snapcraft runs (not just gpg-agent)
# squashfs-tools  : mksquashfs for final .snap packaging
# snapd           : provides /usr/bin/snap — needed for "snap pack" and
#                   "snap pack --check-skeleton". Both are self-contained in
#                   the snap binary (no daemon socket needed); snap pack calls
#                   mksquashfs from PATH internally. Same approach as the
#                   official canonical/snapcraft-rocks image.
# patchelf        : ELF rpath rewriting for staged libraries
# python3-apt     : required by snapcraft (C extension, cannot be pip-installed)
# sudo            : snapcraft installs build/stage packages via apt-get at build
#                   time; the non-root builder user needs passwordless sudo for it
# python3-catkin-pkg, python3-numpy : ament/rosidl CMake build tools call the
#                   *staged* python3 binary which has its own isolated sys.path —
#                   these are copied into the staged env via override-build
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

# ── Remove the ROS apt source after package installation ───────────────────────
# ros:jazzy-ros-base ships ros2.sources with an inline PGP block in Signed-By.
# craft_parts creates its own source file using a keyring FILE path (different
# path, same URL) — apt 2.7+ rejects this as "Conflicting values set for
# Signed-By". Fix: remove ros2.sources so craft_parts is the sole owner of
# the ROS repository at build time; it will re-add it with its own keyring.
RUN rm -f /etc/apt/sources.list.d/ros2.sources

# ── Builder home ──────────────────────────────────────────────────────────────
# snapcraft in destructive mode requires root (it opens the system apt cache for
# package checks, which needs write access to /var/lib/apt/lists/partial).
# We run the container as root and just create a home dir for state files.
RUN mkdir -p /root

# ── Snapcraft ─────────────────────────────────────────────────────────────────
# PyPI only carries snapcraft 4.x; the current 9.x line is git-only.
# --system-site-packages exposes python3-apt (a C extension) to the venv.
# Install into /opt/snapcraft so it is accessible by the non-root builder user.
RUN python3 -m venv --system-site-packages /opt/snapcraft \
    && /opt/snapcraft/bin/pip install --quiet --upgrade pip \
    && /opt/snapcraft/bin/pip install --quiet \
        "git+https://github.com/canonical/snapcraft.git@9.0.0" \
    && ln -s /opt/snapcraft/bin/snapcraft   /usr/local/bin/snapcraft \
    && ln -s /opt/snapcraft/bin/craftctl    /usr/local/bin/craftctl

# Fix snapcraft share layout: pip places extension data under site-packages/
# but snapcraft resolves it via sys.prefix/share/snapcraft/extensions/
RUN mkdir -p /opt/snapcraft/share/snapcraft/extensions \
    && cp -r /opt/snapcraft/lib/python3.12/site-packages/extensions/ros2 \
             /opt/snapcraft/share/snapcraft/extensions/

# ── empy (ament template engine) ──────────────────────────────────────────────
# rosidl_adapter imports `em`; the snap's staged python3 needs empy<4 because
# the ROS Jazzy toolchain is not yet compatible with the empy 4.x API.
RUN /opt/snapcraft/bin/pip install --quiet "empy<4.0" lark

# ── rosdep ────────────────────────────────────────────────────────────────────
# Initialize as root so the sources.list.d file is written to /etc/ros/
# (rosdep warns against root, but the builder user inherits the init result)
RUN rosdep init 2>/dev/null || true \
    && rosdep update --rosdistro jazzy

# ── Environment ───────────────────────────────────────────────────────────────
# SNAPCRAFT_BUILD_ENVIRONMENT=host  → skip LXD / Multipass (destructive mode)
# SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 → ros2-jazzy-ros-base is still
#   flagged experimental in snapcraft 9; without this the build exits early
# PYTHONPATH=/usr/lib/python3/dist-packages is the key fix for staged python3:
# The colcon plugin downloads python3.12 as a stage-package; that binary's
# sys.path is fully isolated from the host. When CMake calls it to run
# ament/rosidl build tools (package_xml_2_cmake.py, rosidl_adapter, numpy
# header detection), those tools import catkin_pkg, em, and numpy — all present
# on the host at /usr/lib/python3/dist-packages but invisible to the staged
# python3. Setting PYTHONPATH here is inherited by every subprocess spawned
# during the snapcraft build, including the staged python3, so all three modules
# are found without any modification to the snap recipe itself.
ENV SNAPCRAFT_BUILD_ENVIRONMENT=host \
    SNAPCRAFT_ENABLE_EXPERIMENTAL_EXTENSIONS=1 \
    ROS_DISTRO=jazzy \
    ROS_VERSION=2 \
    ROS_PYTHON_VERSION=3 \
    AMENT_PREFIX_PATH=/opt/ros/jazzy \
    PYTHONPATH=/usr/lib/python3/dist-packages:/opt/ros/jazzy/lib/python3.12/site-packages
# NOTE: LD_LIBRARY_PATH is intentionally omitted — it contains an arch-specific
# multiarch tuple (aarch64-linux-gnu vs x86_64-linux-gnu). setup.bash sets it
# correctly at runtime; the entrypoint sources it for interactive use.

RUN echo "source /opt/ros/jazzy/setup.bash" >> /root/.bashrc

# ── Entrypoint helper ─────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

# Usage:
#   docker build -t ros-snapcraft .
#
#   # Build the ros2cli snap from jazzy branch:
#   docker run --rm -v $(pwd)/ros2cli-snap-jazzy:/workspace ros-snapcraft
#
#   # Interactive shell:
#   docker run --rm -it ros-snapcraft bash
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
