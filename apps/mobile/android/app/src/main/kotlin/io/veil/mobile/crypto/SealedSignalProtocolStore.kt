package io.veil.mobile.crypto

import android.content.Context
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.InvalidKeyIdException
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.groups.state.SenderKeyRecord
import org.signal.libsignal.protocol.state.IdentityKeyStore
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.SessionRecord
import org.signal.libsignal.protocol.state.SignalProtocolStore
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import java.util.UUID

/**
 * [SignalProtocolStore] backed by [KeystoreSealedStore]. Every record is
 * persisted on write (libsignal mutates sessions on each encrypt/decrypt) and
 * read back on demand; nothing is cached unsealed between calls.
 *
 * API names follow libsignal-android 0.86.x
 * (`org.signal.libsignal.protocol.state.*`). VERIFY against the pinned
 * version in android/app/build.gradle.kts when bumping.
 */
internal class SealedSignalProtocolStore(context: Context) : SignalProtocolStore {
    private val identity = KeystoreSealedStore(context, "identity")
    private val trusted = KeystoreSealedStore(context, "trusted-identities")
    private val sessions = KeystoreSealedStore(context, "sessions")
    private val preKeys = KeystoreSealedStore(context, "prekeys")
    private val signedPreKeys = KeystoreSealedStore(context, "signed-prekeys")
    private val kyberPreKeys = KeystoreSealedStore(context, "kyber-prekeys")
    private val senderKeys = KeystoreSealedStore(context, "sender-keys")

    // ---- identity -----------------------------------------------------------

    fun hasIdentity(): Boolean = identity.contains(KEY_IDENTITY_PAIR)

    fun installIdentity(pair: IdentityKeyPair, registrationId: Int) {
        identity.put(KEY_IDENTITY_PAIR, pair.serialize())
        identity.put(KEY_REGISTRATION_ID, registrationId.toString().toByteArray())
    }

    override fun getIdentityKeyPair(): IdentityKeyPair {
        val bytes = identity.get(KEY_IDENTITY_PAIR) ?: throw IllegalStateException("no identity")
        return IdentityKeyPair(bytes)
    }

    override fun getLocalRegistrationId(): Int {
        val bytes = identity.get(KEY_REGISTRATION_ID) ?: throw IllegalStateException("no identity")
        return String(bytes).toInt()
    }

    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): IdentityKeyStore.IdentityChange {
        val key = addressKey(address)
        val existing = trusted.get(key)
        trusted.put(key, identityKey.serialize())
        return if (existing == null || existing.contentEquals(identityKey.serialize())) {
            IdentityKeyStore.IdentityChange.NEW_OR_UNCHANGED
        } else {
            IdentityKeyStore.IdentityChange.REPLACED_EXISTING
        }
    }

    /**
     * Trust-on-first-use, then pin. A changed key is *not* trusted here: the
     * decrypt/encrypt call throws UntrustedIdentityException, the bridge maps
     * it to `identityMismatch`, and the Dart layer forces a re-bootstrap plus
     * the Safety-Number-changed prompt. Never auto-accept a rotated key.
     */
    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction,
    ): Boolean {
        val existing = trusted.get(addressKey(address)) ?: return true
        return existing.contentEquals(identityKey.serialize())
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? =
        trusted.get(addressKey(address))?.let { IdentityKey(it) }

    fun forgetIdentity(address: SignalProtocolAddress) = trusted.remove(addressKey(address))

    // ---- one-time prekeys -----------------------------------------------------

    override fun loadPreKey(preKeyId: Int): PreKeyRecord =
        preKeys.get(preKeyId.toString())?.let { PreKeyRecord(it) }
            ?: throw InvalidKeyIdException("no prekey $preKeyId")

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) = preKeys.put(preKeyId.toString(), record.serialize())

    override fun containsPreKey(preKeyId: Int): Boolean = preKeys.contains(preKeyId.toString())

    override fun removePreKey(preKeyId: Int) = preKeys.remove(preKeyId.toString())

    // ---- signed prekeys -------------------------------------------------------

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord =
        signedPreKeys.get(signedPreKeyId.toString())?.let { SignedPreKeyRecord(it) }
            ?: throw InvalidKeyIdException("no signed prekey $signedPreKeyId")

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> =
        signedPreKeys.keys("").mapNotNull { k -> signedPreKeys.get(k)?.let { SignedPreKeyRecord(it) } }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) =
        signedPreKeys.put(signedPreKeyId.toString(), record.serialize())

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean = signedPreKeys.contains(signedPreKeyId.toString())

    override fun removeSignedPreKey(signedPreKeyId: Int) = signedPreKeys.remove(signedPreKeyId.toString())

    // ---- kyber prekeys (PQXDH) ---------------------------------------------------

    override fun loadKyberPreKey(kyberPreKeyId: Int): KyberPreKeyRecord =
        kyberPreKeys.get(kyberPreKeyId.toString())?.let { KyberPreKeyRecord(it) }
            ?: throw InvalidKeyIdException("no kyber prekey $kyberPreKeyId")

    override fun loadKyberPreKeys(): List<KyberPreKeyRecord> =
        kyberPreKeys.keys("").filterNot { it.startsWith(USED_PREFIX) }
            .mapNotNull { k -> kyberPreKeys.get(k)?.let { KyberPreKeyRecord(it) } }

    override fun storeKyberPreKey(kyberPreKeyId: Int, record: KyberPreKeyRecord) =
        kyberPreKeys.put(kyberPreKeyId.toString(), record.serialize())

    override fun containsKyberPreKey(kyberPreKeyId: Int): Boolean = kyberPreKeys.contains(kyberPreKeyId.toString())

    /**
     * The long-lived ("last resort") Kyber prekey published in the bundle must
     * survive being used, so we only record the use; one-time Kyber prekeys
     * are not published by this bridge yet.
     */
    override fun markKyberPreKeyUsed(kyberPreKeyId: Int) {
        kyberPreKeys.put("$USED_PREFIX$kyberPreKeyId", byteArrayOf(1))
    }

    // ---- sessions ---------------------------------------------------------------

    override fun loadSession(address: SignalProtocolAddress): SessionRecord? =
        sessions.get(addressKey(address))?.let { SessionRecord(it) }

    override fun loadExistingSessions(addresses: List<SignalProtocolAddress>): List<SessionRecord> =
        addresses.map { loadSession(it) ?: throw org.signal.libsignal.protocol.NoSessionException(it, "no session") }

    override fun getSubDeviceSessions(name: String): List<Int> =
        sessions.keys("$name/").mapNotNull { it.substringAfterLast('/').toIntOrNull() }.filter { it != 1 }

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) =
        sessions.put(addressKey(address), record.serialize())

    override fun containsSession(address: SignalProtocolAddress): Boolean = sessions.contains(addressKey(address))

    override fun deleteSession(address: SignalProtocolAddress) = sessions.remove(addressKey(address))

    override fun deleteAllSessions(name: String) {
        sessions.keys("$name/").forEach(sessions::remove)
    }

    // ---- sender keys (unused: VEIL groups use their own Sender Keys engine) -------

    override fun storeSenderKey(sender: SignalProtocolAddress, distributionId: UUID, record: SenderKeyRecord) =
        senderKeys.put("${addressKey(sender)}/$distributionId", record.serialize())

    override fun loadSenderKey(sender: SignalProtocolAddress, distributionId: UUID): SenderKeyRecord? =
        senderKeys.get("${addressKey(sender)}/$distributionId")?.let { SenderKeyRecord(it) }

    // ---- wipe ---------------------------------------------------------------------

    fun wipeConversation(peerDeviceId: String) {
        deleteAllSessions(peerDeviceId)
        sessions.remove(addressKey(SignalProtocolAddress(peerDeviceId, 1)))
        forgetIdentity(SignalProtocolAddress(peerDeviceId, 1))
    }

    fun wipeAll() {
        listOf(identity, trusted, sessions, preKeys, signedPreKeys, kyberPreKeys, senderKeys).forEach { it.destroy() }
    }

    private fun addressKey(address: SignalProtocolAddress) = "${address.name}/${address.deviceId}"

    private companion object {
        const val KEY_IDENTITY_PAIR = "identity-key-pair"
        const val KEY_REGISTRATION_ID = "registration-id"
        const val USED_PREFIX = "used:"
    }
}
