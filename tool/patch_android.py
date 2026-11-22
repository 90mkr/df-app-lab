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
print("안드로이드 설정 완료")

# 후기 사진: 방향 바로잡기 · 1080px로 줄이기 · 작은 사진(320px) · 얼굴이 크게 나온 사진 찾기 (안드로이드 기본 얼굴 찾기 — 따로 받는 부품 없음)
import glob
MAIN_KT = '''package {pkg}

import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
