#!/usr/bin/env bash
# Build + push an image to ghcr.io FROM the arm64 omar VM, for services that have
# no GitHub repo/Actions (chatgpt-proxy, chatgpt-browser). The VM is aarch64, so
# the image is natively arm64 — no QEMU. Run from the Mac.
#
# Usage: ./scripts/push-from-vm.sh <service> <remote-src-dir> [dockerfile]
#   ./scripts/push-from-vm.sh chatgpt-proxy   '~/chatgpt-openai-proxy'
#   ./scripts/push-from-vm.sh chatgpt-browser '~/chatgpt-browser-bridge'
#
# Prereqs on the VM: docker logged in to ghcr (echo $PAT | docker login ghcr.io -u omar-massfih --password-stdin)
set -euo pipefail

SVC="${1:?service name}"
SRC="${2:?remote source dir on the VM}"
DOCKERFILE="${3:-}"
ORG="omar-massfih"
IMAGE="ghcr.io/${ORG}/${SVC}"
TAG="$(date +%Y%m%d-%H%M%S)"
HOST="${SSH_HOST:-omar}"

# If a dockerfile from this repo is named, copy it into the source dir on the VM.
DF_ARG=""
if [ -n "$DOCKERFILE" ]; then
  scp "$DOCKERFILE" "${HOST}:${SRC}/Dockerfile.ci"
  DF_ARG="-f Dockerfile.ci"
fi

ssh "$HOST" "cd ${SRC} && docker build ${DF_ARG} -t ${IMAGE}:${TAG} -t ${IMAGE}:latest . && docker push ${IMAGE}:${TAG} && docker push ${IMAGE}:latest"
echo "pushed ${IMAGE}:${TAG} and :latest"
