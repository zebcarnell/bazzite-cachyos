#!/usr/bin/env bash
# Generate a cosign keypair for the BlueBuild image and upload the private key
# to GitHub Actions as the SIGNING_SECRET secret.
#
# Requirements: cosign, gh (logged in: `gh auth login`)
# Run this from the repo root AFTER pushing the repo to GitHub.

set -euo pipefail

if ! command -v cosign >/dev/null; then
  echo "cosign not found. Install it: https://docs.sigstore.dev/system_config/installation/" >&2
  exit 1
fi
if ! command -v gh >/dev/null; then
  echo "gh CLI not found. Install: https://cli.github.com/" >&2
  exit 1
fi

if [[ -f cosign.key || -f cosign.pub ]]; then
  echo "cosign.key or cosign.pub already exists in $(pwd). Refusing to overwrite." >&2
  echo "If you want to rotate, delete them first." >&2
  exit 1
fi

# IMPORTANT: when cosign prompts for a password, press Enter twice (no password).
# An encrypted key will not work in GitHub Actions.
echo ">>> Generating cosign keypair (press Enter at the password prompts — no password)"
COSIGN_PASSWORD="" cosign generate-key-pair

echo ">>> Uploading cosign.key to GitHub Actions secret SIGNING_SECRET"
gh secret set SIGNING_SECRET < cosign.key

echo
echo "Done."
echo " - Commit cosign.pub to the repo (it is the public verification key)."
echo " - Keep cosign.key private; .gitignore already excludes it."
echo " - The build workflow will sign images using SIGNING_SECRET on the next run."
