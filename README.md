# bazzite-cachyos

Custom [BlueBuild](https://blue-build.org/) image: **Bazzite Deck GNOME** with the **CachyOS kernel** swapped in at build time, plus a handful of packages I would otherwise rpm-ostree-layer on the host.

Base image: `ghcr.io/ublue-os/bazzite-deck-gnome:stable`
Output image: `ghcr.io/zebcarnell/bazzite-cachyos:latest`

## What's in it

- CachyOS kernel from the [`bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/) COPR (replaces the stock Fedora kernel during the image build, where it's a normal `dnf` op rather than a tricky `rpm-ostree override`).
- Pre-installed packages: `cockpit`, `cockpit-machines`, `corectrl`, `hwloc-devel`, `libstdc++-static`, `libuv-static`, `rocm-hip`, `virt-manager`.
- Image is signed with cosign; verify with `cosign.pub` from this repo.

## First-time setup

```bash
# 1. Create the GitHub repo from this directory
gh repo create bazzite-cachyos --public --source=. --remote=origin --push

# 2. Generate cosign keys + upload the private key as SIGNING_SECRET
./scripts/setup-cosign.sh
git add cosign.pub
git commit -m "Add cosign public key"
git push
```

The first GitHub Actions build will run on push (or you can kick it off via `gh workflow run build-bazzite-cachyos`). Subsequent builds run daily at 06:00 UTC and on every push to `main`, picking up upstream Bazzite + CachyOS kernel updates automatically.

## Rebase your machine

After the first successful build:

```bash
GH_USER=your-github-username ./scripts/rebase.sh
sudo systemctl reboot
```

Then drop the local layers that are now baked into the image:

```bash
sudo rpm-ostree uninstall \
  cockpit cockpit-machines corectrl hwloc-devel \
  libstdc++-static libuv-static rocm-hip virt-manager
```

## Verifying signatures

```bash
cosign verify --key cosign.pub ghcr.io/zebcarnell/bazzite-cachyos
```

## Notes

- **Module choice.** Kernel swap is done via a shell script (`files/scripts/install-cachyos-kernel.sh`) rather than the declarative `rpm-ostree`/`dnf` modules, because rpm-ostree's `kernel-install` + dracut hooks fire during the install before `depmod` populates `modules.dep`, causing dracut to fail. The script stubs those hooks, swaps the kernel, then runs depmod + dracut manually.
- **Auto-updates on the host.** Rebasing only changes what you track. The system still needs to run `rpm-ostree upgrade` (or whatever timer/auto-update service is enabled) to pull each new build. Reboot to apply.

## Secure Boot

The CachyOS kernel is **not signed with a key trusted by Fedora's shim**, so it will fail to boot on any UEFI system with Secure Boot enabled (you'll see `bad shim signature` / `you need to load the kernel first` from GRUB).

Two options before rebasing:

1. **Disable Secure Boot in firmware** (simplest). Reboot into your UEFI setup, turn it off, save, reboot.
2. **Enroll the CachyOS signing key via MOK** (keeps Secure Boot on). The bieszczaders COPR ships a signing key; you'd need to import it into shim's MOK list. See the [bieszczaders/kernel-cachyos COPR notes](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/) for the current procedure.

For VM testing with `virt-install`, pass `--boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no`.

## Maintenance & Fedora major version transitions

`image-version: stable` is a **floating** tag. When Bazzite cuts over from F43 → F44, the next daily rebuild will pull the F44 base automatically. The COPR URL uses `%OS_VERSION%`, which BlueBuild substitutes to the base image's actual Fedora version at build time, so the kernel repo URL updates itself.

In practice this means **no maintenance** for:
- Daily Bazzite updates
- New CachyOS kernel releases
- Fedora major bumps (provided the CachyOS COPR has builds for the new Fedora version, which it usually does ahead of time — F44 was already published before Bazzite F44 shipped)

When a major bump *might* break the build:
- If Bazzite reshuffles its stock `kernel-*` subpackage set (adds/renames one). Fix: edit the `remove:` list in `recipes/recipe.yml`.
- If the CachyOS COPR is briefly behind on a new Fedora version. Fix: wait, or temporarily pin `image-version: stable-<N>` (the old major) until the COPR catches up.

If you want predictability over auto-rollover, pin `image-version` to `stable-43` (or `stable-44`, etc.) and bump it manually. Tags are visible at <https://github.com/ublue-os/bazzite/pkgs/container/bazzite-deck-gnome>.

Your host won't apply a broken build — `rpm-ostree` only deploys images it can pull and verify. A red CI badge is the warning sign; the previously-good image stays on GHCR.

## Files

- `recipes/recipe.yml` — the BlueBuild recipe.
- `.github/workflows/build.yml` — daily + on-push GHA build.
- `scripts/setup-cosign.sh` — one-shot cosign keypair generation + `SIGNING_SECRET` upload.
- `scripts/rebase.sh` — convenience wrapper for the host-side `rpm-ostree rebase`.
- `cosign.pub` — public signing key (created by the setup script; safe to commit).
