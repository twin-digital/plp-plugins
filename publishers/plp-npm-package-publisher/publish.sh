#!/bin/bash
set -euo pipefail

# Exit codes
EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_AUTH_FAILURE=2
EXIT_VALIDATION_FAILURE=3
EXIT_MISSING_VAR=4

echo "PLP NPM Package Publisher"
echo ""

# Set default registry if not provided
PLP_NPM_REGISTRY="${PLP_NPM_REGISTRY:-https://registry.npmjs.org}"

# Validate required environment variables
REQUIRED_VARS=(
  "PLP_ARTIFACT_PATH"
  "PLP_COMMIT_SHA"
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

# Validate artifact file exists
if [ ! -f "$PLP_ARTIFACT_PATH" ]; then
  echo "❌ Error: Artifact file not found at $PLP_ARTIFACT_PATH"
  exit $EXIT_VALIDATION_FAILURE
fi

# Validate artifact is a tarball
if ! tar -tzf "$PLP_ARTIFACT_PATH" > /dev/null 2>&1; then
  echo "❌ Error: Artifact is not a valid tarball"
  exit $EXIT_VALIDATION_FAILURE
fi

echo "Configuration:"
echo "  Artifact path: $PLP_ARTIFACT_PATH"
echo "  Registry: $PLP_NPM_REGISTRY"
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

# Extract package metadata from tarball without fully extracting
echo "Reading package metadata..."
PACKAGE_JSON_CONTENT=$(tar -xzf "$PLP_ARTIFACT_PATH" -O package/package.json 2>/dev/null || tar -xzf "$PLP_ARTIFACT_PATH" -O ./package.json 2>/dev/null)

if [ -z "$PACKAGE_JSON_CONTENT" ]; then
  echo "❌ Error: package.json not found in artifact"
  exit $EXIT_VALIDATION_FAILURE
fi

# Extract package metadata
PACKAGE_NAME=$(echo "$PACKAGE_JSON_CONTENT" | jq -r '.name')
PACKAGE_VERSION=$(echo "$PACKAGE_JSON_CONTENT" | jq -r '.version')

if [ -z "$PACKAGE_NAME" ] || [ "$PACKAGE_NAME" = "null" ]; then
  echo "❌ Error: Package name not found in package.json"
  exit $EXIT_VALIDATION_FAILURE
fi

if [ -z "$PACKAGE_VERSION" ] || [ "$PACKAGE_VERSION" = "null" ]; then
  echo "❌ Error: Package version not found in package.json"
  exit $EXIT_VALIDATION_FAILURE
fi

echo "Package information:"
echo "  Name: $PACKAGE_NAME"
echo "  Version: $PACKAGE_VERSION"
echo ""

# Determine if package should be published based on git context
SHOULD_PUBLISH=false
PUBLISH_TAG="latest"

# Tag builds - always publish with version tag
if [ -n "${PLP_TAG_NAME:-}" ]; then
  SHOULD_PUBLISH=true
  PUBLISH_TAG="latest"
  echo "✅Tagged build - will publish with 'latest' tag"
fi

# Default branch builds - publish with 'latest' tag
if [ "${PLP_IS_DEFAULT_BRANCH:-}" = "true" ]; then
  SHOULD_PUBLISH=true
  PUBLISH_TAG="latest"
  echo "✅ Default branch build - will publish with 'latest' tag"
fi

# Non-default branch builds - publish with branch-specific tag
if [ -n "${PLP_BRANCH_NAME:-}" ] && [ "${PLP_IS_DEFAULT_BRANCH:-}" != "true" ]; then
  SHOULD_PUBLISH=true
  # Sanitize branch name for npm tag (alphanumeric, dash, underscore only)
  PUBLISH_TAG=$(echo "$PLP_BRANCH_NAME" | sed 's/[^a-zA-Z0-9._-]/-/g')
  echo "✅ Branch build - will publish with '$PUBLISH_TAG' tag"
fi

# Pull request builds - skip publishing by default
if [ -n "${PLP_PULL_REQUEST_NUMBER:-}" ]; then
  if [ "${PLP_PUBLISH_PR:-}" = "true" ]; then
    SHOULD_PUBLISH=true
    PUBLISH_TAG="pr-${PLP_PULL_REQUEST_NUMBER}"
    echo "✅ PR build with PLP_PUBLISH_PR=true - will publish with '$PUBLISH_TAG' tag"
  else
    SHOULD_PUBLISH=false
    echo "   PR build - skipping publish (set PLP_PUBLISH_PR=true to override)"
  fi
fi

if [ "$SHOULD_PUBLISH" != "true" ]; then
  echo ""
  echo "Publish skipped (no matching conditions)"
  echo ""
  echo "To publish, ensure one of:"
  echo "  - This is a tag build"
  echo "  - This is the default branch (PLP_IS_DEFAULT_BRANCH=true)"
  echo "  - This is a branch build"
  echo "  - This is a PR with PLP_PUBLISH_PR=true"
  exit $EXIT_SUCCESS
fi

echo ""
echo "Configuring npm registry..."

# Determine authentication token
NPM_AUTH_TOKEN=""

if [ -n "${PLP_REGISTRY_TOKEN:-}" ]; then
  # Use provided token
  echo "Using provided PLP_REGISTRY_TOKEN for authentication"
  NPM_AUTH_TOKEN="$PLP_REGISTRY_TOKEN"
elif [ "$PLP_NPM_REGISTRY" = "https://registry.npmjs.org" ]; then
  # Public npm registry - attempt OIDC trusted publishing
  echo "No PLP_REGISTRY_TOKEN provided - attempting npm trusted publishing (OIDC)"
  
  # Get the directory where this script is located
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  
  # Call the OIDC token exchange script
  if ! NPM_AUTH_TOKEN=$("$SCRIPT_DIR/get-npm-oidc-token.sh" "$PACKAGE_NAME"); then
    echo "❌ Error: Failed to obtain npm token via OIDC"
    exit $EXIT_AUTH_FAILURE
  fi
else
  # Non-public registry without token
  echo "❌ Error: PLP_REGISTRY_TOKEN is required for registry: $PLP_NPM_REGISTRY"
  echo "   Either provide PLP_REGISTRY_TOKEN or use the public npm registry with OIDC trusted publishing"
  exit $EXIT_AUTH_FAILURE
fi

echo ""

# Configure npm registry
npm config set registry "$PLP_NPM_REGISTRY"

# Extract registry hostname for authentication
REGISTRY_HOST=$(echo "$PLP_NPM_REGISTRY" | sed -E 's|^https?://||; s|/.*$||')

# Configure authentication
# Use registry-scoped auth token format
npm config set "//$REGISTRY_HOST/:_authToken" "$NPM_AUTH_TOKEN"

echo "  Registry: $PLP_NPM_REGISTRY"
echo "  Host: $REGISTRY_HOST"

# Check if package already exists at this version
echo ""
echo "Checking if package version already exists..."

if npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version > /dev/null 2>&1; then
  EXISTING_VERSION=$(npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version)
  echo "⚠️  Warning: Package $PACKAGE_NAME@$PACKAGE_VERSION already exists in registry"
  echo "   Existing version: $EXISTING_VERSION"
  
  # Check if PLP_ALLOW_REPUBLISH is set
  if [ "${PLP_ALLOW_REPUBLISH:-}" != "true" ]; then
    echo "❌ Error: Cannot republish existing version"
    echo "   Set PLP_ALLOW_REPUBLISH=true to override (may fail if registry doesn't allow)"
    exit $EXIT_VALIDATION_FAILURE
  else
    echo "   PLP_ALLOW_REPUBLISH=true - attempting to republish"
  fi
else
  echo "✅ Version $PACKAGE_VERSION does not exist - safe to publish"
fi

echo ""
echo "Publishing package..."
echo "  Package: $PACKAGE_NAME@$PACKAGE_VERSION"
echo "  Tag: $PUBLISH_TAG"
echo ""

# Determine access level (public/restricted)
ACCESS_FLAG=""
if [ -n "${PLP_NPM_ACCESS:-}" ]; then
  ACCESS_FLAG="--access $PLP_NPM_ACCESS"
  echo "  Access: $PLP_NPM_ACCESS"
fi

# Publish the package directly from the tarball
if ! npm publish "$PLP_ARTIFACT_PATH" $ACCESS_FLAG --tag "$PUBLISH_TAG" 2>&1; then
  echo ""
  echo "❌ Error: Failed to publish package"
  exit $EXIT_GENERAL_ERROR
fi

echo ""
echo "✅ Successfully published NPM package"
echo ""
echo "Package: $PACKAGE_NAME@$PACKAGE_VERSION"
echo "Registry: $PLP_NPM_REGISTRY"
echo "Tag: $PUBLISH_TAG"
echo ""
echo "Install with:"
echo "  npm install $PACKAGE_NAME@$PUBLISH_TAG"
echo ""

exit $EXIT_SUCCESS
