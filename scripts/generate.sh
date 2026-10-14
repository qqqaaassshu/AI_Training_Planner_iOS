#!/usr/bin/env bash
# 生成 Xcode 工程：读取 local.env（开发团队、标识前缀、是否免费账号），再运行 XcodeGen。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f local.env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./local.env
  set +a
fi

export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
export BUNDLE_PREFIX="${BUNDLE_PREFIX:-com.example}"
FREE_ACCOUNT="${FREE_ACCOUNT:-NO}"
if [ "$FREE_ACCOUNT" = "YES" ]; then export FULL_CAPABILITIES=NO; else export FULL_CAPABILITIES=YES; fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "没有找到 xcodegen。安装：brew install xcodegen" >&2
  echo "（没有 Homebrew 时，也可以从 https://github.com/yonaskolb/XcodeGen/releases 下载 xcodegen.zip，解压后把 bin/xcodegen 放到 PATH 里）" >&2
  exit 1
fi

echo "开发团队：${DEVELOPMENT_TEAM:-（未设置，需在 Xcode 里选择）}  标识前缀：$BUNDLE_PREFIX  完整能力：$FULL_CAPABILITIES"
xcodegen generate
