#!/usr/bin/env python3
"""为截图目录生成 README.md，在 GitHub 上直接浏览。

用法：python3 scripts/screenshot-index.py screenshots <提交>
"""
import os
import sys
import urllib.parse

root, commit = sys.argv[1], sys.argv[2]
lines = ["# 界面截图（演示数据）", "", "由 CI 在提交 `{}` 上自动生成，每次推送到 main 时更新。".format(commit), ""]
for section, title in [("iphone", "iPhone"), ("watch", "Apple Watch")]:
    d = os.path.join(root, section)
    files = sorted(f for f in os.listdir(d) if f.endswith(".png")) if os.path.isdir(d) else []
    lines += ["## " + title, ""]
    if not files:
        lines += ["（这次没有截图，请看 CI 日志）", ""]
        continue
    width = 300 if section == "iphone" else 200
    for f in files:
        path = urllib.parse.quote("{}/{}".format(section, f))
        lines += ["**{}**".format(os.path.splitext(f)[0]), "", '<img src="{}" width="{}">'.format(path, width), ""]
open(os.path.join(root, "README.md"), "w").write("\n".join(lines))
print("已生成 {}/README.md".format(root))
