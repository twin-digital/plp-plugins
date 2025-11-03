#!/bin/sh
set -eu

# Expected mounts:
# /source - read-only source directory containing Dockerfile
# /build  - writable directory for output

DOCKERFILE="/source/Dockerfile"
OUTPUT_TAR="/build/container-image.tar"

ls -l /source

echo "Building OCI image from $DOCKERFILE..."

# Verify Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
  echo "❌ Error: Dockerfile not found at $DOCKERFILE"
  exit 1
fi

# Verify /build is writable
if [ ! -w "/build" ]; then
  echo "❌ Error: /build directory is not writable"
  exit 1
fi

echo "Building image with BuildKit..."

  # --opt label:org.opencontainers.image.source="${GIT_REPOSITORY_URL}" \
  # --opt label:org.opencontainers.image.revision="${GIT_SHA}" \
  # --opt label:org.opencontainers.image.created="${CREATED}" \

CREATED="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context=/source \
  --local dockerfile=/source \
  --output "type=oci,dest=${OUTPUT_TAR},\
annotation.org.opencontainers.image.source=${GIT_REPOSITORY_URL},\
annotation.org.opencontainers.image.revision=${GIT_SHA},\
annotation.org.opencontainers.image.created=${CREATED}"

echo "✅ Successfully built and saved image to $OUTPUT_TAR"
echo "Image size: $(du -h "$OUTPUT_TAR" | cut -f1)"
