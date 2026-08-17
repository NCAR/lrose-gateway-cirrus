# Heavily borrowed from docker-stacks/scipy-notebook/
# https://github.com/jupyter/docker-stacks/blob/master/scipy-notebook/Dockerfile

ARG BASE_CONTAINER=quay.io/jupyter/minimal-notebook:ubuntu-24.04
FROM $BASE_CONTAINER

LABEL maintainer="LROSE <lrose-help@lists.colostate.edu>"

# See https://github.com/NCAR/lrose-core/releases
# LROSE parameters
ENV LROSE_RELEASE="lrose-core-20260425" \
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
    # --no-hsts: HOME is /home/jovyan even as root, so wget would drop a \
    # root-owned .wget-hsts there and break the later fix-permissions run \
    wget --no-hsts ${LROSE_RELEASE_URL} -O /tmp/lrose.deb && \
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
    mamba create --name lrose-hub -f /tmp/environment.yml && \
    # Make lrose-hub the default notebook kernel by overwriting base's
    # "python3" kernelspec, which is what JupyterLab opens new notebooks with.
    # nb_conda_kernels still lists every other env alongside it.
    "${CONDA_DIR}/envs/lrose-hub/bin/python" -m ipykernel install \
      --prefix="${CONDA_DIR}" \
      --name python3 \
      --display-name "Python 3 (lrose-hub)" && \
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

# Activate lrose-hub in interactive shells. This lives in /etc rather than
# /home/${NB_USER}/.bashrc on purpose: on the hub $HOME is a PVC that masks
# anything the image writes there. /etc/profile.d covers login shells (the
# JupyterLab terminal), /etc/bash.bashrc covers interactive non-login shells
# (the XFCE terminal, kubectl exec). The postStart hook in
# ../lrose-jhub-values.yaml also appends the same activation to the PVC's
# .bashrc; the CONDA_DEFAULT_ENV guard keeps the two from stacking.
USER root
RUN printf '%s\n' \
      '# Activate the lrose-hub conda env in interactive shells.' \
      'if [ -n "${BASH_VERSION-}" ] && [ "${CONDA_DEFAULT_ENV-}" != "lrose-hub" ]; then' \
      '    eval "$(conda shell.bash hook)"' \
      '    conda activate lrose-hub' \
      'fi' \
      > /etc/profile.d/10-lrose-activate.sh && \
    echo '. /etc/profile.d/10-lrose-activate.sh' >> /etc/bash.bashrc

# Jupyter with VNC auxiliary files
RUN wget --no-hsts ${JVNC_URL}/jupyter_server_proxy_config.py \
       -O /etc/jupyter/jupyter_server_proxy_config.py && \
    cat /etc/jupyter/jupyter_server_proxy_config.py >> /etc/jupyter/jupyter_server_config.py && \
    wget --no-hsts ${JVNC_URL}/start_virtual_desktop.sh -O /usr/local/bin/before-notebook.d/start_virtual_desktop.sh && \
    wget --no-hsts ${JVNC_URL}/xinitrc -O /etc/X11/xinit/xinitrc
USER ${NB_USER}

WORKDIR "${HOME}"
