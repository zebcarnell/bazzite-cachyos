#!/usr/bin/env bash
# Rebase the current bootc/rpm-ostree system onto the custom image.
# Run on the Bazzite host (NOT inside a toolbox).

set -euo pipefail

GH_USER="${GH_USER:-<YOUR-USERNAME>}"
IMAGE="${IMAGE:-ghcr.io/${GH_USER}/bazzite-cachyos:latest}"

if [[ "$GH_USER" == "<YOUR-USERNAME>" ]]; then
  echo "Set GH_USER=your-github-username (or edit this script) before running." >&2
  exit 1
fi

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
