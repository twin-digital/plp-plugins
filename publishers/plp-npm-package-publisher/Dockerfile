FROM node:22-alpine

# Install bash and jq for scripting
RUN apk add --no-cache \
    bash \
    curl \
    jq

# Enable corepack for package manager management
RUN corepack enable

# Create non-root user
RUN addgroup -S plp && adduser -S plp -G plp

# Copy scripts
COPY publish.sh /usr/local/bin/publish.sh
COPY get-npm-oidc-token.sh /usr/local/bin/get-npm-oidc-token.sh
RUN chmod +x /usr/local/bin/publish.sh /usr/local/bin/get-npm-oidc-token.sh

# Switch to non-root user
USER plp

ENTRYPOINT ["/usr/local/bin/publish.sh"]
