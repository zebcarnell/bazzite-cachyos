#!/usr/bin/env bash
# Swap the stock Bazzite kernel for the CachyOS kernel from the
# bieszczaders/kernel-cachyos COPR.
#
# This is a build-time script (runs inside the BlueBuild image build),
# NOT something to run on a live host. The dance below is required because
# rpm-ostree's kernel-install + dracut hooks fire during `dnf install` of
# the new kernel BEFORE depmod has populated /usr/lib/modules/<ver>/modules.dep,
# so they crash. We stub the hooks, swap the kernel, then run depmod + dracut
# manually for the new kernel version. Pattern adapted from
# https://github.com/sihawken/cachyos-kernel-bazzite-dx (build.sh).

set -euo pipefail

echo ">>> Stubbing rpm-ostree + dracut kernel-install hooks"
cd /usr/lib/kernel/install.d
mv 05-rpmostree.install 05-rpmostree.install.bak
mv 50-dracut.install 50-dracut.install.bak
printf '%s\n' '#!/bin/sh' 'exit 0' > 05-rpmostree.install
printf '%s\n' '#!/bin/sh' 'exit 0' > 50-dracut.install
chmod +x 05-rpmostree.install 50-dracut.install
cd -

echo ">>> Enabling bieszczaders/kernel-cachyos COPR"
dnf5 -y copr enable bieszczaders/kernel-cachyos

echo ">>> Removing stock kernel packages"
dnf5 -y remove \
  kernel \
  kernel-core \
  kernel-modules \
  kernel-modules-core \
  kernel-modules-extra

# Stale module trees (e.g. kernel-modules-akmods leftovers) confuse depmod later.
rm -rf /lib/modules/*

echo ">>> Installing kernel-cachyos"
dnf5 -y install --allowerasing \
  kernel-cachyos \
  kernel-cachyos-devel-matched

echo ">>> Restoring kernel-install hooks"
cd /usr/lib/kernel/install.d
mv -f 05-rpmostree.install.bak 05-rpmostree.install
mv -f 50-dracut.install.bak 50-dracut.install
cd -

echo ">>> Generating depmod + initramfs for the new CachyOS kernel"
releasever=$(/usr/bin/rpm -E %fedora)
basearch=$(/usr/bin/arch)
KVER=$(dnf list kernel-cachyos -q | awk '/^kernel-cachyos\./ {print $2}' | head -n1 | cut -d'-' -f1)-cachyos1.fc${releasever}.${basearch}
echo "    Kernel version: ${KVER}"

depmod -a "${KVER}"
export DRACUT_NO_XATTR=1
/usr/bin/dracut \
  --no-hostonly \
  --kver "${KVER}" \
  --reproducible \
  -v \
  --add ostree \
  -f "/lib/modules/${KVER}/initramfs.img"
chmod 0600 "/lib/modules/${KVER}/initramfs.img"

echo ">>> CachyOS kernel ${KVER} installed"
