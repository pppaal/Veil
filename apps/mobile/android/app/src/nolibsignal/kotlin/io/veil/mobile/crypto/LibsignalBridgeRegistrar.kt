package io.veil.mobile.crypto

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger

/**
 * Default build: the libsignal bridge and its native libraries are left out,
 * and nothing answers its channel. A Dart build that selects the libsignal
 * adapter then reports the bridge as unavailable (MissingPluginException,
 * see libsignal_bridge_adapter.dart) and decrypts nothing.
 */
object LibsignalBridgeRegistrar {
    @Suppress("UNUSED_PARAMETER")
    fun register(messenger: BinaryMessenger, context: Context) = Unit
}
