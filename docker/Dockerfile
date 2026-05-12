FROM --platform=linux/amd64 alpine:3.22

# Small docker image to allow using fasm on macOS with Apple Silicon (arm64).

RUN apk add --no-cache curl tar gzip \
    && curl -L -o /tmp/fasm.tgz https://flatassembler.net/fasm-1.73.35.tgz \
    && tar -xzf /tmp/fasm.tgz -C /opt \
    && rm /tmp/fasm.tgz

ENV PATH="/opt/fasm:${PATH}"

ENTRYPOINT ["fasm"]
