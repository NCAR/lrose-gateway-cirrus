# Single-user container image

Build context for the JupyterHub single-user image referenced by
`singleuser.image` in `../lrose-jhub-values.yaml`:

```
hub.k8s.ucar.edu/docker/nsflrose/gateway:<tag>
```

These files were copied out of
[`nsf-lrose/lrose-gateway`](https://github.com/nsf-lrose/lrose-gateway)
(`hubs/lrose-hub-2025/`), which is where the image was previously built from.

## What the image contains

Base: `quay.io/jupyter/minimal-notebook:ubuntu-24.04` (Jupyter docker-stacks).

1. **LROSE** — installed from the `.deb` release published at
   [NCAR/lrose-core/releases](https://github.com/NCAR/lrose-core/releases).
   The release is pinned by the `LROSE_RELEASE` build-time `ENV` in the
   `Dockerfile` (currently `lrose-core-20250811`), and `PATH` /
   `LD_LIBRARY_PATH` are set to pick up both `/usr/local/lrose` (stable) and
   `/share/lrose-nightly` (an NFS-mounted nightly build, if present).
2. **Virtual desktop** — XFCE + `x11vnc`/`xvfb`/`novnc`, exposed through
   `jupyter-server-proxy` using configuration pulled from
   [`ana-v-espinoza/jupyter-with-vnc`](https://github.com/ana-v-espinoza/jupyter-with-vnc).
   This is what `START_VIRTUAL_DESKTOP=1` in the Helm values drives.
3. **Conda environment** — a `lrose-hub-2025` env built from
   `environment.yml`, plus `nb_conda_kernels`, `jupyter-server-proxy`,
   `nbgitpuller`, and `ncview` in the base env.

## Layout

```
container/
├── Dockerfile          # The image definition
├── environment.yml     # Conda env for the user's kernel
├── configs/            # ─┐
├── notebooks/          #  ├─ baked into the image at /
└── scripts/            # ─┘
```

`Dockerfile` and `environment.yml` are build inputs. The three subdirectories
hold the **payload** — files baked into the image and then copied into each
user's home by the `singleuser.lifecycleHooks.postStart` hook in
`../lrose-jhub-values.yaml`.

> **The subdirectories group the build context only.** The `COPY` in the
> `Dockerfile` flattens all seven payload files into the image's `/`, so their
> image paths are `/.condarc`, `/lrose-nightly.ipynb`, and so on. That is why
> the postStart hook and `lrose-nightly.ipynb` refer to them at `/`. If you
> change the `COPY` destination, those references have to change with it.

### Build inputs

| File | Purpose |
| --- | --- |
| `Dockerfile` | The image definition. |
| `environment.yml` | Conda env for the user's kernel (numpy, cartopy, arm_pyart, metpy, xarray, seaborn, jupyterlab). Add Python packages here. |

### Payload — `configs/`

| File | Image path | Purpose |
| --- | --- | --- |
| `.condarc` | `/.condarc` | Points `envs_dirs` at `/home/jovyan/my-conda-envs` so user-created envs land on the persistent volume. |
| `.profile` | `/.profile` | Sources `~/.bashrc` for login shells. |
| `bashrc_lrose` | `/bashrc_lrose` | LROSE shell config (aliases, `CLICOLOR`, `conda shell.bash hook`); appended to the user's `.bashrc` by the postStart hook in the Helm values. |

### Payload — `notebooks/`

| File | Image path | Purpose |
| --- | --- | --- |
| `lrose-nightly.ipynb` | `/lrose-nightly.ipynb` | Notebook explaining / driving the stable ↔ nightly swap. |
| `update_workshop_material.ipynb` | `/update_workshop_material.ipynb` | Pulls updates to the `nsf-lrose/lrose-hub` workshop material into the user's workspace. |

### Payload — `scripts/`

| File | Image path | Purpose |
| --- | --- | --- |
| `lrose-swap-install.sh` | `/lrose-swap-install.sh` | Swap `PATH`/`LD_LIBRARY_PATH` priority between the stable and nightly LROSE installs. Must be `source`d. |
| `lrose-swap-install.py` | `/lrose-swap-install.py` | The same swap, for use from a notebook via `%run`. |

## Building

Normally you don't — GitHub Actions does. See
[`.github/workflows/build-container.yml`](../.github/workflows/build-container.yml).

- Any push or PR touching `container/` **builds the image but does not push
  it**, as a check that the `Dockerfile` still works.
- Pushing to the registry is a **manual** `workflow_dispatch` run with the
  *push* box ticked. It is deliberately not automatic: `singleuser.image.tag`
  in `../lrose-jhub-values.yaml` pins an exact tag that ArgoCD syncs onto the
  cluster, so overwriting a tag changes production with no commit behind it.
  The workflow refuses to overwrite an existing tag unless you also tick
  *overwrite*.

The tag defaults to the date parsed out of `LROSE_RELEASE` in the `Dockerfile`
(`lrose-core-20250811` → `20250811`), so the image tag and the LROSE version in
it can't drift apart. You can override it with the *tag* input.

Pushing requires the `HARBOR_USERNAME` / `HARBOR_PASSWORD` repository secrets
to be set for `hub.k8s.ucar.edu`.

### To roll the hub onto a new LROSE release

1. Bump `LROSE_RELEASE` in the `Dockerfile`, and open a PR — CI builds it.
2. Merge, then run the workflow manually with *push* ticked.
3. Set `singleuser.image.tag` in `../lrose-jhub-values.yaml` to the new tag and
   commit; ArgoCD syncs it.

### Building locally

The build context is this directory and there is nothing to configure, so a
plain `docker build` is enough:

```sh
docker build -t hub.k8s.ucar.edu/docker/nsflrose/gateway:20250811 container/
```
