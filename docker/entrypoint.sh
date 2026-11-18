#!/bin/sh
set -eu

log() { printf '[dsh] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

DSH_HOME="${DSH_HOME:-/data/.dsh}"
DSH_WORKSPACE="${DSH_WORKSPACE:-/workspace}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
export HOME="${HOME:-/data}" DSH_HOME

version_at() {
  node -e 'try{process.stdout.write(require(process.argv[1]).version)}catch(e){}' \
    "$1/package.json" 2>/dev/null || true
}

installed_version() {
  version_at "$(npm root -g)/@deepseek-ai/dsh"
}

IMAGE_DSH=/usr/local/lib/node_modules/@deepseek-ai/dsh
NPM_PREFIX="${NPM_CONFIG_PREFIX:-/data/.npm-global}"
PERSIST_DSH="$NPM_PREFIX/lib/node_modules/@deepseek-ai/dsh"
SEED_STAMP="$NPM_PREFIX/.seeded-from-image"

export NPM_CONFIG_PREFIX="$NPM_PREFIX"
export PATH="$NPM_PREFIX/bin:$PATH"

dsh_tree_ok() {
  [ -f "$1/lib/bin.js" ] || return 1
  report="$(node /usr/local/bin/check-dsh-tree.js "$1" 2>&1)" && return 0
  printf '%s\n' "$report" | head -n 5 | while IFS= read -r line; do log "  $line"; done
  return 1
}

dsh_entry() {
  if dsh_tree_ok "$PERSIST_DSH"; then
    printf '%s\n' "$PERSIST_DSH/lib/bin.js"
    return 0
  fi
  [ -d "$PERSIST_DSH" ] && log "卷上的 dsh 不完整，使用镜像默认版本 $(version_at "$IMAGE_DSH")"
  if [ -f "$IMAGE_DSH/lib/bin.js" ]; then
    printf '%s\n' "$IMAGE_DSH/lib/bin.js"
    return 0
  fi
  command -v dsh 2>/dev/null || true
}

link_dsh_bin() {
  mkdir -p "$NPM_PREFIX/bin"
  ln -sfn ../lib/node_modules/@deepseek-ai/dsh/lib/bin.js "$NPM_PREFIX/bin/dsh"
}

swap_in() {
  rm -rf "$PERSIST_DSH.old"
  if [ -d "$PERSIST_DSH" ]; then mv "$PERSIST_DSH" "$PERSIST_DSH.old"; fi
  mv "$1" "$PERSIST_DSH"
  rm -rf "$PERSIST_DSH.old"
  link_dsh_bin
}

install_dsh() {
  stage="$NPM_PREFIX/.staging"
  rm -rf "$stage"
  if ! npm install -g --prefix "$stage" "@deepseek-ai/dsh@$1" --no-fund --no-audit --loglevel=error; then
    rm -rf "$stage"
    return 1
  fi
  if ! dsh_tree_ok "$stage/lib/node_modules/@deepseek-ai/dsh"; then
    log "新装的 $1 不完整，丢弃"
    rm -rf "$stage"
    return 1
  fi
  swap_in "$stage/lib/node_modules/@deepseek-ai/dsh"
  rm -rf "$stage"
}

seed_persistent_dsh() {
  image_version="$(version_at "$IMAGE_DSH")"
  [ -n "$image_version" ] || return 0
  if [ -f "$PERSIST_DSH/package.json" ] && [ "$(cat "$SEED_STAMP" 2>/dev/null || true)" = "$image_version" ]; then
    return 0
  fi
  log "持久化 dsh：用镜像里的 ${image_version} 初始化 $NPM_PREFIX"
  mkdir -p "$NPM_PREFIX/lib/node_modules/@deepseek-ai"
  rm -rf "$PERSIST_DSH.tmp"
  if cp -a "$IMAGE_DSH" "$PERSIST_DSH.tmp"; then
    swap_in "$PERSIST_DSH.tmp"
    printf '%s\n' "$image_version" > "$SEED_STAMP"
  else
    rm -rf "$PERSIST_DSH.tmp"
    log "持久化 dsh 失败，继续用镜像里的版本"
  fi
}

newest_version() {
  npm view @deepseek-ai/dsh versions --json --silent 2>/dev/null \
    | node /usr/local/bin/newest-version.js "${DSH_CHANNEL:-rc}" 2>/dev/null || true
}

maybe_auto_update() {
  if [ "${DSH_AUTO_UPDATE:-1}" = "0" ]; then
    log "auto-update: 已关闭"
    return 0
  fi
  log "auto-update: 检查更新 (通道: ${DSH_CHANNEL:-rc})"
  current="$(installed_version)"
  latest="$(newest_version | tail -n1 | tr -d '[:space:]')"
  if [ -z "$latest" ]; then
    log "auto-update: 连不上 registry，继续用 ${current:-未知版本}"
    return 0
  fi
  if [ "$latest" = "$current" ]; then
    log "auto-update: 已是最新 ${current}"
    return 0
  fi
  log "auto-update: ${current:-未知} -> ${latest}"
  if install_dsh "$latest"; then
    log "auto-update: 完成，当前 $(installed_version)"
  else
    log "auto-update: 安装失败，继续用 ${current:-当前版本}"
  fi
}

# 阶段 1：root
if [ "$(id -u)" = "0" ]; then
  for d in "$HOME" "$DSH_HOME" "$DSH_WORKSPACE"; do
    mkdir -p "$d"
    if [ "$(stat -c %u "$d")" != "$PUID" ]; then
      log "修正属主 $d -> ${PUID}:${PGID}"
      chown -R "${PUID}:${PGID}" "$d"
    fi
  done
  seed_persistent_dsh
  if [ -d "$PERSIST_DSH" ] && ! dsh_tree_ok "$PERSIST_DSH"; then
    log "卷上的 dsh 不完整，用镜像重新初始化"
    rm -f "$SEED_STAMP"
    seed_persistent_dsh
  fi
  rm -rf "$NPM_PREFIX/.staging" "$PERSIST_DSH.tmp"
  maybe_auto_update
  if [ -d "$NPM_PREFIX" ] && [ -n "$(find "$NPM_PREFIX" ! -user "$PUID" -print -quit 2>/dev/null)" ]; then
    log "修正 $NPM_PREFIX 属主 -> ${PUID}:${PGID}"
    chown -R "${PUID}:${PGID}" "$NPM_PREFIX"
  fi
  fix-node-pty.sh || log "node-pty 检查异常"
  exec gosu "${PUID}:${PGID}" "$0" "$@"
fi

# 阶段 2：非特权
dsh_bin="$(dsh_entry)"
[ -n "$dsh_bin" ] || die "找不到 dsh，镜像构建异常"
[ -w "$DSH_HOME" ] || die "DSH_HOME=$DSH_HOME 对 uid $(id -u) 不可写"
mkdir -p "$DSH_WORKSPACE"

case "${1:-}" in
  dsh|*/dsh)
    shift
    log "dsh $(version_at "${dsh_bin%/lib/bin.js}") <- $dsh_bin"
    profile="$1"; shift
    set -- "$profile" --patch /etc/dsh/dsh.patch.yml "$@"
    for h in ${DSH_TRUSTED_HOSTS:-}; do
      set -- "$@" --trusted-host "$h"
    done
    [ -n "${DSH_PUBLIC_URL:-}" ] && set -- "$@" --public-url "$DSH_PUBLIC_URL"
    host_addr="$(node -e 'for(const l of Object.values(require("os").networkInterfaces()))for(const a of l||[])if(a.family==="IPv4"&&!a.internal){console.log(a.address);process.exit(0)}')"
    [ -n "$host_addr" ] || die "拿不到容器 IPv4 地址"
    set -- node --expose-internals "$dsh_bin" "$@" --host "$host_addr"
    ;;
esac

log "启动: $*"
exec "$@"
