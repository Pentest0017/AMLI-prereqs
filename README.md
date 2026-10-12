# AMLI prerequisites

Everything a bare Linux server needs before the **AMLI** application repo can run.
Two repos, two steps:

| Step | Repo | Command |
|------|------|---------|
| 1. prerequisites (this repo) | `AMLI-prereqs` | `bash install-prereqs.sh` |
| 2. application | `AMLI` | `bash deploy.sh` |

## Step 1 - on the server

```bash
git clone https://github.com/<you>/AMLI-prereqs.git
cd AMLI-prereqs
bash install-prereqs.sh
```

It checks the server (x86_64 Linux, RAM, disk), uses the container engine already there
(Podman or Docker) or installs one, installs the bundled `bin/docker-compose`, wires Podman
for compose, and opens firewall port 8443. Then open a **new shell** (so
`/etc/profile.d/amli-podman.sh` is picked up) and continue with step 2.

### Server that can only reach GitHub (no Docker Hub / PyPI / npm)

The container images are too big for git (about 10 GB), so they are attached to GitHub
**Releases** and downloaded by `load-images.sh`:

```bash
./load-images.sh <owner>/AMLI-prereqs images-base-v1   # SQL Server, qdrant, caddy, mailhog
./load-images.sh <owner>/AMLI-prereqs images-app-v1    # AMLI backend + frontend
```

(or `AMLI_IMAGES_REPO=<owner>/AMLI-prereqs bash install-prereqs.sh` to load the base images
as part of step 1.) The app's `deploy.sh` notices the images are already loaded and skips
the build, so nothing is downloaded from the internet at all.

### No package repositories either?

Put Podman's `.rpm` files (plus dependencies) in `./rpms/`; `install-prereqs.sh` installs from
there instead of `dnf`.

## Preparing the bundle (once, on a machine with internet and the images)

```bash
./fetch-binaries.sh                                    # downloads bin/docker-compose, then git add it
./export-images.sh images-base.txt out/base            # packs images into <=1.9 GB parts
./export-images.sh images-app.txt  out/app
gh release create images-base-v1 out/base/* --title "AMLI base images" --notes "container images"
gh release create images-app-v1  out/app/*  --title "AMLI app images"  --notes "container images"
```

Rebuild and re-publish `images-app-*` whenever the application code changes.

## What is NOT in here

Secrets. The app repo creates its own `.env` with random passwords on first run.
