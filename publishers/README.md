# Publisher Plugins

Publisher plugins are responsible for taking built artifacts and publishing them to their respective registries or repositories.

## Contract

All publisher plugins must adhere to the following contract:

### Execution Model

- Publishers are executed as containers
- Artifacts are mounted into the container at paths specified by environment variables
- Publishers authenticate to their target registries using credentials provided via environment variables
- Publishers must exit with code `0` on success, non-zero on failure

### Common Environment Variables

All publisher plugins receive the following environment variables:

| Variable                   | Description                                 | Example                                    | Required |
| -------------------------- | ------------------------------------------- | ------------------------------------------ | -------- |
| `PLP_BRANCH_NAME`          | Name of the git branch                      | `main`, `develop`, `feature/xyz`           | No\*     |
| `PLP_IS_DEFAULT_BRANCH`    | Set to `true` if this is the default branch | `true`                                     | No       |
| `PLP_PULL_REQUEST_NUMBER`  | Pull request number (if applicable)         | `123`                                      | No       |
| `PLP_MERGE_REQUEST_NUMBER` | Alias for `PLP_PULL_REQUEST_NUMBER`         | `123`                                      | No       |
| `PLP_TAG_NAME`             | Git tag name (if applicable)                | `v1.2.3`, `release-2024`                   | No       |
| `PLP_COMMIT_SHA`           | Full git commit SHA                         | `6c2271197bf6c7aae6d17545abdd67586af1171d` | Yes      |

\* At least one of `PLP_BRANCH_NAME`, `PLP_TAG_NAME`, or `PLP_PULL_REQUEST_NUMBER` will be set.

### Artifact-Specific Variables

Each publisher type defines additional environment variables specific to the artifact type being published.

### Authentication

Publishers receive authentication credentials via environment variables:

- Variable names are specific to each publisher type
- Credentials should never be logged or exposed
- Publishers should fail fast if required credentials are missing

### Logging

Publishers should provide clear, structured logging:

- Log the final location of published artifacts
- Do not log sensitive information (credentials, tokens)

## Available Publishers

### Container Image Publisher

**Image**: `ghcr.io/twin-digital/plp-plugins/plp-container-image-publisher`

Publishes OCI container images to container registries.

### NPM Package Publisher

**Image**: `ghcr.io/twin-digital/plp-plugins/plp-npm-publisher`

Publishes NPM packages to NPM registries.
