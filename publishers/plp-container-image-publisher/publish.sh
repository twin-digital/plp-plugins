#!/bin/bash
set -euo pipefail

# Exit codes
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_AUTH_FAILURE=2
EXIT_VALIDATION_FAILURE=3
EXIT_MISSING_VAR=4

echo "PLP Container Image Publisher"
echo ""

# Validate required environment variables
REQUIRED_VARS=(
  "PLP_IMAGE_PATH"
  "PLP_IMAGE_REPOSITORY"
  "PLP_COMMIT_SHA"
  "PLP_REGISTRY_USERNAME"
  "PLP_REGISTRY_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "❌ Error: Required environment variable $var is not set"
    exit $EXIT_MISSING_VAR
  fi
done

# Validate that at least one ref context is provided
if [ -z "${PLP_BRANCH_NAME:-}" ] && [ -z "${PLP_TAG_NAME:-}" ] && [ -z "${PLP_PULL_REQUEST_NUMBER:-}" ]; then
  echo "❌ Error: At least one of PLP_BRANCH_NAME, PLP_TAG_NAME, or PLP_PULL_REQUEST_NUMBER must be set"
  exit $EXIT_MISSING_VAR
fi

# Validate image file exists
if [ ! -f "$PLP_IMAGE_PATH" ]; then
  echo "❌ Error: Image file not found at $PLP_IMAGE_PATH"
  exit $EXIT_VALIDATION_FAILURE
fi

echo "Configuration:"
echo "  Image path: $PLP_IMAGE_PATH"
echo "  Repository: $PLP_IMAGE_REPOSITORY"
echo "  Commit SHA: $PLP_COMMIT_SHA"
if [ -n "${PLP_BRANCH_NAME:-}" ]; then
  echo "  Branch: $PLP_BRANCH_NAME"
fi
if [ -n "${PLP_TAG_NAME:-}" ]; then
  echo "  Tag: $PLP_TAG_NAME"
fi
if [ -n "${PLP_PULL_REQUEST_NUMBER:-}" ]; then
  echo "  Pull Request: #$PLP_PULL_REQUEST_NUMBER"
fi
if [ "${PLP_IS_DEFAULT_BRANCH:-}" = "true" ]; then
  echo "  Default branch: yes"
fi
echo ""

echo "Validating image..."
IMAGE_SIZE=$(stat -f%z "$PLP_IMAGE_PATH" 2>/dev/null || stat -c%s "$PLP_IMAGE_PATH" 2>/dev/null)
echo "  Image size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE 2>/dev/null || echo "$IMAGE_SIZE bytes")"

# Test skopeo can read the image
if ! skopeo inspect "oci-archive:$PLP_IMAGE_PATH" > /dev/null 2>&1; then
  echo "❌ Error: Failed to inspect OCI image - file may be corrupted or invalid"
  exit $EXIT_VALIDATION_FAILURE
fi
echo "  ✅ Image is valid"
echo ""

# Determine tags based on git context
PRIMARY_TAG=""
ADDITIONAL_TAGS=()
SHORT_SHA="${PLP_COMMIT_SHA:0:7}"

# Branch builds
if [ -n "${PLP_BRANCH_NAME:-}" ]; then
  PRIMARY_TAG="$PLP_BRANCH_NAME"
  ADDITIONAL_TAGS+=("$PLP_BRANCH_NAME-$SHORT_SHA")
  
  # Add 'latest' tag for default branch
  if [ "${PLP_IS_DEFAULT_BRANCH:-}" = "true" ]; then
    ADDITIONAL_TAGS+=("latest")
  fi
fi

# Pull/Merge request builds
if [ -n "${PLP_PULL_REQUEST_NUMBER:-}" ]; then
  PR_NUMBER="${PLP_PULL_REQUEST_NUMBER}"
  PRIMARY_TAG="pr-$PR_NUMBER"
  ADDITIONAL_TAGS+=("pr-$PR_NUMBER-$SHORT_SHA")
fi

# Tag builds (highest priority)
if [ -n "${PLP_TAG_NAME:-}" ]; then
  # Extract semver components if it matches pattern (with or without 'v' prefix)
  if [[ "$PLP_TAG_NAME" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    # This is a semver tag - use only the numeric versions
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    
    PRIMARY_TAG="$MAJOR.$MINOR.$PATCH"
    ADDITIONAL_TAGS+=("$MAJOR.$MINOR")
    ADDITIONAL_TAGS+=("$MAJOR")
  else
    # Not a semver tag - use as-is
    PRIMARY_TAG="$PLP_TAG_NAME"
  fi
fi

if [ -z "$PRIMARY_TAG" ]; then
  echo "❌ Error: Unable to determine primary tag"
  exit $EXIT_GENERAL_ERROR
fi

echo "Tags to apply:"
echo "  Primary: $PRIMARY_TAG"
if [ ${#ADDITIONAL_TAGS[@]} -gt 0 ]; then
  echo "  Additional:"
  for tag in "${ADDITIONAL_TAGS[@]}"; do
    echo "    - $tag"
  done
fi
echo ""

# Push image with primary tag
FULL_IMAGE="$PLP_IMAGE_REPOSITORY:$PRIMARY_TAG"
echo "Pushing image with primary tag..."
echo "  Destination: $FULL_IMAGE"

if ! skopeo copy \
  "oci-archive:$PLP_IMAGE_PATH" \
  "docker://$FULL_IMAGE" \
  --dest-creds "$PLP_REGISTRY_USERNAME:$PLP_REGISTRY_PASSWORD" 2>&1; then
  echo "❌ Error: Failed to push image"
  exit $EXIT_GENERAL_ERROR
fi

echo "  ✅ Pushed successfully"
echo ""

# Copy to additional tags
FAILED_TAGS=()
if [ ${#ADDITIONAL_TAGS[@]} -gt 0 ]; then
  echo "Applying additional tags..."
  for tag in "${ADDITIONAL_TAGS[@]}"; do
    echo "  Tagging as: $tag"
    TARGET_IMAGE="$PLP_IMAGE_REPOSITORY:$tag"
    
    if ! skopeo copy \
      "docker://$FULL_IMAGE" \
      "docker://$TARGET_IMAGE" \
      --src-creds "$PLP_REGISTRY_USERNAME:$PLP_REGISTRY_PASSWORD" \
      --dest-creds "$PLP_REGISTRY_USERNAME:$PLP_REGISTRY_PASSWORD" 2>&1; then
      echo "    ❌ Failed to tag as $tag"
      FAILED_TAGS+=("$tag")
    else
      echo "    ✅ Tagged successfully"
    fi
  done
  echo ""
fi

# Check if any tags failed
if [ ${#FAILED_TAGS[@]} -gt 0 ]; then
  echo "❌ Error: Failed to apply the following tags:"
  for tag in "${FAILED_TAGS[@]}"; do
    echo "  - $tag"
  done
  exit $EXIT_GENERAL_ERROR
fi

# Summary
echo "✅ Successfully published container image"
echo ""
echo "Repository: $PLP_IMAGE_REPOSITORY"
echo ""
echo "Available tags:"
echo "  $PLP_IMAGE_REPOSITORY:$PRIMARY_TAG"
for tag in "${ADDITIONAL_TAGS[@]}"; do
  echo "  $PLP_IMAGE_REPOSITORY:$tag"
done
echo ""

exit $EXIT_SUCCESS
