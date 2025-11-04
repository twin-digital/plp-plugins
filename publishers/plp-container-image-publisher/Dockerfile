FROM alpine:3.22

# Install skopeo for OCI image operations
RUN apk add --no-cache \
    skopeo \
    bash \
    jq

# Create non-root user
RUN addgroup -S plp && adduser -S plp -G plp

# Copy entrypoint script
COPY publish.sh /usr/local/bin/publish.sh
RUN chmod +x /usr/local/bin/publish.sh

# Switch to non-root user
USER plp

ENTRYPOINT ["/usr/local/bin/publish.sh"]
