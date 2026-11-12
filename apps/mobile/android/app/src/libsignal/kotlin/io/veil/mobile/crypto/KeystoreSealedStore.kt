package io.veil.mobile.crypto

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small key/value store whose values are sealed with an AES-256-GCM key that
 * lives in the Android Keystore (hardware-backed where the device supports
 * it, never exportable). Backs every libsignal store so identity, prekey and
 * session bytes are never written to disk in the clear.
 *
 * Layout per value: base64( iv(12) || ciphertext || tag(16) ). Keys (the
 * SharedPreferences names) are not secret but carry no plaintext either —
 * they are opaque record ids / peer device ids.
 *
 * Deliberately dependency-free (no androidx.security) so the audited surface
 * is AndroidKeyStore + javax.crypto only.
 */
internal class KeystoreSealedStore(context: Context, namespace: String) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("veil.libsignal.$namespace", Context.MODE_PRIVATE)
    private val alias = "veil.libsignal.sealing.$namespace"
    private val random = SecureRandom()

    fun get(key: String): ByteArray? {
        val encoded = prefs.getString(key, null) ?: return null
        val blob = Base64.decode(encoded, Base64.NO_WRAP)
        if (blob.size < IV_LENGTH + TAG_LENGTH_BYTES) return null
        val iv = blob.copyOfRange(0, IV_LENGTH)
        val body = blob.copyOfRange(IV_LENGTH, blob.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, sealingKey(), GCMParameterSpec(TAG_LENGTH_BITS, iv))
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(body)
    }

    fun put(key: String, value: ByteArray) {
        val iv = ByteArray(IV_LENGTH).also(random::nextBytes)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, sealingKey(), GCMParameterSpec(TAG_LENGTH_BITS, iv))
        // Bind the record id so a sealed value cannot be moved under another key.
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val body = cipher.doFinal(value)
        prefs.edit().putString(key, Base64.encodeToString(iv + body, Base64.NO_WRAP)).apply()
    }

    fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }

    fun contains(key: String): Boolean = prefs.contains(key)

    fun keys(prefix: String): List<String> = prefs.all.keys.filter { it.startsWith(prefix) }

    fun clear() {
        prefs.edit().clear().apply()
    }

    /** Destroys the sealing key too — everything previously stored is unrecoverable. */
    fun destroy() {
        clear()
        try {
            val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            ks.deleteEntry(alias)
        } catch (_: Exception) {
            // Best effort; the prefs are already gone.
        }
    }

    private fun sealingKey(): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                // Randomized IVs are supplied by us (fresh per write), so we
                // must opt out of the Keystore-managed IV.
                .setRandomizedEncryptionRequired(false)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_LENGTH_BITS = 128
        const val TAG_LENGTH_BYTES = 16
    }
}
