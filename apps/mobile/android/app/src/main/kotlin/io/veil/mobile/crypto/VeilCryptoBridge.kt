package io.veil.mobile.crypto

import android.content.Context
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.UntrustedIdentityException
import org.signal.libsignal.protocol.ecc.Curve
import org.signal.libsignal.protocol.message.CiphertextMessage
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.message.SignalMessage
import org.signal.libsignal.protocol.state.PreKeyBundle
import org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore
import org.signal.libsignal.protocol.util.KeyHelper

/**
 * Native crypto bridge backing the Dart [LibsignalBridgeAdapter] with Signal's
 * audited libsignal (org.signal:libsignal-android). First-cut, Android-only.
 *
 * The core message path (identity generation, session bootstrap, encrypt,
 * decrypt) uses real libsignal calls. It is NOT production-ready yet — see the
 * TODOs — and must be verified on real devices before it is trusted:
 *
 *  - PERSISTENCE: uses InMemorySignalProtocolStore, so identity + sessions are
 *    lost on process restart. Must be replaced with a persistent store backed
 *    by a hardware keystore (EncryptedSharedPreferences / SQLCipher) that
 *    implements IdentityKeyStore/PreKeyStore/SignedPreKeyStore/SessionStore.
 *  - PQXDH: libsignal 0.86.x may require Kyber prekey params on PreKeyBundle /
 *    the bundle generation. If the classic constructor is rejected, switch to
 *    the Kyber-aware overload and advertise a Kyber prekey.
 *  - ADDRESS MAPPING: uses the peer deviceId as the SignalProtocolAddress name
 *    with device 1. Confirm against VEIL's multi-device routing.
 *  - device-auth (Ed25519 challenge) and attachment key wrap are left to VEIL's
 *    existing paths for now (notYet).
 *
 * Exact symbol names/signatures are for libsignal-android 0.86.5; verify when
 * pinning. No operation ever falls back to plaintext.
 */
class VeilCryptoBridge(
    @Suppress("unused") private val context: Context,
) : MethodChannel.MethodCallHandler {

    private var store: InMemorySignalProtocolStore? = null
    private var identityKeyPair: IdentityKeyPair? = null

    private fun b64e(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun b64d(value: String): ByteArray = Base64.decode(value, Base64.NO_WRAP)

    private fun requireStore(): InMemorySignalProtocolStore =
        store ?: throw IllegalStateException(
            "identity not initialized in this process (persistent store is a TODO)",
        )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "generateDeviceIdentity" -> generateDeviceIdentity(call, result)
                "extractIdentityPublicKey" -> extractIdentityPublicKey(result)
                "bootstrapSession" -> bootstrapSession(call, result)
                "bootstrapSessionFromInbound" -> bootstrapSessionFromInbound(call, result)
                "encryptMessage" -> encryptMessage(call, result)
                "decryptMessage" -> decryptMessage(call, result)
                "forceRekey" -> result.success(mapOf("armed" to false))
                // Kept on VEIL's existing paths for the first cut:
                "generateAuthKeyMaterial" ->
                    notYet(result, "generateAuthKeyMaterial: Ed25519 device-auth keypair")
                "signChallenge" ->
                    notYet(result, "signChallenge: Ed25519 sign with device-auth key")
                "encryptAttachmentKey" ->
                    notYet(result, "encryptAttachmentKey: wrap one-shot content key")
                "decryptAttachmentKey" ->
                    notYet(result, "decryptAttachmentKey: unwrap content key")
                else -> result.notImplemented()
            }
        } catch (e: UntrustedIdentityException) {
            result.error("identityMismatch", e.message, null)
        } catch (e: Exception) {
            // Never leak internals or fall through to plaintext.
            result.error("decryptFailed", e.message, null)
        }
    }

    private fun generateDeviceIdentity(call: MethodCall, result: MethodChannel.Result) {
        val ikp = IdentityKeyPair.generate()
        val registrationId = KeyHelper.generateRegistrationId(false)
        val protocolStore = InMemorySignalProtocolStore(ikp, registrationId)

        val signedPreKeyId = 1
        val signedPreKey = KeyHelper.generateSignedPreKey(ikp, signedPreKeyId)
        protocolStore.storeSignedPreKey(signedPreKey.id, signedPreKey)

        val preKeys = KeyHelper.generatePreKeys(1, 100)
        preKeys.forEach { protocolStore.storePreKey(it.id, it) }

        store = protocolStore
        identityKeyPair = ikp

        // Advertise one one-time prekey + the signed prekey. The server key
        // bundle format must carry exactly these fields for the peer to build a
        // PreKeyBundle (see bootstrapSession).
        val oneTime = preKeys.first()
        val bundle = JSONObject().apply {
            put("registrationId", registrationId)
            put("deviceId", 1) // TODO: map to VEIL deviceId
            put("preKeyId", oneTime.id)
            put("preKeyPublic", b64e(oneTime.keyPair.publicKey.serialize()))
            put("signedPreKeyId", signedPreKey.id)
            put("signedPreKeyPublic", b64e(signedPreKey.keyPair.publicKey.serialize()))
            put("signedPreKeySignature", b64e(signedPreKey.signature))
        }

        result.success(
            mapOf(
                "identityPublicKey" to b64e(ikp.publicKey.serialize()),
                // Opaque handle; the private key never leaves native. TODO: with
                // a persistent store this becomes a stable key id, not the raw
                // device id.
                "identityPrivateKeyRef" to (call.argument<String>("deviceId") ?: "local"),
                "signedPrekeyBundle" to bundle.toString(),
            ),
        )
    }

    private fun extractIdentityPublicKey(result: MethodChannel.Result) {
        val ikp = identityKeyPair
            ?: throw IllegalStateException("no identity (persistent store is a TODO)")
        result.success(mapOf("identityPublicKey" to b64e(ikp.publicKey.serialize())))
    }

    private fun bootstrapSession(call: MethodCall, result: MethodChannel.Result) {
        val protocolStore = requireStore()
        val remoteDeviceId = call.argument<String>("remoteDeviceId")!!
        val identityB64 = call.argument<String>("remoteIdentityPublicKey")!!
        val bundleJson = JSONObject(call.argument<String>("remoteSignedPrekeyBundle")!!)

        val identityKey = IdentityKey(b64d(identityB64), 0)
        val preKeyPublic = Curve.decodePoint(b64d(bundleJson.getString("preKeyPublic")), 0)
        val signedPreKeyPublic =
            Curve.decodePoint(b64d(bundleJson.getString("signedPreKeyPublic")), 0)

        // TODO(pqxdh): 0.86.x may require the Kyber-aware PreKeyBundle overload.
        val preKeyBundle = PreKeyBundle(
            bundleJson.getInt("registrationId"),
            bundleJson.getInt("deviceId"),
            bundleJson.getInt("preKeyId"),
            preKeyPublic,
            bundleJson.getInt("signedPreKeyId"),
            signedPreKeyPublic,
            b64d(bundleJson.getString("signedPreKeySignature")),
            identityKey,
        )

        val address = SignalProtocolAddress(remoteDeviceId, 1)
        SessionBuilder(protocolStore, address).process(preKeyBundle)

        result.success(bootstrapMaterial(call, identityKey))
    }

    private fun bootstrapSessionFromInbound(call: MethodCall, result: MethodChannel.Result) {
        // With libsignal, an inbound PreKeySignalMessage bootstraps the session
        // during decrypt (see decryptMessage), so no explicit build is needed.
        // Report success so the Dart layer records the session; the real
        // session is established on first decrypt.
        result.success(bootstrapMaterial(call, null))
    }

    private fun bootstrapMaterial(call: MethodCall, identityKey: IdentityKey?): Map<String, Any> {
        val fingerprint = identityKey?.let { b64e(it.serialize()) } ?: ""
        return mapOf(
            "sessionLocator" to (call.argument<String>("conversationId") ?: ""),
            "sessionEnvelopeVersion" to "libsignal-v1",
            "requiresLocalPersistence" to true,
            "sessionSchemaVersion" to 1,
            "localDeviceId" to (call.argument<String>("localDeviceId") ?: ""),
            "remoteDeviceId" to (call.argument<String>("remoteDeviceId") ?: ""),
            "remoteIdentityFingerprint" to fingerprint,
        )
    }

    private fun encryptMessage(call: MethodCall, result: MethodChannel.Result) {
        val protocolStore = requireStore()
        val recipientBundle = call.argument<Map<String, Any>>("recipientBundle")!!
        val recipientDeviceId = recipientBundle["deviceId"] as String
        val plaintext = b64d(call.argument<String>("plaintext")!!)

        val address = SignalProtocolAddress(recipientDeviceId, 1)
        val ciphertext: CiphertextMessage = SessionCipher(protocolStore, address).encrypt(plaintext)
        val type = if (ciphertext.type == CiphertextMessage.PREKEY_TYPE) "prekey" else "whisper"

        result.success(
            mapOf(
                "version" to "libsignal-v1",
                "ciphertext" to b64e(ciphertext.serialize()),
                // libsignal has no separate nonce; carry the message type here so
                // the receiver picks PreKeySignalMessage vs SignalMessage.
                "nonce" to type,
            ),
        )
    }

    private fun decryptMessage(call: MethodCall, result: MethodChannel.Result) {
        val protocolStore = requireStore()
        val senderDeviceId = call.argument<String>("senderDeviceId")!!
        val type = call.argument<String>("nonce") ?: "whisper"
        val bytes = b64d(call.argument<String>("ciphertext")!!)

        val address = SignalProtocolAddress(senderDeviceId, 1)
        val cipher = SessionCipher(protocolStore, address)
        val plaintext: ByteArray = if (type == "prekey") {
            cipher.decrypt(PreKeySignalMessage(bytes))
        } else {
            cipher.decrypt(SignalMessage(bytes))
        }

        result.success(
            mapOf(
                "plaintext" to b64e(plaintext),
                "messageKind" to (call.argument<String>("messageKind") ?: "text"),
            ),
        )
    }

    private fun notYet(result: MethodChannel.Result, what: String) {
        result.error("bridgeUnavailable", "libsignal bridge not implemented yet: $what", null)
    }
}
