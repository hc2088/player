#!/usr/bin/env python3
import os
import subprocess
import sys

# ======================
# 配置区
# ======================
project_dir = os.path.dirname(os.path.abspath(__file__))  # Flutter 项目根目录
scheme = "Runner"  # Xcode scheme
workspace = "ios/Runner.xcworkspace"
configuration = "Release"
output_dir = os.path.join(project_dir, "build_output", "ios")

# ======================
# 脚本实现
# ======================
def run(cmd):
    print(f"Running: {cmd}")
    ret = subprocess.run(cmd, shell=True)
    if ret.returncode != 0:
        print("Build failed")
        sys.exit(1)

# 创建输出目录
os.makedirs(output_dir, exist_ok=True)

# Flutter clean（可选）
# run("flutter clean")

# 构建 iOS IPA
cmd = f"flutter build ipa --export-method ad-hoc --scheme {scheme} --configuration {configuration}"
run(cmd)

# 移动 IPA 到自定义目录
ipa_path = os.path.join(project_dir, "build", "ios", "ipa", f"{scheme}.ipa")
if os.path.exists(ipa_path):
    dest_path = os.path.join(output_dir, f"{scheme}.ipa")
    os.replace(ipa_path, dest_path)
    print(f"IPA generated: {dest_path}")
else:
    print("IPA not found, build may have failed")
