# Flutter engine — keep entry points and JNI hooks. The Flutter Gradle plugin
# normally injects these, but the project pins isMinifyEnabled=true on
# release so we make the rules explicit.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keepattributes *Annotation*

# Plugins commonly used in this app — flutter_secure_storage, drift, etc.
# Keep their generated channels and cipher init paths so R8 doesn't strip
# native lookups.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }

# libsignal: the Rust core calls back into these classes by name over JNI.
-keep class org.signal.libsignal.** { *; }
-keepclassmembers class org.signal.libsignal.** { *; }
-keep class io.veil.mobile.crypto.** { *; }

# Kotlin coroutines — prevent obfuscation breaking lambda metadata.
-keepclassmembernames class kotlinx.** { volatile <fields>; }

# OkHttp/HTTP plugin reflection paths used by url_launcher / http.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Strip android.util.Log debug/verbose calls from release builds. Errors
# and warnings still flow through.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}

# Keep platform-channel method signatures used by AndroidManifest providers.
-keep class io.veil.mobile.** { *; }
