#!/bin/sh
set -eu

GYP_DEVDIR="${GYP_DEVDIR:-/usr/local/share/node-gyp}"
dsh_root="$(npm root -g)/@deepseek-ai/dsh"
pty="$dsh_root/node_modules/node-pty"

[ -d "$pty" ] || exit 0

loadable() {
  node -e 'require(process.argv[1])' "$pty" >/dev/null 2>&1
}

if loadable; then
  exit 0
fi

printf '[dsh] node-pty 加载失败，现存二进制的报错：\n' >&2
node -e 'require(process.argv[1])' "$pty" 2>&1 | head -n 20 >&2 || true

if [ -d "$pty/build" ]; then
  printf '[dsh] 清除 %s\n' "$pty/build" >&2
  rm -rf "$pty/build"
  if loadable; then
    printf '[dsh] node-pty 使用 prebuilds 成功\n' >&2
    exit 0
  fi
fi

printf '[dsh] 重新编译 node-pty…\n' >&2
cd "$pty"
npm_config_devdir="$GYP_DEVDIR" node-gyp rebuild

if loadable; then
  printf '[dsh] node-pty 编译完成\n' >&2
  exit 0
fi

printf '[dsh] node-pty 编译后仍加载失败：\n' >&2
node -e 'require(process.argv[1])' "$pty" 2>&1 | head -n 40 >&2 || true
exit 1
