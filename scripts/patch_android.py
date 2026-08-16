import os
import re


def patch_pubspec():
    tag = os.environ.get("GITHUB_REF_NAME", "v1").lstrip("v")
    build = re.sub(r"\D", "", tag)
    # Android versionCode 是 32 位有符号整数，最大 2147483647
    # tag 形如 v260816-2057 -> 2608162057（10 位）会溢出，取后 8 位 MMDDHHMM
    build = build[-8:] if len(build) >= 8 else (build or "1")
    with open("pubspec.yaml", encoding="utf-8") as f:
        s = f.read()
    s = re.sub(r"^version: .+", f"version: 1.0.0+{build}", s, flags=re.M)
    with open("pubspec.yaml", "w", encoding="utf-8") as f:
        f.write(s)
    print("version:", f"1.0.0+{build}")


def patch_build_gradle():
    p = "android/app/build.gradle"
    with open(p, encoding="utf-8") as f:
        s = f.read()
    # 覆盖 AGP 自动生成的 debug signingConfig，使其指向仓库中固定的 PKCS12 签名文件。
    # release 构建沿用 signingConfigs.debug（始终存在），避免新增 signingConfigs.release
    # 导致 “Could not get unknown property 'release'” 的 Gradle 错误。
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
    if "signingConfigs" not in s:
        # 在 android { 后的第一个配置项之前插入 signingConfigs，避免依赖缩进字符串
        idx = s.find("android {")
        if idx != -1:
            rest = s[idx + len("android {"):]
            match = re.search(r"\n(    \S)", rest)
            if match:
                insert_pos = idx + len("android {") + match.start() + 1
                s = s[:insert_pos] + signing_block + s[insert_pos:]
            else:
                s = s.replace("android {", "android {\n" + signing_block, 1)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("build.gradle patched (debug signingConfig -> jizhang.p12)")


def patch_manifest():
    p = "android/app/src/main/AndroidManifest.xml"
    with open(p, encoding="utf-8") as f:
        s = f.read()
    s = re.sub(r'android:label="[^"]*"', 'android:label="记账本"', s)
    # usesCleartextTraffic 必须是 <application> 的属性，<manifest> 上无效
    if "usesCleartextTraffic" not in s:
        s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("manifest patched")


if __name__ == "__main__":
    patch_pubspec()
    patch_build_gradle()
    patch_manifest()
