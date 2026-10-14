#!/usr/bin/env bash
# 在 Linux（Ubuntu 24.04）云端会话里安装 Swift 工具链，用于运行 `swift test`。
# 优先从 download.swift.org 下载；被网络策略拦截时，退回到 Docker Hub 的官方 swift 镜像。
set -euo pipefail

VERSION="${SWIFT_VERSION:-6.1.3}"
PREFIX="/opt/swift-${VERSION}"

if command -v swift >/dev/null 2>&1; then
  swift --version
  exit 0
fi

TARBALL="swift-${VERSION}-RELEASE-ubuntu24.04"
URL="https://download.swift.org/swift-${VERSION}-release/ubuntu2404/swift-${VERSION}-RELEASE/${TARBALL}.tar.gz"

mkdir -p "$PREFIX"
if curl -fsSL "$URL" -o "/tmp/${TARBALL}.tar.gz"; then
  tar -xzf "/tmp/${TARBALL}.tar.gz" -C "$PREFIX" --strip-components=1
else
  echo "download.swift.org 不可用，改用 Docker 镜像 swift:${VERSION%.*}-noble" >&2
  if ! docker info >/dev/null 2>&1; then
    (dockerd >/tmp/dockerd.log 2>&1 &)
    for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  fi
  docker pull "swift:${VERSION%.*}-noble"
  cid=$(docker create "swift:${VERSION%.*}-noble")
  docker cp "$cid:/usr" "$PREFIX/"
  docker rm "$cid" >/dev/null
fi

# 只链接 swift 相关命令，避免工具链目录里的其他程序覆盖系统命令
for f in "$PREFIX"/usr/bin/swift "$PREFIX"/usr/bin/swiftc "$PREFIX"/usr/bin/swift-*; do
  ln -sf "$f" /usr/local/bin/
done
swift --version
