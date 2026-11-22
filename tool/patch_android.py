"""자동 제작 때 안드로이드 설정을 맞춘다: 인터넷·위치 권한, 앱 이름, 바깥 링크 열기 허용."""
import re
import sys

path = "android/app/src/main/AndroidManifest.xml"
label = sys.argv[1] if len(sys.argv) > 1 else "콕플"
s = open(path, encoding="utf-8").read()

if "android.permission.INTERNET" not in s:
    s = s.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

# 내 주변 맛집: 위치 권한
for perm in ("ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION"):
    if f"android.permission.{perm}" not in s:
        s = s.replace("<application", f'<uses-permission android:name="android.permission.{perm}"/>\n    <application', 1)

s = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s, count=1)

if "android.intent.action.DIAL" not in s:
    extra = """
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="mailto" />
        </intent>"""
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>" + extra, 1)
    else:
        s = s.replace("</manifest>", "    <queries>" + extra + "\n    </queries>\n</manifest>", 1)

open(path, "w", encoding="utf-8").write(s)

# 출시용 만들 때 린트 검사 끄기 (영상 재생 부품의 린트 도구가 깨져 제작이 멈춤)
import os
for gp, line in (("android/app/build.gradle.kts", "    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }\n"),
                 ("android/app/build.gradle", "    lint {\n        checkReleaseBuilds false\n        abortOnError false\n    }\n")):
    if os.path.exists(gp):
        g = open(gp, encoding="utf-8").read()
        if "checkReleaseBuilds" not in g:
            g = g.replace("android {\n", "android {\n" + line, 1)
            open(gp, "w", encoding="utf-8").write(g)
# 고정 서명: android/app/upload.jks 가 있으면 그 키로 (비밀번호는 KEY_PASS 환경 변수)
kts = "android/app/build.gradle.kts"
if os.path.exists(kts):
    g = open(kts, encoding="utf-8").read()
    if 'create("upload")' not in g:
        g = g.replace("    buildTypes {", """    signingConfigs {
        create("upload") {
            storeFile = file("upload.jks")
            storePassword = System.getenv("KEY_PASS")
            keyAlias = "kokple"
            keyPassword = System.getenv("KEY_PASS")
        }
    }

    buildTypes {""", 1)
        g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = if (file("upload.jks").exists()) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")', 1)
        open(kts, "w", encoding="utf-8").write(g)
grv = "android/app/build.gradle"
if os.path.exists(grv):
    g = open(grv, encoding="utf-8").read()
    if "upload.jks" not in g:
        g = g.replace("    buildTypes {", """    signingConfigs {
        upload {
            storeFile file("upload.jks")
            storePassword System.getenv("KEY_PASS")
            keyAlias "kokple"
            keyPassword System.getenv("KEY_PASS")
        }
    }

    buildTypes {""", 1)
        g = g.replace("signingConfig signingConfigs.debug", 'signingConfig file("upload.jks").exists() ? signingConfigs.upload : signingConfigs.debug', 1)
        open(grv, "w", encoding="utf-8").write(g)
print("안드로이드 설정 완료")
