#!/bin/sh
set -eu

echo "=========================================="
echo "Container Image Builder"
echo "=========================================="
echo ""

# Set default paths if not provided
PLP_SOURCE_PATH="${PLP_SOURCE_PATH:-/source}"
PLP_BUILD_PATH="${PLP_BUILD_PATH:-/build}"
PLP_CACHE_PATH="${PLP_CACHE_PATH:-/tmp/cache}"

# Create cache directory if it doesn't exist
mkdir -p "$PLP_CACHE_PATH" 2>/dev/null || {
    echo "⚠️  Warning: Cannot create cache directory at $PLP_CACHE_PATH"
    echo "   Cache will not be available for this build."
}

# Verify build path is writable
if [ ! -w "$PLP_BUILD_PATH" ]; then
    echo "❌ Error: Build directory $PLP_BUILD_PATH is not writable"
    echo "   Ensure the directory has appropriate permissions (e.g., chmod 777) or is owned by UID 1000"
    exit 1
fi

echo "Paths:"
echo "  Source: $PLP_SOURCE_PATH"
echo "  Build: $PLP_BUILD_PATH"
echo "  Cache: $PLP_CACHE_PATH"
echo ""

DOCKERFILE="$PLP_SOURCE_PATH/Dockerfile"
OUTPUT_TAR="$PLP_BUILD_PATH/container-image.tar"

ls -l "$PLP_SOURCE_PATH"
echo ""

echo "Building OCI image from $DOCKERFILE..."

# Verify Dockerfile exists
if [ ! -f "$DOCKERFILE" ]; then
  echo "❌ Error: Dockerfile not found at $DOCKERFILE"
  exit 1
fi

# Verify build path is writable
if [ ! -w "$PLP_BUILD_PATH" ]; then
  echo "❌ Error: $PLP_BUILD_PATH directory is not writable"
  exit 1
fi

echo "Building image with BuildKit..."
echo ""

CREATED="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context="$PLP_SOURCE_PATH" \
  --local dockerfile="$PLP_SOURCE_PATH" \
  --export-cache type=local,dest="$PLP_CACHE_PATH/buildkit" \
  --import-cache type=local,src="$PLP_CACHE_PATH/buildkit" \
  --output "type=oci,dest=${OUTPUT_TAR},\
annotation.org.opencontainers.image.source=${GIT_REPOSITORY_URL:-},\
annotation.org.opencontainers.image.revision=${GIT_SHA:-},\
annotation.org.opencontainers.image.created=${CREATED}"

echo ""
echo "=========================================="
echo "Build Complete"
echo "=========================================="
echo "Artifact: container-image.tar"
echo "Size: $(du -h "$OUTPUT_TAR" | cut -f1)"
echo "Location: $OUTPUT_TAR"
echo ""

ls -lh "$PLP_BUILD_PATH"
