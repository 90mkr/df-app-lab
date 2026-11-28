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

# 길안내: 카카오맵·네이버·티맵이 깔렸는지 보고 아이콘을 받으려면 알려 둬야 함 (안드로이드 11부터)
if "net.daum.android.map" not in s:
    nav = """
        <package android:name="net.daum.android.map" />
        <package android:name="com.nhn.android.nmap" />
        <package android:name="com.skt.tmap.ku" />
        <package android:name="com.kakao.talk" />
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="kakaomap" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="nmap" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="tmap" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="market" />
        </intent>"""
    s = s.replace("<queries>", "<queries>" + nav, 1)

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
# 파이어베이스 로그인은 안드로이드 6.0(23) 이상
for gp in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if os.path.exists(gp):
        g = open(gp, encoding="utf-8").read()
        g = g.replace("minSdk = flutter.minSdkVersion", "minSdk = 23").replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 23")
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
# 앱 고유 이름: 플레이 스토어·파이어베이스·네이버 지도에 등록하는 이름은 kr.designfeel.kokple (대표님 11-28)
# 코드 폴더 이름(namespace)은 그대로 두고 설치되는 앱의 이름(applicationId)만 바꾼다
APP_ID = "kr.designfeel.kokple"
for gp in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if os.path.exists(gp):
        g = open(gp, encoding="utf-8").read()
        g2 = re.sub(r'applicationId\s*=?\s*"[^"]*"', lambda m: ('applicationId = "%s"' if "=" in m.group(0) else 'applicationId "%s"') % APP_ID, g, count=1)
        if g2 == g and APP_ID not in g:
            print("::error::앱 고유 이름(applicationId)을 바꾸지 못했습니다")
            sys.exit(1)
        open(gp, "w", encoding="utf-8").write(g2)
# 직접 받는 설치 파일(APK)은 64비트 폰용만 — 네이버 지도 부품이 다른 종류(32비트·에뮬레이터용)까지 따라 들어와 96MB 되던 것
#   ONLY_ARM64=1 일 때만 (출시용 AAB 는 구글이 휴대폰마다 골라 주므로 그대로)
import glob as _glob
for g in _glob.glob("android/app/build.gradle*"):
    t = open(g, encoding="utf-8").read()
    if "ONLY_ARM64" in t:
        continue
    if g.endswith(".kts"):
        add = '        if (System.getenv("ONLY_ARM64") == "1") {\n            ndk { abiFilters.clear(); abiFilters.add("arm64-v8a") }\n        }\n'
    else:
        add = '        if (System.getenv("ONLY_ARM64") == "1") {\n            ndk { abiFilters "arm64-v8a" }\n        }\n'
    t2 = t.replace("    defaultConfig {\n", "    defaultConfig {\n" + add, 1)
    if t2 != t:
        open(g, "w", encoding="utf-8").write(t2)
        print("APK 64비트만:", g)
print("안드로이드 설정 완료")

# 후기 사진: 방향 바로잡기 · 1080px로 줄이기 · 작은 사진(320px) · 얼굴이 크게 나온 사진 찾기 (안드로이드 기본 얼굴 찾기 — 따로 받는 부품 없음)
import glob
MAIN_KT = '''package {pkg}

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.Intent
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.FaceDetector
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {{
    private val pool = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        // 길안내 고르는 창: 휴대폰에 깔린 카카오맵·네이버·티맵의 실제 아이콘 (없는 앱은 빠짐)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kokple/apps").setMethodCallHandler {{ call, result ->
            // 룰렛 결과 카톡으로 보내기: 카톡이 있으면 카톡으로 바로, 없으면 휴대폰 공유 창
            if (call.method == "shareKakao") {{
                val text = call.argument<String>("text") ?: ""
                val send = Intent(Intent.ACTION_SEND).apply {{
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }}
                try {{
                    startActivity(Intent(send).setPackage("com.kakao.talk"))
                    result.success("kakao")
                }} catch (e: Throwable) {{
                    try {{
                        startActivity(Intent.createChooser(send, "보내기"))
                        result.success("chooser")
                    }} catch (e2: Throwable) {{
                        result.success("none")
                    }}
                }}
                return@setMethodCallHandler
            }}
            if (call.method != "icons") {{
                result.notImplemented()
                return@setMethodCallHandler
            }}
            val pkgs = call.argument<List<String>>("pkgs") ?: emptyList()
            pool.execute {{
                val out = HashMap<String, ByteArray>()
                for (p in pkgs) {{
                    try {{
                        out[p] = iconPng(packageManager.getApplicationIcon(p), 120)
                    }} catch (e: Throwable) {{
                    }}
                }}
                Handler(Looper.getMainLooper()).post {{ result.success(out) }}
            }}
        }}
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kokple/photo").setMethodCallHandler {{ call, result ->
            if (call.method != "prep") {{
                result.notImplemented()
                return@setMethodCallHandler
            }}
            val path = call.argument<String>("path") ?: ""
            val full = call.argument<Int>("full") ?: 1080
            val thumb = call.argument<Int>("thumb") ?: 320
            pool.execute {{
                val out = try {{ prep(path, full, thumb) }} catch (e: Throwable) {{ null }}
                Handler(Looper.getMainLooper()).post {{
                    if (out == null) result.error("prep", "photo", null) else result.success(out)
                }}
            }}
        }}
    }}

    private fun iconPng(d: Drawable, size: Int): ByteArray {{
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(c)
        val o = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, o)
        return o.toByteArray()
    }}

    private fun prep(path: String, fullMax: Int, thumbMax: Int): Map<String, Any> {{
        val bounds = BitmapFactory.Options().apply {{ inJustDecodeBounds = true }}
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= fullMax && bounds.outHeight / (sample * 2) >= fullMax) sample *= 2
        val src = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {{ inSampleSize = sample }}) ?: throw IllegalStateException("decode")
        val ori = try {{
            ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }} catch (e: Exception) {{ ExifInterface.ORIENTATION_NORMAL }}
        val m = Matrix()
        when (ori) {{
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {{ m.postRotate(90f); m.postScale(-1f, 1f) }}
            ExifInterface.ORIENTATION_TRANSVERSE -> {{ m.postRotate(270f); m.postScale(-1f, 1f) }}
        }}
        val s = minOf(1f, fullMax.toFloat() / maxOf(src.width, src.height))
        m.postScale(s, s)
        val big = Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)

        // 얼굴 찾기: 작게 줄인 사진에서 (가로는 짝수여야 함)
        var fw = minOf(big.width, 640)
        fw -= fw % 2
        val fh = maxOf(2, (big.height.toFloat() * fw / big.width).toInt())
        val small = Bitmap.createScaledBitmap(big, fw, fh, true).copy(Bitmap.Config.RGB_565, false)
        val faces = arrayOfNulls<FaceDetector.Face>(5)
        val n = try {{ FaceDetector(fw, fh, 5).findFaces(small, faces) }} catch (e: Throwable) {{ 0 }}
        var eyes = 0f
        for (i in 0 until n) {{
            val f = faces[i] ?: continue
            if (f.confidence() >= 0.4f) eyes = maxOf(eyes, f.eyesDistance())
        }}
        // 얼굴 폭 ≈ 눈 사이 × 2.4 → 사진 짧은 변의 22%를 넘으면 「얼굴이 크게 나온 사진」
        val faceBig = eyes * 2.4f / minOf(fw, fh) >= 0.22f

        val fullOut = ByteArrayOutputStream()
        big.compress(Bitmap.CompressFormat.JPEG, 80, fullOut)
        val side = minOf(big.width, big.height)
        val sq = Bitmap.createBitmap(big, (big.width - side) / 2, (big.height - side) / 2, side, side)
        val th = Bitmap.createScaledBitmap(sq, thumbMax, thumbMax, true)
        val thumbOut = ByteArrayOutputStream()
        th.compress(Bitmap.CompressFormat.JPEG, 72, thumbOut)
        return mapOf("full" to fullOut.toByteArray(), "thumb" to thumbOut.toByteArray(), "faceBig" to faceBig, "faces" to n)
    }}
}}
'''
for kt in glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True):
    old = open(kt, encoding="utf-8").read()
    pkg = re.search(r"^package\s+([\w.]+)", old, re.M).group(1)
    open(kt, "w", encoding="utf-8").write(MAIN_KT.format(pkg=pkg))
