#!/usr/bin/env python3
"""从 `xcrun simctl list devices available -j` 里选最新系统版本的模拟器，打印 UDID。

用法：xcrun simctl list devices available -j | python3 scripts/pick-simulator.py iOS iPhone
"""
import json
import sys

platform, prefix = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"]


def version(runtime):
    tail = runtime.rsplit(".", 1)[-1]  # 例如 iOS-26-2
    return [int(x) for x in tail.split("-")[1:] if x.isdigit()]


for runtime in sorted((r for r in devices if ".{}-".format(platform) in r), key=version, reverse=True):
    for d in devices[runtime]:
        if d["name"].startswith(prefix):
            print(d["udid"])
            sys.exit(0)
sys.exit("没有可用的 {} 模拟器（{}）".format(platform, prefix))
