import os
import re
from datetime import datetime, timezone, timedelta


def _beijing_now():
    return datetime.now(timezone(timedelta(hours=8)))


def patch_pubspec():
    tag = os.environ.get("GITHUB_REF_NAME", "v1").lstrip("v")
    build = re.sub(r"\D", "", tag)
    # Android versionCode 是 32 位有符号整数，最大 2147483647
    # tag 形如 v260816-2057 -> 2608162057（10 位）会溢出，取后 8 位 MMDDHHMM
    build = build[-8:] if len(build) >= 8 else (build or "1")
    with open("pubspec.yaml", encoding="utf-8") as f:
        s = f.read()
    # 默认自动递增 patch 位：1.0.0 -> 1.0.1；major/minor 需要手动改 pubspec 指定
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)", s, flags=re.M)
    if m:
        major, minor, patch, _ = m.groups()
        new_patch = str(int(patch) + 1)
        version_name = f"{major}.{minor}.{new_patch}"
    else:
        version_name = "1.0.1"
    s = re.sub(r"^version: .+", f"version: {version_name}+{build}", s, flags=re.M)
    with open("pubspec.yaml", "w", encoding="utf-8") as f:
        f.write(s)
    print("version:", f"{version_name}+{build}")
    return version_name, build, tag


def patch_build_gradle():
    p = "android/app/build.gradle"
    with open(p, encoding="utf-8") as f:
        s = f.read()
    # Flutter 模板默认已带 signingConfigs.debug，之前因为 "signingConfigs" 已存在
    # 没替换，导致 release 仍用模板 debug keystore，签名与 jizhang.p12 不一致。
    # 这里强制替换整个 signingConfigs 块，并确保 release 使用它。
    signing_block = '''    signingConfigs {
        debug {
            storeFile rootProject.file("../jizhang.p12")
            storePassword "jizhang123"
            keyAlias "jizhang"
            keyPassword "jizhang123"
            storeType "PKCS12"
        }
    }
'''
    # 替换已有的 signingConfigs { ... } 块
    s = re.sub(
        r'    signingConfigs \{[\s\S]*?\n    \}',
        signing_block.rstrip(),
        s,
    )
    # 兜底：如果没找到（模板结构不同），在 android { 后第一个配置项前插入
    if "jizhang.p12" not in s:
        idx = s.find("android {")
        if idx != -1:
            rest = s[idx + len("android {"):]
            match = re.search(r"\n(    \S)", rest)
            if match:
                insert_pos = idx + len("android {") + match.start() + 1
                s = s[:insert_pos] + signing_block + s[insert_pos:]
            else:
                s = s.replace("android {", "android {\n" + signing_block, 1)
    # 确保 release 构建类型使用 signingConfigs.debug（兼容 signingConfig 与 signingConfig = 两种写法）
    has_release_signing = re.search(
        r'release\s*\{[\s\S]*?signingConfig\s*=?\s*signingConfigs\.debug', s) is not None
    if not has_release_signing:
        s = re.sub(
            r'(    buildTypes \{[\s\S]*?release\s*\{[\s\S]*?)\n        \}',
            r'\1            signingConfig signingConfigs.debug\n        }',
            s,
        )
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("build.gradle patched (signingConfig -> jizhang.p12)")


def patch_manifest():
    p = "android/app/src/main/AndroidManifest.xml"
    with open(p, encoding="utf-8") as f:
        s = f.read()
    s = re.sub(r'android:label="[^"]*"', 'android:label="记账本"', s)
    # usesCleartextTraffic 必须是 <application> 的属性，<manifest> 上无效
    if "usesCleartextTraffic" not in s:
        s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
    # 显式引用 network_security_config，比单独 usesCleartextTraffic 更稳
    if "networkSecurityConfig" not in s:
        s = s.replace("<application", '<application android:networkSecurityConfig="@xml/network_security_config"', 1)
    # 只保留 INTERNET 权限，去掉 Flutter 模板可能带的不必要权限，减少安装时 allow 提示
    lines = s.splitlines()
    filtered = []
    has_internet = False
    manifest_open_idx = -1
    for i, line in enumerate(lines):
        if manifest_open_idx == -1 and "<manifest" in line:
            manifest_open_idx = i
        if "<uses-permission" in line:
            if 'android.permission.INTERNET' in line:
                has_internet = True
                filtered.append(line)
            continue
        filtered.append(line)
    if not has_internet and manifest_open_idx != -1:
        # 确保 INTERNET 权限一定存在，插在 <manifest> 之后
        filtered.insert(manifest_open_idx + 1, '    <uses-permission android:name="android.permission.INTERNET" />')
    s = "\n".join(filtered)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("manifest patched")


def patch_network_security_config():
    dir_path = "android/app/src/main/res/xml"
    os.makedirs(dir_path, exist_ok=True)
    p = os.path.join(dir_path, "network_security_config.xml")
    xml = '''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
'''
    with open(p, "w", encoding="utf-8") as f:
        f.write(xml)
    print("network_security_config.xml created")


def patch_build_info(version_name, build, tag):
    """生成 build_info.dart，供 APP 展示版本号与构建时间。"""
    os.makedirs("lib/core", exist_ok=True)
    p = "lib/core/build_info.dart"
    build_time = _beijing_now().strftime("%Y-%m-%d %H:%M")
    content = f'''// 由 scripts/patch_android.py 自动生成，请勿手动修改。
class BuildInfo {{
  static const String version = '{version_name}';
  static const String buildNumber = '{build}';
  static const String tag = '{tag}';
  static const String buildTime = '{build_time}';
}}
'''
    with open(p, "w", encoding="utf-8") as f:
        f.write(content)
    print("build_info.dart created")


if __name__ == "__main__":
    version_name, build, tag = patch_pubspec()
    patch_build_gradle()
    patch_manifest()
    patch_network_security_config()
    patch_build_info(version_name, build, tag)
