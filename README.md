# lrose-gateway-cirrus

A JupyterHub for [LROSE](http://lrose.net/) (Lidar Radar Open Software Environment), hosted on NSF NCAR's **CIRRUS** Kubernetes platform. The hub is reachable at **https://lrosehub.k8s.ucar.edu** and is operated as a partnership between NSF NCAR and Colorado State University.

## Overview

The deployment has three parts:

1. **Helm values** (`lrose-jhub-values.yaml`) — configuration for the upstream [Zero to JupyterHub](https://z2jh.jupyter.org/) (`jupyterhub`) Helm chart. This defines authentication, the single-user server image and resources, ingress, and storage.
2. **Kustomize manifests** (`manifests/`) — supporting Kubernetes resources that the Helm release depends on: the secret sync, ingress middleware, network policy, and the custom login/spawn page templates.
3. **Container image** (`container/`) — the build context for the single-user image (`nsflrose/gateway`) that users get when they spawn a server: LROSE, the XFCE/VNC virtual desktop, and the conda environment. See [`container/README.md`](container/README.md).

Everything is deployed into the `eol-lrose` namespace.

## Repository layout

```
.
├── lrose-jhub-values.yaml          # Helm values for the JupyterHub (z2jh) chart
├── .github/workflows/
│   └── build-container.yml         # Builds (and on demand pushes) the user image
├── container/                      # Build context for the single-user image
│   ├── Dockerfile                  # LROSE + XFCE/noVNC desktop on jupyter/minimal-notebook
│   ├── environment.yml             # Conda env for the user kernel
│   ├── configs/                    # .condarc, .profile, bashrc_lrose
│   ├── notebooks/                  # lrose-nightly, update_workshop_material
│   └── scripts/                    # lrose-swap-install.{sh,py}
└── manifests/
    ├── kustomization.yaml          # Ties the manifests together + generates template/CSS ConfigMaps
    ├── lrose-jhub-esos.yaml        # ExternalSecret: pulls GitHub OAuth creds into the cluster
    ├── middlewares.yaml            # Traefik buffering middleware (large file uploads)
    ├── cilium-hub-apiserver.yaml   # CiliumNetworkPolicy: hub egress to kube-apiserver
    └── customization/
        ├── templates/              # Custom JupyterHub page/login/spawn HTML
        │   ├── page.html
        │   ├── login.html
        │   └── spawn.html
        └── static/
            ├── css/style.css       # LROSE/CSU/NCAR branding styles
            └── images/             # Logos and favicon
```

## Configuration details

### Authentication

Login uses **GitHub OAuth** (`GitHubOAuthenticator`). Access is restricted to members of the [`nsf-lrose`](https://github.com/nsf-lrose) GitHub organization (`allowed_organizations`), with the `read:org` scope. `allow_all` is `false`, so users must be org members or previously allowed users. Admin users are listed by GitHub login under `Authenticator.admin_users` in `lrose-jhub-values.yaml`.

GitHub OAuth credentials are **not** stored in the repo. They live in a secret store and are synced into the cluster by the `ExternalSecret` in `manifests/lrose-jhub-esos.yaml`, which creates the `lrose-hub-secrets` Secret (`GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET`). The Helm values reference that secret via `extraEnv`. The OAuth callback URL is `https://lrosehub.k8s.ucar.edu/hub/oauth_callback`.

> The `ExternalSecret` reads through a `SecretStore` named `lrose-ro`. `SecretStore` is a **namespaced** resource and is not part of this repo, so one has to exist in `eol-lrose` for the sync to work. If the hub pod won't start, check the `ExternalSecret` status first.

### Single-user servers

- **Image:** `hub.k8s.ucar.edu/docker/nsflrose/gateway` (tag set in the values file).
- **Default URL:** `/lab` (JupyterLab), with a virtual desktop enabled (`START_VIRTUAL_DESKTOP=1`).
- **Storage:** 20Gi dynamic PVC per user (`ceph-kubepv`) mounted at `/home/jovyan`.
- **postStart hook:** clones the [`nsf-lrose/lrose-hub`](https://github.com/nsf-lrose/lrose-hub) workshop material via `gitpuller` and seeds dotfiles/notebooks on first launch.
- **Resource profiles** users can choose at spawn:
  - **Low Power** — 2 GB / 1.5 vCPU
  - **Medium Power** (default) — 12 GB / 3.5 vCPU
  - **High Power** — 16 GB / 4 vCPU

### Networking & ingress

- The proxy service is `ClusterIP`; traffic enters through a Traefik ingress (`traefik-external`) at `lrosehub.k8s.ucar.edu` with a TLS cert from the `incommon` cluster issuer (cert-manager).
- A **Traefik buffering middleware** (`manifests/middlewares.yaml`) raises the request body limit to 500 MiB so users can upload large files. Only *request* buffering is enabled — response buffering would break notebook websockets/streaming.
- A **CiliumNetworkPolicy** (`manifests/cilium-hub-apiserver.yaml`) allows the hub pod egress to the `kube-apiserver` (needed to spawn user pods). It selects on `release: lrose-jhub`, so the Helm release must keep that name or the hub will fail to spawn servers.

### Branding / customization

The login and spawn pages are customized for LROSE with NSF NCAR and CSU logos and links to LROSE resources (website, wiki, forum, hub repo). The templates and CSS are mounted into the hub pod from ConfigMaps generated by `manifests/kustomization.yaml`, and `hub.templatePaths` / `extraVolumeMounts` in the values file point JupyterHub at them.

## The container image and the build workflow

The single-user image is built by GitHub Actions from `container/`, defined in [`.github/workflows/build-container.yml`](.github/workflows/build-container.yml). It has two deliberately separate modes.

**Automatic — build only.** Any push to `main` or pull request that touches `container/` builds the image and throws it away. Nothing reaches the registry and nothing on the cluster changes. This is a correctness check: it proves the `Dockerfile` and `environment.yml` still resolve before anyone tries to release them.

**Manual — build and push.** Releasing is a `workflow_dispatch` run from the Actions tab with the *push* box ticked. This is intentional. `singleuser.image.tag` in `lrose-jhub-values.yaml` pins an exact tag and ArgoCD syncs it, so quietly overwriting a tag would change what's running in production with no commit to show for it.

### Adding a Python/conda package

This is the common case — it does not require touching the `Dockerfile` or LROSE.

1. Add the package to `container/environment.yml` and open a PR. CI builds the image and tells you whether conda can actually solve the environment with it. **Fix solver failures here**, not after a release.
2. Merge to `main`.
3. Run **Build single-user image** manually from the Actions tab:
   - tick **push**
   - set **tag** to something new, e.g. `20250811-1`
   - leave **overwrite** unticked
4. Set `singleuser.image.tag` in `lrose-jhub-values.yaml` to that same tag and commit. ArgoCD syncs it, and new servers spawn on the new image.

> **Why you have to set a tag by hand.** With the tag field left blank the workflow derives it from `LROSE_RELEASE` in the `Dockerfile` (`lrose-core-20250811` → `20250811`) so the image tag and the LROSE version can never drift apart. A conda-only change doesn't move `LROSE_RELEASE`, so the derived tag already exists in the registry and the workflow's *Refuse to clobber an existing tag* step will fail the run. Giving it a new tag is the fix; ticking *overwrite* instead would replace the image the hub is currently pinned to, which is not what you want.

Steps 1–2 are enough to *validate* a package. Steps 3–4 are what puts it in front of users.

### Rolling onto a new LROSE release

1. Bump `LROSE_RELEASE` in `container/Dockerfile` and open a PR — CI builds it.
2. Merge, then run the workflow manually with *push* ticked. Leave the tag blank; it derives from the new `LROSE_RELEASE`.
3. Set `singleuser.image.tag` in `lrose-jhub-values.yaml` to the new tag and commit.

Pushing requires the `HARBOR_USERNAME` / `HARBOR_PASSWORD` repository secrets for `hub.k8s.ucar.edu`. See [`container/README.md`](container/README.md) for what's inside the image and how the payload files reach each user's home directory.

## Deployment

This hub is deployed and managed by **CIRRUS ArgoCD**. ArgoCD watches this repository, so changes are made by committing to the repo — push a change and it gets synced onto the cluster automatically.

### Making changes

- **Add/remove an admin:** edit `Authenticator.admin_users` in `lrose-jhub-values.yaml`.
- **Add a conda package or change the user image:** see [The container image and the build workflow](#the-container-image-and-the-build-workflow) above.
- **Adjust resource profiles:** edit `singleuser.profileList`.
- **Update login/spawn page styling:** edit files under `manifests/customization/` (the hub pod may need a restart to pick up template/CSS changes — the ConfigMaps are generated with `disableNameSuffixHash: true`, so their contents change without rolling the deployment).
