#!/usr/bin/env bash
# Rebase the current bootc/rpm-ostree system onto the custom image.
# Run on the Bazzite host (NOT inside a toolbox).

set -euo pipefail

GH_USER="${GH_USER:-zebcarnell}"
IMAGE="${IMAGE:-ghcr.io/${GH_USER}/bazzite-cachyos:latest}"

echo ">>> Rebasing to ${IMAGE}"
sudo rpm-ostree rebase "ostree-image-signed:docker://${IMAGE}"

echo
echo "Rebase staged. Reboot when ready:"
echo "  sudo systemctl reboot"
echo
echo "After reboot, you can drop the local rpm-ostree layered packages that are"
echo "now baked into the image:"
echo "  sudo rpm-ostree uninstall \\"
echo "    cockpit cockpit-machines corectrl hwloc-devel \\"
echo "    libstdc++-static libuv-static rocm-hip virt-manager"
