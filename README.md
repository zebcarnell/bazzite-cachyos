# bazzite-cachyos

Custom [BlueBuild](https://blue-build.org/) image: **Bazzite Deck GNOME** with the **CachyOS kernel** swapped in at build time, plus a handful of packages I would otherwise rpm-ostree-layer on the host.

Base image: `ghcr.io/ublue-os/bazzite-deck-gnome:stable`
Output image: `ghcr.io/zebcarnell/bazzite-cachyos:latest`

## What's in it

- CachyOS kernel from the [`bieszczaders/kernel-cachyos`](https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/) COPR, swapped in for the stock Fedora kernel during the image build (see [Notes](#notes) for why this needs a shell script rather than the declarative module).
- Pre-installed packages: `cockpit`, `cockpit-machines`, `corectrl`, `hwloc-devel`, `libstdc++-static`, `libuv-static`, `rocm-hip`, `virt-manager`.
- Image is signed with cosign; verify with `cosign.pub` from this repo.

## First-time setup (forks)

```bash
# 1. Create the GitHub repo from this directory
gh repo create bazzite-cachyos --public --source=. --remote=origin --push

# 2. Generate cosign keys + upload the private key as SIGNING_SECRET
./scripts/setup-cosign.sh
git add cosign.pub
git commit -m "Add cosign public key"
git push
```

The first GitHub Actions build will run on push (or kick it off via `gh workflow run build-bazzite-cachyos`). Subsequent builds run daily at 06:00 UTC and on every push to `main`, picking up upstream Bazzite + CachyOS kernel updates automatically.

> [!IMPORTANT]
> By default, GHCR publishes packages as **private**, which means `rpm-ostree rebase` will fail to pull. After the first build, make the package public at:
> `https://github.com/users/<your-username>/packages/container/bazzite-cachyos/settings` → Danger Zone → Change visibility → Public.

## Rebase your machine

After the first successful build (and after disabling Secure Boot — see [below](#secure-boot)):

```bash
./scripts/rebase.sh         # set GH_USER=... to override the default
sudo systemctl reboot
```

After reboot, drop the local layers that are now baked into the image (this stages a new deployment, hence the second reboot):

```bash
rpm-ostree status                # confirm you're on ghcr.io/<you>/bazzite-cachyos
uname -r                         # confirm a *-cachyos1.fc<N>.* kernel
sudo rpm-ostree uninstall \
  cockpit cockpit-machines corectrl hwloc-devel \
  libstdc++-static libuv-static rocm-hip virt-manager
sudo systemctl reboot
```

## Test in a VM before rebasing (optional)

Build a bootable disk image from the OCI image and boot it under libvirt/KVM:

```bash
# 1. Pull and convert (privileged podman + bootc-image-builder)
mkdir -p ~/bazzite-cachyos-test/output
sudo podman pull ghcr.io/<your-username>/bazzite-cachyos:latest
sudo podman run --rm --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v ~/bazzite-cachyos-test/output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type qcow2 --rootfs btrfs \
  ghcr.io/<your-username>/bazzite-cachyos:latest

# 2. Boot it (Secure Boot off; see Secure Boot section)
sudo install -o qemu -g qemu -m 0660 \
  ~/bazzite-cachyos-test/output/qcow2/disk.qcow2 \
  /var/lib/libvirt/images/bazzite-cachyos-test.qcow2
sudo virt-install --connect qemu:///system \
  --name bazzite-cachyos-test --memory 4096 --vcpus 4 \
  --disk path=/var/lib/libvirt/images/bazzite-cachyos-test.qcow2,bus=virtio,format=qcow2 \
  --osinfo fedora43 --network network=default --graphics spice \
  --boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
  --import --noautoconsole

virt-viewer --connect qemu:///system bazzite-cachyos-test
```

The `--rootfs btrfs` flag is required because BlueBuild images don't declare a default root filesystem in their metadata.

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
- Fedora major bumps, provided the CachyOS COPR has builds for the new Fedora version. As of this writing the COPR already publishes F44 builds ahead of Bazzite's F44 cutover, so the rollover should be transparent.

When a major bump *might* break the build:
- If Bazzite reshuffles its stock `kernel-*` subpackage set (adds/renames one). Fix: edit the `remove:` list in `recipes/recipe.yml`.
- If the CachyOS COPR is briefly behind on a new Fedora version. Fix: wait, or temporarily pin `image-version: stable-<N>` (the old major) until the COPR catches up.

If you want predictability over auto-rollover, pin `image-version` to `stable-43` (or `stable-44`, etc.) and bump it manually. Tags are visible at <https://github.com/ublue-os/bazzite/pkgs/container/bazzite-deck-gnome>.

Your host won't apply a broken build — `rpm-ostree` only deploys images it can pull and verify. A red CI badge is the warning sign; the previously-good image stays on GHCR.

## Files

- `recipes/recipe.yml` — the BlueBuild recipe (script module + rpm-ostree module + signing).
- `files/scripts/install-cachyos-kernel.sh` — build-time kernel-swap script (stubs the install hooks, swaps the kernel, then runs depmod + dracut manually).
- `.github/workflows/build.yml` — daily + on-push GHA build, signs with `SIGNING_SECRET`.
- `scripts/setup-cosign.sh` — one-shot cosign keypair generation + `SIGNING_SECRET` upload.
- `scripts/rebase.sh` — convenience wrapper for the host-side `rpm-ostree rebase`.
- `cosign.pub` — public signing key (created by the setup script; safe to commit).
