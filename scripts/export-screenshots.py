#!/usr/bin/env python3
"""从 .xcresult 导出截图附件，按测试里起的名字重命名。

用法：python3 scripts/export-screenshots.py Result.xcresult 输出目录
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

result, out = sys.argv[1], sys.argv[2]
if not os.path.exists(result):
    print("没有结果文件：" + result)
    sys.exit(0)
os.makedirs(out, exist_ok=True)
tmp = tempfile.mkdtemp()
subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", tmp], check=True)

manifest = json.load(open(os.path.join(tmp, "manifest.json")))
count = 0
for test in manifest:
    for a in test.get("attachments", []):
        exported = a["exportedFileName"]
        name = a.get("suggestedHumanReadableName") or exported
        # 例如 “01-今日_0_6B1E….png” → “01-今日.png”
        m = re.match(r"^(.*?)_\d+_[0-9A-Fa-f-]{8,}(\.\w+)$", name)
        if m:
            name = m.group(1) + m.group(2)
        shutil.copy(os.path.join(tmp, exported), os.path.join(out, name))
        count += 1
print("导出 {} 张截图到 {}".format(count, out))
for f in sorted(os.listdir(out)):
    print("  " + f)
