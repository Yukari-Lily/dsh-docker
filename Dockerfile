# syntax=docker/dockerfile:1
FROM node:24-slim

ARG DSH_VERSION=latest
ARG NPM_REGISTRY=https://registry.npmjs.org/
ARG GYP_DEVDIR=/usr/local/share/node-gyp

ENV HOME=/data \
    DSH_HOME=/data/.dsh \
    npm_config_cache=/tmp/npm-cache \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    TZ=Asia/Shanghai

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        tini gosu git ripgrep jq curl ca-certificates tzdata \
        openssh-client bubblewrap python3 make g++; \
    corepack enable; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    npm install -g node-gyp "@deepseek-ai/dsh@${DSH_VERSION}" \
        --registry="${NPM_REGISTRY}" --no-fund --no-audit --loglevel=error; \
    npm_config_devdir="${GYP_DEVDIR}" node-gyp install

COPY docker/fix-node-pty.sh   /usr/local/bin/
COPY docker/entrypoint.sh     /usr/local/bin/
COPY docker/newest-version.js /usr/local/bin/
COPY docker/check-dsh-tree.js /usr/local/bin/
COPY docker/dsh.patch.yml     /etc/dsh/dsh.patch.yml
RUN chmod +x /usr/local/bin/fix-node-pty.sh /usr/local/bin/entrypoint.sh

RUN GYP_DEVDIR="${GYP_DEVDIR}" /usr/local/bin/fix-node-pty.sh; \
    chown -R node:node /usr/local/lib/node_modules /usr/local/bin

ENV NPM_CONFIG_PREFIX=/data/.npm-global \
    PATH=/data/.npm-global/bin:$PATH

WORKDIR /workspace
EXPOSE 3080
VOLUME ["/data", "/workspace"]

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["dsh", "web", "--no-open"]
