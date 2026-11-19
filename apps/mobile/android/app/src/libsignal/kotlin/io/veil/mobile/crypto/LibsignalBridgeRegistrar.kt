package io.veil.mobile.crypto

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Opt-in build (`-Pveil.libsignal=true`): registers the libsignal bridge the
 * Dart side reaches when it is built with
 * `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal`.
 */
object LibsignalBridgeRegistrar {
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, VeilCryptoBridge.CHANNEL_NAME)
            .setMethodCallHandler(VeilCryptoBridge(context))
    }
}
