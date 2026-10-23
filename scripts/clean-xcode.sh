#!/usr/bin/env bash
# 清理 Xcode 缓存（在 Mac 上运行，不影响仓库代码）：
# - 编译缓存 DerivedData（编译出现莫名错误时先清这个）
# - 已失效的模拟器（对应的系统版本已卸载）
# - 旧的真机调试符号 iOS / watchOS DeviceSupport（每个平台只保留最新的 KEEP 个版本）
# - 模拟器与 Xcode 的临时缓存
# 加 --runtimes 时，同时删除 30 天没用过的模拟器系统（本项目真机运行不需要模拟器）。
#
# 用法：scripts/clean-xcode.sh [--yes] [--runtimes] [--keep N]
set -euo pipefail

YES=NO
RUNTIMES=NO
KEEP=1
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) YES=YES ;;
    --runtimes) RUNTIMES=YES ;;
    --keep) KEEP="$2"; shift ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
  shift
done

DEV=~/Library/Developer
TARGETS=()
[ -d "$DEV/Xcode/DerivedData" ] && TARGETS+=("$DEV/Xcode/DerivedData")
[ -d "$DEV/CoreSimulator/Caches" ] && TARGETS+=("$DEV/CoreSimulator/Caches")
[ -d ~/Library/Caches/com.apple.dt.Xcode ] && TARGETS+=(~/Library/Caches/com.apple.dt.Xcode)
for dir in "$DEV/Xcode/iOS DeviceSupport" "$DEV/Xcode/watchOS DeviceSupport"; do
  [ -d "$dir" ] || continue
  # 目录名形如 "iPhone15,2 18.1 (22B83)" 或 "18.1 (22B83)"，按系统版本排序，保留最新的 KEEP 个
  while IFS= read -r old; do
    [ -n "$old" ] && TARGETS+=("$dir/$old")
  done < <(ls -1 "$dir" | awk '{
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)+$/) {
        n = split($i, v, "."); printf "%04d%04d%04d\t%s\n", v[1], v[2], (n > 2 ? v[3] : 0), $0; break
      }
    }' | sort -r | cut -f2- | tail -n +"$((KEEP + 1))")
done

echo "将删除："
for t in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  printf '  %6s  %s\n' "$(du -sh "$t" 2>/dev/null | cut -f1)" "$t"
done
echo "  以及已失效的模拟器（xcrun simctl delete unavailable）"
[ "$RUNTIMES" = YES ] && echo "  以及 30 天没用过的模拟器系统（xcrun simctl runtime delete --notUsedSinceDays 30）"

if [ "$YES" != YES ]; then
  read -r -p "确认删除？[y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ] || { echo "已取消"; exit 0; }
fi

for t in "${TARGETS[@]+"${TARGETS[@]}"}"; do rm -rf "$t"; done
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl delete unavailable
[ "$RUNTIMES" = YES ] && xcrun simctl runtime delete --notUsedSinceDays 30
echo "完成。重新打开 Xcode 后第一次编译会慢一些。"
