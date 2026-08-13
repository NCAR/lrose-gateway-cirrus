# Heavily borrowed from docker-stacks/scipy-notebook/
# https://github.com/jupyter/docker-stacks/blob/master/scipy-notebook/Dockerfile

ARG BASE_CONTAINER=quay.io/jupyter/minimal-notebook:ubuntu-24.04
FROM $BASE_CONTAINER

LABEL maintainer="LROSE <lrose-help@lists.colostate.edu>"

# See https://github.com/NCAR/lrose-core/releases
# LROSE parameters
ENV LROSE_RELEASE="lrose-core-20250811" \
    LROSE_TARGET_OS="ubuntu_24.04" \
    LROSE_TARGET_ARCH="amd64" \
    PATH="/usr/local/lrose/bin:/share/lrose-nightly/bin:$PATH" \
    LD_LIBRARY_PATH="/usr/local/lrose/lib:/share/lrose-nightly/lib:$LD_LIBRARY_PATH"

# Has to be on a different instruction to use the previously defined parameters
ENV LROSE_RELEASE_URL="https://github.com/NCAR/lrose-core/releases/download/${LROSE_RELEASE}/${LROSE_RELEASE}.${LROSE_TARGET_OS}.${LROSE_TARGET_ARCH}.deb" \
    # Jupyter with VNC parameters \
    JVNC_URL=https://raw.githubusercontent.com/ana-v-espinoza/jupyter-with-vnc/refs/heads/main \
    DISPLAY=:1 \
    NOVNC_DIR=/novnc \
    DESKTOP_ENVIRONMENT=xfce

USER root

RUN apt-get update --yes && \
    apt-get install --yes --no-install-recommends \
      build-essential vim netcdf-bin emacs curl \
      # For app streaming \
      # Dummy X server; vnc server & client \
      x11vnc xvfb xinit novnc xarclock \
      # Some programs for a minimal xfce4 desktop \
      thunar xfdesktop4 xfwm4 xfce4-panel xfce4-session \
      xfce4-appfinder mousepad xfce4-terminal dbus-x11 && \
    # LROSE
    wget ${LROSE_RELEASE_URL} -O /tmp/lrose.deb && \
    apt-get install -y /tmp/lrose.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    # Used to run the novnc websockets proxy server:
    # https://github.com/novnc/noVNC/?tab=readme-ov-file#quick-start
    git clone https://github.com/novnc/novnc --depth=1 ${NOVNC_DIR} && \
    chown -R 1000:100 ${NOVNC_DIR}

USER ${NB_UID}

ADD /environment.yml /tmp

# combine the RUN commands, to prevent intermediate docker images;
#
RUN mamba install --quiet --yes \
      'conda-forge::nb_conda_kernels' \
      'conda-forge::jupyter-server-proxy' \
      'conda-forge::nbgitpuller' \
      'conda-forge::ncview' && \
    mamba create --name lrose-hub-2025 -f /tmp/environment.yml && \
    mamba clean --all -f -y && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# LROSE auxiliary files. These are grouped into subdirectories in the build
# context, but are deliberately flattened into the image's / — the postStart
# hook in ../lrose-jhub-values.yaml copies them from there into each user's home.
COPY --chown=1000:100 \
     configs/.condarc \
     configs/.profile \
     configs/bashrc_lrose \
     notebooks/lrose-nightly.ipynb \
     notebooks/update_workshop_material.ipynb \
     scripts/lrose-swap-install.py \
     scripts/lrose-swap-install.sh \
     /

# Jupyter with VNC auxiliary files
USER root
RUN wget ${JVNC_URL}/jupyter_server_proxy_config.py \
       -O /etc/jupyter/jupyter_server_proxy_config.py && \
    cat /etc/jupyter/jupyter_server_proxy_config.py >> /etc/jupyter/jupyter_server_config.py && \
    wget ${JVNC_URL}/start_virtual_desktop.sh -O /usr/local/bin/before-notebook.d/start_virtual_desktop.sh && \
    wget ${JVNC_URL}/xinitrc -O /etc/X11/xinit/xinitrc
USER ${NB_USER}

WORKDIR "${HOME}"
