# PLP Container Image Publisher

Publisher plugin for publishing OCI container images to container registries.

## Features

- Publishes OCI images from tarball archives to any OCI-compliant registry
- Intelligent tagging based on git context (branches, tags, PRs)
- Supports semver tag expansion (e.g., `v1.2.3` → `1.2.3`, `1.2`, `1`)
- Uses `skopeo` for efficient, registry-native image copying
- Runs as non-root user for security
- Comprehensive validation and error handling

## Environment Variables

### Required

| Variable                | Description                             | Example                                    |
| ----------------------- | --------------------------------------- | ------------------------------------------ |
| `PLP_IMAGE_PATH`        | Path to the OCI image tarball           | `/artifacts/image.tar`                     |
| `PLP_IMAGE_REPOSITORY`  | Full repository path including registry | `ghcr.io/org/repo/image`                   |
| `PLP_COMMIT_SHA`        | Git commit SHA                          | `6c2271197bf6c7aae6d17545abdd67586af1171d` |
| `PLP_REGISTRY_USERNAME` | Registry username                       | `github-username`                          |
| `PLP_REGISTRY_PASSWORD` | Registry password/token                 | `ghp_xxxxx`                                |

At least one of the following must also be set:

- `PLP_BRANCH_NAME`
- `PLP_TAG_NAME`
- `PLP_PULL_REQUEST_NUMBER`

### Optional

| Variable                   | Description                      | Example           |
| -------------------------- | -------------------------------- | ----------------- |
| `PLP_BRANCH_NAME`          | Git branch name                  | `main`, `develop` |
| `PLP_IS_DEFAULT_BRANCH`    | Set to `true` for default branch | `true`            |
| `PLP_TAG_NAME`             | Git tag name                     | `v1.2.3`          |
| `PLP_PULL_REQUEST_NUMBER`  | Pull request number              | `123`             |
| `PLP_MERGE_REQUEST_NUMBER` | Alias for PR number (GitLab)     | `123`             |

## Tagging Behavior

### Branch Builds

Tags applied:

- `{branch-name}`
- `{branch-name}-{short-sha}`
- `latest` (only if `PLP_IS_DEFAULT_BRANCH=true`)

Example:

```bash
PLP_BRANCH_NAME=main
PLP_IS_DEFAULT_BRANCH=true
PLP_COMMIT_SHA=6c2271197bf6c7aae6d17545abdd67586af1171d
```

Results in tags: `main`, `main-6c22711`, `latest`

### Pull Request Builds

Tags applied:

- `pr-{number}`
- `pr-{number}-{short-sha}`

Example:

```bash
PLP_PULL_REQUEST_NUMBER=123
PLP_COMMIT_SHA=6c2271197bf6c7aae6d17545abdd67586af1171d
```

Results in tags: `pr-123`, `pr-123-6c22711`

### Tag Builds (Semver)

Tags applied:

- `{tag-name}`
- `{major}.{minor}.{patch}` (if semver format)
- `{major}.{minor}` (if semver format)
- `{major}` (if semver format)

Example:

```bash
PLP_TAG_NAME=v1.2.3
```

Results in tags: `v1.2.3`, `1.2.3`, `1.2`, `1`

### Tag Builds (Non-Semver)

Tags applied:

- `{tag-name}`

Example:

```bash
PLP_TAG_NAME=release-2024
```

Results in tags: `release-2024`

## Usage

### Docker

```bash
docker run --rm \
  -e PLP_IMAGE_PATH=/artifacts/image.tar \
  -e PLP_IMAGE_REPOSITORY=ghcr.io/myorg/myapp \
  -e PLP_BRANCH_NAME=main \
  -e PLP_IS_DEFAULT_BRANCH=true \
  -e PLP_COMMIT_SHA=6c2271197bf6c7aae6d17545abdd67586af1171d \
  -e PLP_REGISTRY_USERNAME=myuser \
  -e PLP_REGISTRY_PASSWORD=ghp_xxxxx \
  -v /path/to/image.tar:/artifacts/image.tar:ro \
  ghcr.io/twin-digital/plp-plugins/plp-container-image-publisher
```

### GitHub Actions (example)

```yaml
- name: Publish container image
  run: |
    docker run --rm \
      -e PLP_IMAGE_PATH=/artifacts/image.tar \
      -e PLP_IMAGE_REPOSITORY=ghcr.io/${{ github.repository }}/myapp \
      -e PLP_BRANCH_NAME=${{ github.ref_name }} \
      -e PLP_IS_DEFAULT_BRANCH=${{ github.ref == format('refs/heads/{0}', github.event.repository.default_branch) }} \
      -e PLP_COMMIT_SHA=${{ github.sha }} \
      -e PLP_REGISTRY_USERNAME=${{ github.actor }} \
      -e PLP_REGISTRY_PASSWORD=${{ secrets.GITHUB_TOKEN }} \
      -v ${{ runner.temp }}/image.tar:/artifacts/image.tar:ro \
      ghcr.io/twin-digital/plp-plugins/plp-container-image-publisher
```

## Exit Codes

| Code | Meaning                               |
| ---- | ------------------------------------- |
| 0    | Success                               |
| 1    | General error                         |
| 2    | Authentication failure                |
| 3    | Artifact validation failure           |
| 4    | Missing required environment variable |

## Supported Registries

This publisher supports any OCI-compliant container registry.

## Building

```bash
docker build -t ghcr.io/twin-digital/plp-plugins/plp-container-image-publisher .
```

## Security

- Runs as non-root user (`plp`)
- Credentials are never logged
- Image validation before publishing
- Uses official `skopeo` from Alpine packages
- Minimal attack surface with Alpine base image
