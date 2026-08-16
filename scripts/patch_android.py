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
    # 使用仓库中固定的 PKCS12 签名文件，保证每次签名一致，可覆盖安装
    if "signingConfigs" not in s:
        s = s.replace(
            "    buildTypes {",
            '''    signingConfigs {
        release {
            storeFile file("../../jizhang.p12")
            storePassword "jizhang123"
            keyAlias "jizhang"
            keyPassword "jizhang123"
            storeType "PKCS12"
        }
    }

    buildTypes {''',
        )
    s = s.replace("signingConfig = signingConfigs.debug", "signingConfig = signingConfigs.release")
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("build.gradle patched")


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
