# vpinos-repo

Signed apt repository for VPINOS packages (`vpinball`, `vpinfe`, `vpxconfig`). Packages are
built in [`vpinos/deb-package-builder`](https://github.com/vpinos/deb-package-builder);
this repo publishes them as a flat apt repository hosted on a single, fixed
GitHub Release (tag `apt`).

## Install

Requirements: a 64-bit x86 (amd64) Debian or Ubuntu system, and `curl`
(`sudo apt install curl ca-certificates`). `vpinball` is built on Ubuntu 24.04,
so use Ubuntu 24.04 / Debian 13 or newer.

1. Add the signing key and the repository:

   ```bash
   sudo install -d -m 0755 /etc/apt/keyrings
   sudo curl -fsSL -o /etc/apt/keyrings/vpinos.asc \
     https://github.com/vpinos/deb-repo/releases/download/apt/vpinos.asc
   echo "deb [signed-by=/etc/apt/keyrings/vpinos.asc] https://github.com/vpinos/deb-repo/releases/download/apt ./" \
     | sudo tee /etc/apt/sources.list.d/vpinos.list
   ```

2. Install:

   ```bash
   sudo apt update
   sudo apt install vpinball vpinfe vpxconfig
   ```

Updates arrive through the normal `sudo apt update && sudo apt upgrade`.

To check the key you just added, its fingerprint should be
`4748 FE25 6E97 C275 8922  A4AB D8CC DDBD 8DA1 D4FE`:

```bash
gpg --show-keys --fingerprint /etc/apt/keyrings/vpinos.asc
```

To remove the repository:

```bash
sudo apt remove vpinball vpinfe vpxconfig   # optional
sudo rm /etc/apt/sources.list.d/vpinos.list /etc/apt/keyrings/vpinos.asc
sudo apt update
```

## How it works

The `apt` release holds everything under one base URL: the `.deb` files plus
`Packages`, `Packages.gz`, `Release`, `InRelease`, `Release.gpg` and the public
key `vpinos.asc`. It is a "flat" repository (the trailing `./` in the source
line), so there is no `dists/` or `pool/` tree. Do not download assets by hand.

## Maintainer: one-time setup

```bash
# 1. Create the GitHub repo and push this project
gh repo create vpinos/deb-repo --public --source=. --push

# 2. Create the signing key (prompts for a passphrase) and export the public key
scripts/generate-key.sh
git add keys/vpinos.asc && git commit -m "add public signing key" && git push

# 3. Store the private key (and passphrase, if you set one) as Actions secrets
gpg --armor --export-secret-keys <fingerprint> \
  | gh secret set VPINOS_GPG_PRIVATE_KEY -R vpinos/deb-repo
gh secret set VPINOS_GPG_PASSPHRASE -R vpinos/deb-repo
```

Secrets are encrypted by GitHub and are never shown again after being set. Also
keep an offline backup of the private key; losing it means every user has to
re-trust a new key. The workflow refuses to run if the secret key does not match
the committed `keys/vpinos.asc`.

## Maintainer: publish an update

Run after a new build finishes in `vpinos/deb-package-builder`. Go to **Actions > Update
apt repository > Run workflow**, or:

```bash
gh workflow run update-repo.yml -R vpinos/deb-repo                 # latest build release
gh workflow run update-repo.yml -R vpinos/deb-repo -f source_release_tag=vpinos-debs-42
gh workflow run update-repo.yml -R vpinos/deb-repo -f dry_run=true # build and sign only
```

The workflow (which runs `scripts/update-repo.sh`):

1. downloads the current `.deb` files from the `apt` release,
2. downloads the `.deb` files from the build release and verifies each against
   its `.sha256` sidecar,
3. keeps only the newest version of each package/architecture,
4. generates and signs the metadata,
5. uploads new debs, then the metadata, then deletes superseded debs.

Packages already in the repo are kept, so a build release that only contains
one package updates just that package. A package only upgrades for users if its
version is higher than the previous one.

The build repo must be public (or the workflow needs a token that can read it).

### Running locally instead

```bash
export VPINOS_GPG_KEY=<fingerprint>
scripts/update-repo.sh [release-tag]
DRY_RUN=1 scripts/update-repo.sh    # build and sign only; result is in .work/
```

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/generate-key.sh` | one-time signing key creation and public key export |
| `.github/workflows/update-repo.yml` | manually triggered publish workflow |
| `scripts/update-repo.sh` | pull from the build repo, merge, and publish |
| `scripts/build-repo.sh` | prune old versions and generate signed metadata |
| `keys/vpinos.asc` | public signing key (also published as a release asset) |
