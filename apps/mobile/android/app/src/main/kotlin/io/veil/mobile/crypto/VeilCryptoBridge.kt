package io.veil.mobile.crypto

import android.content.Context
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.InvalidMessageException
import org.signal.libsignal.protocol.NoSessionException
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.UntrustedIdentityException
import org.signal.libsignal.protocol.ecc.Curve
import org.signal.libsignal.protocol.ecc.ECPublicKey
import org.signal.libsignal.protocol.kdf.HKDF
import org.signal.libsignal.protocol.kem.KEMKeyPair
import org.signal.libsignal.protocol.kem.KEMKeyType
import org.signal.libsignal.protocol.kem.KEMPublicKey
import org.signal.libsignal.protocol.message.CiphertextMessage
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.message.SignalMessage
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyBundle
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.util.KeyHelper
import org.signal.libsignal.protocol.util.Medium
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * `io.veil.crypto/bridge` handler. Implements the channel contract in
 * docs/crypto-mobile-bridge-design.md on top of libsignal-android.
 *
 * Rules (enforced by construction, not convention):
 *   - Private keys and session records never cross the channel. The only
 *     "private" value Dart receives is [IDENTITY_REF], an opaque constant.
 *   - Every failure is a `MethodChannel.Result.error` with a stable code.
 *     There is no plaintext fallback path and no inspection method.
 *   - Nothing is logged. Not inputs, not outputs, not error details beyond
 *     the exception class name.
 *
 * libsignal API usage targets libsignal-android 0.86.x; names marked
 * VERIFY must be checked against the pinned release before the first build.
 */
class VeilCryptoBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val store = SealedSignalProtocolStore(context)
    private val random = SecureRandom()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "generateDeviceIdentity" -> result.success(generateDeviceIdentity(call))
                "extractIdentityPublicKey" -> result.success(extractIdentityPublicKey(call))
                "bootstrapSession" -> result.success(bootstrapSession(call))
                "encryptMessage" -> result.success(encryptMessage(call))
                "decryptMessage" -> result.success(decryptMessage(call))
                "encryptAttachmentKey" -> result.success(encryptAttachmentKey(call))
                "decryptAttachmentKey" -> result.success(decryptAttachmentKey(call))
                "hasSession" -> result.success(mapOf("present" to hasSession(call)))
                "wipeCryptoState" -> result.success(mapOf("wiped" to wipe(call)))
                else -> result.notImplemented()
            }
        } catch (e: NoSessionException) {
            result.error("sessionNotFound", e.javaClass.simpleName, null)
        } catch (e: UntrustedIdentityException) {
            result.error("identityMismatch", e.javaClass.simpleName, null)
        } catch (e: BundleException) {
            result.error("bundleInvalid", e.message, null)
        } catch (e: ArgumentException) {
            result.error("invalidArgument", e.message, null)
        } catch (e: IllegalStateException) {
            // Store has no identity / corrupt record: the only recovery is a
            // local wipe + re-registration, matching VEIL's no-recovery model.
            result.error("keyWipeRequired", e.javaClass.simpleName, null)
        } catch (e: Exception) {
            result.error("decryptFailed", e.javaClass.simpleName, null)
        }
    }

    // ---- identity -------------------------------------------------------------

    /**
     * Generates: IdentityKeyPair, registrationId, one signed (EC) prekey, one
     * last-resort Kyber-1024 prekey, and one one-time EC prekey. Publishes
     * them as the VEIL `signedPrekeyBundle` (base64url JSON, v2 shape).
     *
     * Calling this again replaces the identity: libsignal sessions keyed to
     * the old identity become undecryptable, which is what device transfer /
     * re-registration expects.
     */
    private fun generateDeviceIdentity(call: MethodCall): Map<String, Any> {
        requireString(call, "deviceId")
        store.wipeAll()

        val identityPair = IdentityKeyPair.generate()
        val registrationId = KeyHelper.generateRegistrationId(false)
        store.installIdentity(identityPair, registrationId)

        val signedPreKeyId = random.nextInt(Medium.MAX_VALUE)
        val signedPair = Curve.generateKeyPair()
        val signedSig = Curve.calculateSignature(identityPair.privateKey, signedPair.publicKey.serialize())
        store.storeSignedPreKey(signedPreKeyId, SignedPreKeyRecord(signedPreKeyId, now(), signedPair, signedSig))

        val kyberPreKeyId = random.nextInt(Medium.MAX_VALUE)
        val kyberPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024)
        val kyberSig = Curve.calculateSignature(identityPair.privateKey, kyberPair.publicKey.serialize())
        store.storeKyberPreKey(kyberPreKeyId, KyberPreKeyRecord(kyberPreKeyId, now(), kyberPair, kyberSig))

        val preKeyId = random.nextInt(Medium.MAX_VALUE)
        val preKeyPair = Curve.generateKeyPair()
        store.storePreKey(preKeyId, PreKeyRecord(preKeyId, preKeyPair))

        val bundle = JSONObject()
            .put("v", 2)
            .put("registrationId", registrationId)
            .put("deviceId", LIBSIGNAL_DEVICE_ID)
            .put("signedPreKeyId", signedPreKeyId)
            .put("signedPreKey", b64(signedPair.publicKey.serialize()))
            .put("signedPreKeySignature", b64(signedSig))
            .put("kyberPreKeyId", kyberPreKeyId)
            .put("kyberPreKey", b64(kyberPair.publicKey.serialize()))
            .put("kyberPreKeySignature", b64(kyberSig))
            .put("preKeyId", preKeyId)
            .put("preKey", b64(preKeyPair.publicKey.serialize()))

        return mapOf(
            "identityPublicKey" to b64(identityPair.publicKey.serialize()),
            "identityPrivateKeyRef" to IDENTITY_REF,
            "signedPrekeyBundle" to b64(bundle.toString().toByteArray(Charsets.UTF_8)),
        )
    }

    private fun extractIdentityPublicKey(call: MethodCall): Map<String, Any> {
        requireIdentityRef(call)
        return mapOf("identityPublicKey" to b64(store.identityKeyPair.publicKey.serialize()))
    }

    // ---- sessions ---------------------------------------------------------------

    private fun bootstrapSession(call: MethodCall): Map<String, Any> {
        val remoteDeviceId = requireString(call, "remoteDeviceId")
        val remoteIdentity = parseIdentity(requireString(call, "remoteIdentityPublicKey"))
        val bundle = parseBundle(requireString(call, "remoteSignedPrekeyBundle"), remoteIdentity)
        val address = SignalProtocolAddress(remoteDeviceId, LIBSIGNAL_DEVICE_ID)

        // VERIFY(0.86.5): SessionBuilder(SignalProtocolStore, SignalProtocolAddress).process(PreKeyBundle)
        SessionBuilder(store, address).process(bundle)

        return mapOf("remoteIdentityFingerprint" to fingerprint(remoteIdentity.serialize()))
    }

    private fun hasSession(call: MethodCall): Boolean {
        val remoteDeviceId = call.argument<String>("remoteDeviceId") ?: return false
        return store.containsSession(SignalProtocolAddress(remoteDeviceId, LIBSIGNAL_DEVICE_ID))
    }

    // ---- messages -----------------------------------------------------------------

    private fun encryptMessage(call: MethodCall): Map<String, Any> {
        val remoteDeviceId = requireString(call, "remoteDeviceId")
        val plaintext = unb64(requireString(call, "plaintext"))
        val address = SignalProtocolAddress(remoteDeviceId, LIBSIGNAL_DEVICE_ID)
        val message: CiphertextMessage = SessionCipher(store, address).encrypt(plaintext)
        plaintext.fill(0)
        return mapOf(
            "ciphertext" to b64(message.serialize()),
            "messageType" to message.type,
        )
    }

    private fun decryptMessage(call: MethodCall): Map<String, Any> {
        val senderDeviceId = requireString(call, "senderDeviceId")
        val ciphertext = unb64(requireString(call, "ciphertext"))
        val messageType = call.argument<Int>("messageType") ?: throw ArgumentException("messageType")
        val address = SignalProtocolAddress(senderDeviceId, LIBSIGNAL_DEVICE_ID)
        val cipher = SessionCipher(store, address)
        val plaintext = when (messageType) {
            CiphertextMessage.PREKEY_TYPE -> cipher.decrypt(PreKeySignalMessage(ciphertext))
            CiphertextMessage.WHISPER_TYPE -> cipher.decrypt(SignalMessage(ciphertext))
            else -> throw InvalidMessageException("unknown message type")
        }
        val encoded = b64(plaintext)
        plaintext.fill(0)
        return mapOf("plaintext" to encoded)
    }

    // ---- attachment key wrap ----------------------------------------------------------
    //
    // ephemeral X25519 → HKDF-SHA256(salt = ephPub, info = "veil-attachment-wrap-v1")
    // → AES-256-GCM. Same wire shape as the lib adapter:
    //   wrappedKey = ephPub(33, libsignal-serialized) || ct || tag(16)
    // The recipient's X25519 is their *signed prekey*, verified against their
    // identity key before any agreement is computed.

    private fun encryptAttachmentKey(call: MethodCall): Map<String, Any> {
        val recipientIdentity = parseIdentity(requireString(call, "recipientIdentityPublicKey"))
        val bundleJson = parseBundleJson(requireString(call, "recipientSignedPrekeyBundle"))
        val signedPreKey = Curve.decodePoint(unb64(bundleJson.getString("signedPreKey")), 0)
        val signature = unb64(bundleJson.getString("signedPreKeySignature"))
        if (!recipientIdentity.publicKey.verifySignature(signedPreKey.serialize(), signature)) {
            throw BundleException("signed prekey signature invalid")
        }
        val attachmentKey = unb64(requireString(call, "attachmentKey"))
        if (attachmentKey.size != 32) throw ArgumentException("attachmentKey")

        val eph = Curve.generateKeyPair()
        val shared = Curve.calculateAgreement(signedPreKey, eph.privateKey)
        val wrapKey = HKDF.deriveSecrets(shared, eph.publicKey.serialize(), ATTACHMENT_WRAP_INFO, 32)
        shared.fill(0)
        val nonce = ByteArray(12).also(random::nextBytes)
        val sealed = aesGcm(Cipher.ENCRYPT_MODE, wrapKey, nonce, attachmentKey)
        wrapKey.fill(0)
        attachmentKey.fill(0)
        return mapOf(
            "wrappedKey" to b64(eph.publicKey.serialize() + sealed),
            "wrapNonce" to b64(nonce),
        )
    }

    private fun decryptAttachmentKey(call: MethodCall): Map<String, Any> {
        requireIdentityRef(call)
        val wrapped = unb64(requireString(call, "wrappedKey"))
        val nonce = unb64(requireString(call, "wrapNonce"))
        if (wrapped.size < EC_PUBLIC_LENGTH + 16 || nonce.size != 12) throw ArgumentException("wrappedKey")
        val ephPub: ECPublicKey = Curve.decodePoint(wrapped, 0)
        val body = wrapped.copyOfRange(EC_PUBLIC_LENGTH, wrapped.size)

        // Our side of the agreement is the *current signed prekey* (the key the
        // sender wrapped to). Try each stored signed prekey newest-first so a
        // rotation does not strand in-flight attachments.
        var lastError: Exception? = null
        for (record in store.loadSignedPreKeys().sortedByDescending { it.timestamp }) {
            try {
                val shared = Curve.calculateAgreement(ephPub, record.keyPair.privateKey)
                val wrapKey = HKDF.deriveSecrets(shared, ephPub.serialize(), ATTACHMENT_WRAP_INFO, 32)
                shared.fill(0)
                val key = aesGcm(Cipher.DECRYPT_MODE, wrapKey, nonce, body)
                wrapKey.fill(0)
                val encoded = b64(key)
                key.fill(0)
                return mapOf("attachmentKey" to encoded)
            } catch (e: Exception) {
                lastError = e
            }
        }
        throw lastError ?: InvalidMessageException("no signed prekey")
    }

    // ---- wipe ----------------------------------------------------------------------

    private fun wipe(call: MethodCall): Boolean {
        val scope = requireString(call, "scope")
        if (scope == "all") {
            store.wipeAll()
        } else {
            // Conversation scope: Dart passes the peer device id it bootstrapped with.
            store.wipeConversation(call.argument<String>("remoteDeviceId") ?: scope)
        }
        return true
    }

    // ---- bundle parsing ----------------------------------------------------------------

    private fun parseBundleJson(encoded: String): JSONObject = try {
        JSONObject(String(unb64(encoded), Charsets.UTF_8))
    } catch (e: Exception) {
        throw BundleException("malformed bundle")
    }

    private fun parseBundle(encoded: String, identity: IdentityKey): PreKeyBundle {
        val json = parseBundleJson(encoded)
        if (json.optInt("v", 0) != 2) throw BundleException("unsupported bundle version")
        try {
            val signedPreKey = Curve.decodePoint(unb64(json.getString("signedPreKey")), 0)
            val signedSig = unb64(json.getString("signedPreKeySignature"))
            val kyberPreKey = KEMPublicKey(unb64(json.getString("kyberPreKey")))
            val kyberSig = unb64(json.getString("kyberPreKeySignature"))
            val preKeyId = if (json.has("preKey")) json.getInt("preKeyId") else -1
            val preKey = if (json.has("preKey")) Curve.decodePoint(unb64(json.getString("preKey")), 0) else null
            // VERIFY(0.86.5): PreKeyBundle(registrationId, deviceId, preKeyId, preKey,
            //   signedPreKeyId, signedPreKey, signedPreKeySignature, identityKey,
            //   kyberPreKeyId, kyberPreKey, kyberPreKeySignature). libsignal itself
            //   re-verifies both signatures against `identity` inside process().
            return PreKeyBundle(
                json.getInt("registrationId"),
                json.optInt("deviceId", LIBSIGNAL_DEVICE_ID),
                preKeyId,
                preKey,
                json.getInt("signedPreKeyId"),
                signedPreKey,
                signedSig,
                identity,
                json.getInt("kyberPreKeyId"),
                kyberPreKey,
                kyberSig,
            )
        } catch (e: BundleException) {
            throw e
        } catch (e: Exception) {
            throw BundleException("bundle fields invalid")
        }
    }

    private fun parseIdentity(encoded: String): IdentityKey = try {
        IdentityKey(unb64(encoded))
    } catch (e: Exception) {
        throw BundleException("identity key invalid")
    }

    // ---- helpers -----------------------------------------------------------------------

    private fun aesGcm(mode: Int, key: ByteArray, nonce: ByteArray, input: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        return cipher.doFinal(input)
    }

    private fun fingerprint(identitySerialized: ByteArray): String =
        b64(MessageDigest.getInstance("SHA-256").digest(identitySerialized).copyOfRange(0, 16))

    private fun requireString(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf { it.isNotEmpty() } ?: throw ArgumentException(key)

    private fun requireIdentityRef(call: MethodCall) {
        if (requireString(call, "identityPrivateKeyRef") != IDENTITY_REF || !store.hasIdentity()) {
            throw IllegalStateException("identity ref")
        }
    }

    private fun now(): Long = System.currentTimeMillis()

    private fun b64(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

    private fun unb64(value: String): ByteArray = try {
        Base64.decode(value, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    } catch (e: IllegalArgumentException) {
        throw ArgumentException("base64")
    }

    private class ArgumentException(field: String) : RuntimeException("invalid or missing argument: $field")
    private class BundleException(message: String) : RuntimeException(message)

    companion object {
        const val CHANNEL_NAME = "io.veil.crypto/bridge"

        /** Opaque handle Dart stores as `identityPrivateKeyRef`. Carries no key material. */
        private const val IDENTITY_REF = "veil-libsignal-identity-v1"

        /** VEIL device ids are already per-device UUIDs, so every libsignal address uses sub-device 1. */
        private const val LIBSIGNAL_DEVICE_ID = 1

        /** libsignal-serialized EC public key length (type byte + 32). */
        private const val EC_PUBLIC_LENGTH = 33

        private val ATTACHMENT_WRAP_INFO = "veil-attachment-wrap-v1".toByteArray(Charsets.UTF_8)
    }
}
