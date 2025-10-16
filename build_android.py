#!/usr/bin/env python3
import os
import subprocess
import sys

# ======================
# 配置区
# ======================
project_dir = os.path.dirname(os.path.abspath(__file__))  # Flutter 项目根目录
flavor = None  # 可选: "dev", "prod" 等
build_mode = "release"  # debug, profile, release
output_dir = os.path.join(project_dir, "build_output", "apk")

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
run("flutter clean")

# 构建 APK
cmd = "flutter build apk"
if build_mode:
    cmd += f" --{build_mode}"
if flavor:
    cmd += f" --flavor {flavor}"
cmd += f" --target-platform android-arm,android-arm64,android-x64"

run(cmd)

# 移动 APK 到自定义目录
apk_path = os.path.join(project_dir, "build", "app", "outputs", "flutter-apk", f"app-{build_mode}.apk")
if os.path.exists(apk_path):
    dest_path = os.path.join(output_dir, f"app-{build_mode}.apk")
    os.replace(apk_path, dest_path)
    print(f"APK generated: {dest_path}")
else:
    print("APK not found, build may have failed")
