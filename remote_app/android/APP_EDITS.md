# Android edits — exactly four, and why

Your repo's `android/` folder comes from **your** `flutter create`, so it already
matches your Flutter/Gradle/Kotlin versions. Do not copy an `android/` folder from
anywhere. These four edits are all that my code needs from the platform.

Everything below is Windows/PowerShell-friendly; any shell works.

---

## 1 · `android/app/src/main/AndroidManifest.xml`

Add the three permissions, the camera feature, `usesCleartextTraffic`, a nicer label,
and the `salu://` deep link. The whole file, ready to paste over the generated one —
**if your generated manifest has attributes mine does not (a newer Flutter may add
one), keep them.**

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- The PC is reached over the LAN, in cleartext ws:// — by design.
         remote.md §4: no TLS in v1 (a self-signed cert on an IP breaks more
         phones than it protects). -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- QR pairing (D2). The app never takes a photo; the camera is only ever
         pointed at SALU's own panel. -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <!-- "Camera optional" so the app still installs on a device without one:
         manual entry has to keep working. -->
    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <application
        android:label="SALU Remote"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <!-- salu://pair?v=1&n=…&h=…&p=…&c=…  (remote.md §10.2)
                 Not used by the app to pair directly — the QR scanner reads the
                 same URI. It exists so any camera app's "open with" can bring
                 SALU Remote to the front instead of a browser. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="salu" android:host="pair" />
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

**Why `usesCleartextTraffic` even though `dart:io` sockets usually ignore it:**
Flutter's WebSocket does its own socket work and is not policed by this flag, but
anything else that ever fetches over http (a WebView, an image loader, a future
plugin) is. Leaving it on costs nothing here and removes a class of "works on my
phone, not on yours" reports.

---

## 2 · `android/app/build.gradle.kts` (or `build.gradle` — older Flutter)

Two changes inside the `android { }` block: **minSdk 24**, and nothing else.

Kotlin DSL (Flutter 3.29+ generates this file name):

```kotlin
android {
    namespace = "app.salu.salu_remote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "app.salu.salu_remote"
        minSdk = 24                 // ← was flutter.minSdkVersion (21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

Groovy (`build.gradle`):

```groovy
defaultConfig {
    applicationId "app.salu.salu_remote"
    minSdkVersion 24                // ← was flutter.minSdkVersion (21)
    targetSdkVersion flutter.targetSdkVersion
}
```

`minSdk 24` (Android 7.0) is what `mobile_scanner` is happiest with and it covers every
phone in use. If your `flutter create` used a different `--org`/project name, keep
*your* `applicationId` — it only has to match the `package` line in `MainActivity.kt`.

---

## 3 · `android/app/src/main/kotlin/<your/package>/MainActivity.kt`

One method channel, so the app can hold the screen awake while it is on screen (D6)
**without a third plugin**. Replace the file with this, keeping **your** `package` line:

```kotlin
package app.salu.salu_remote

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val screenChannel = "app.salu.remote/screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

If you skip this, nothing breaks: `lib/core/screen.dart` swallows the missing channel and
the phone just dims on its own schedule.

---

## 4 · `android/gradle.properties` — only if the build is slow or OOMs

Not required, but on a 8 GB Windows machine the first build sometimes dies with
`Java heap space`. Then:

```properties
org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G
android.useAndroidX=true
android.enableJetifier=false
```

---

## Nice-to-have, later: the app icon

Flutter ships the blue Flutter logo. SALU's own mark is `salu_app_icon.png` in the PC
repo and a set of rendered concepts under `design/icons-preview/`. Dropping a proper
launcher icon is a five-minute job with `flutter_launcher_icons` — **not** part of the
first working build. Ask me when the app runs; it is polish, not plumbing.
