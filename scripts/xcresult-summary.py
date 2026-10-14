#!/usr/bin/env python3
"""打印 xcresulttool 的测试摘要；没有运行任何测试或有失败时返回非零。"""
import json
import sys

summary = json.load(open(sys.argv[1]))
total = summary.get("totalTestCount", 0)
failed = summary.get("failedTests", 0)
print("结果 {}：通过 {}，失败 {}，跳过 {}，共 {}".format(
    summary.get("result"), summary.get("passedTests"), failed, summary.get("skippedTests"), total))
for f in summary.get("testFailures", []):
    print("✘", f.get("testName"), f.get("failureText"))
sys.exit(0 if total > 0 and failed == 0 else 1)
