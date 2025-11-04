# PLP NPM Package Publisher

Publisher plugin for publishing NPM packages to npm registries (npm, GitHub Packages, private registries, etc.).

## Features

- Publishes NPM packages from tarball archives to any npm-compatible registry
- Intelligent publishing based on git context (branches, tags, PRs)
- Configurable dist-tags based on branch/tag context
- Version conflict detection with optional override
- Supports scoped and unscoped packages
- Runs as non-root user for security
- Comprehensive validation and error handling

## Environment Variables

### Required

| Variable             | Description                   | Example                                    |
| -------------------- | ----------------------------- | ------------------------------------------ |
| `PLP_ARTIFACT_PATH`  | Path to the package tarball   | `/artifacts/package.tgz`                   |
| `PLP_NPM_REGISTRY`   | NPM registry URL              | `https://registry.npmjs.org`               |
| `PLP_COMMIT_SHA`     | Git commit SHA                | `6c2271197bf6c7aae6d17545abdd67586af1171d` |
| `PLP_REGISTRY_TOKEN` | Registry authentication token | `npm_xxxxx`                                |

At least one of the following must also be set:

- `PLP_BRANCH_NAME`
- `PLP_TAG_NAME`
- `PLP_PULL_REQUEST_NUMBER`

### Optional

| Variable                  | Description                          | Example                   |
| ------------------------- | ------------------------------------ | ------------------------- |
| `PLP_BRANCH_NAME`         | Git branch name                      | `main`, `develop`         |
| `PLP_IS_DEFAULT_BRANCH`   | Set to `true` for default branch     | `true`                    |
| `PLP_TAG_NAME`            | Git tag name                         | `v1.2.3`                  |
| `PLP_PULL_REQUEST_NUMBER` | Pull request number                  | `123`                     |
| `PLP_NPM_ACCESS`          | Package access level                 | `public`, `restricted`    |
| `PLP_PUBLISH_PR`          | Set to `true` to publish PR builds   | `true` (default: `false`) |
| `PLP_ALLOW_REPUBLISH`     | Allow republishing existing versions | `true` (default: `false`) |

## Publishing Behavior

### Tag Builds

**When to publish:** Always

**Dist-tag:** `latest`

**Validation:** Tag should match package version (warns if mismatch)

Example:

```bash
PLP_TAG_NAME=v1.2.3
# Package version in package.json: 1.2.3
```

Result: Publishes `@mypackage@1.2.3` with tag `latest`

### Default Branch Builds

**When to publish:** Always (when `PLP_IS_DEFAULT_BRANCH=true`)

**Dist-tag:** `latest`

Example:

```bash
PLP_BRANCH_NAME=main
PLP_IS_DEFAULT_BRANCH=true
```

Result: Publishes with tag `latest`

### Non-Default Branch Builds

**When to publish:** Always

**Dist-tag:** Sanitized branch name (alphanumeric, dash, underscore only)

Example:

```bash
PLP_BRANCH_NAME=feature/new-api
```

Result: Publishes with tag `feature-new-api`

Users can install with: `npm install mypackage@feature-new-api`

### Pull Request Builds

**When to publish:** Only if `PLP_PUBLISH_PR=true`

**Dist-tag:** `pr-{number}`

**Default:** Skip publishing

Example:

```bash
PLP_PULL_REQUEST_NUMBER=123
PLP_PUBLISH_PR=true
```

Result: Publishes with tag `pr-123`

Users can install with: `npm install mypackage@pr-123`

## Registry Configuration

### npm Registry (Public)

```bash
PLP_NPM_REGISTRY=https://registry.npmjs.org
PLP_REGISTRY_TOKEN=npm_xxxxx  # From npmjs.com account settings
PLP_NPM_ACCESS=public          # Required for scoped packages
```

### GitHub Packages

```bash
PLP_NPM_REGISTRY=https://npm.pkg.github.com
PLP_REGISTRY_TOKEN=ghp_xxxxx  # GitHub Personal Access Token with packages:write
PLP_NPM_ACCESS=public          # Or restricted
```

### Private Registry

```bash
PLP_NPM_REGISTRY=https://registry.example.com
PLP_REGISTRY_TOKEN=your-token
```

## Version Conflict Handling

By default, the publisher will **fail** if the package version already exists in the registry:

```
❌ Error: Cannot republish existing version
   Set PLP_ALLOW_REPUBLISH=true to override
```

To override (useful for private registries that allow overwrites):

```bash
PLP_ALLOW_REPUBLISH=true
```

**Note:** Most public registries (npm, GitHub Packages) do not allow republishing. This setting will still fail at the registry level but won't pre-emptively block the attempt.

## Usage Example

```bash
docker run --rm \
  -e PLP_ARTIFACT_PATH=/artifacts/mypackage-1.2.3.tgz \
  -e PLP_NPM_REGISTRY=https://registry.npmjs.org \
  -e PLP_COMMIT_SHA=6c2271197bf6c7aae6d17545abdd67586af1171d \
  -e PLP_REGISTRY_TOKEN=npm_xxxxx \
  -e PLP_BRANCH_NAME=main \
  -e PLP_IS_DEFAULT_BRANCH=true \
  -e PLP_NPM_ACCESS=public \
  -v /path/to/artifacts:/artifacts:ro \
  ghcr.io/twin-digital/plp-plugins/plp-npm-package-publisher:latest
```

## Exit Codes

| Code | Meaning              | Description                           |
| ---- | -------------------- | ------------------------------------- |
| 0    | Success              | Package published successfully        |
| 1    | General Error        | Unexpected error during publishing    |
| 2    | Authentication Error | Registry authentication failed        |
| 3    | Validation Error     | Invalid artifact or package metadata  |
| 4    | Missing Variable     | Required environment variable not set |

## Security Notes

- **Never commit tokens** to source code
- Use GitHub Actions secrets or similar for `PLP_REGISTRY_TOKEN`
- The container runs as non-root user (`plp:plp`)
- Tokens are only configured in memory, not written to disk
- The working directory is cleaned up on exit

## Common Patterns

### Publish only releases (tags)

Set up workflow to only run publish job on tag pushes:

```yaml
on:
  push:
    tags:
      - "v*"
```

### Branch-specific testing

Developers can test packages from feature branches:

```bash
# Publish from feature/cool-stuff branch
# Creates dist-tag: feature-cool-stuff

npm install mypackage@feature-cool-stuff
```

### Preview PR changes

Enable PR publishing for testing:

```bash
PLP_PUBLISH_PR=true
PLP_PULL_REQUEST_NUMBER=123
# Creates dist-tag: pr-123

npm install mypackage@pr-123
```

## Troubleshooting

### Package already exists

```
⚠️  Warning: Package mypackage@1.2.3 already exists in registry
❌ Error: Cannot republish existing version
```

**Solution:** Increment version in `package.json` before building, or set `PLP_ALLOW_REPUBLISH=true` for private registries that allow it.

### Authentication failed

```
❌ Error: Failed to publish package
npm ERR! code E401
npm ERR! Unable to authenticate
```

**Solution:** Verify `PLP_REGISTRY_TOKEN` is valid for the registry in `PLP_NPM_REGISTRY`.

### Scope mismatch

```
❌ Error: Package scope doesn't match registry
```

**Solution:** For scoped packages on GitHub Packages, ensure the scope matches your organization:

- Package: `@myorg/mypackage`
- Registry: `https://npm.pkg.github.com/@myorg`

### Access denied (public)

```
npm ERR! code E403
npm ERR! You must have two-factor authentication enabled
```

**Solution:** Add `PLP_NPM_ACCESS=public` for scoped packages on public registries.

## Design Philosophy

This publisher follows the Platform Controls Publishing pattern:

- **Registry location** determined by platform (via `PLP_NPM_REGISTRY`)
- **Not** read from `package.json` `publishConfig.registry`
- Allows same code to publish to different registries per environment
- Supports multi-environment workflows (dev → staging → prod)
- Registry credentials managed by CI/CD platform, not source code

The package's `publishConfig` in `package.json` is **ignored** in favor of platform-controlled configuration.
