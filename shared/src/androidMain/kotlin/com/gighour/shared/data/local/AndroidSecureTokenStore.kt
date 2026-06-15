package com.gighour.shared.data.local

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.concurrent.atomic.AtomicReference

/**
 * Android [SecureTokenStore] backed by EncryptedSharedPreferences (Android
 * Keystore master key) — the same mechanism Gigand's AuthPreferences uses, so
 * tokens at rest survive only on this device and can't be read off a rooted
 * device. An in-memory [AtomicReference] mirrors the token so
 * [hasCachedSupabaseToken] is cheap and the per-request Supabase callback never
 * blocks on disk.
 *
 * NOTE for later :app migration — Gigand's AuthPreferences already owns this
 * file; when wiring :app to :shared, either delegate to the existing
 * AuthPreferences or migrate its keys here. Don't double-own the same prefs file.
 */
class AndroidSecureTokenStore(
    context: Context,
    private val prefsFileName: String = "gighour_secure_tokens",
) : SecureTokenStore {

    private val securePrefs: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            prefsFileName,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    private val cachedToken = AtomicReference<String?>(securePrefs.getString(KEY_TOKEN, null))

    override suspend fun getSupabaseToken(): String? =
        cachedToken.get() ?: securePrefs.getString(KEY_TOKEN, null)

    override suspend fun setSupabaseToken(token: String?) {
        cachedToken.set(token)
        securePrefs.edit().apply {
            if (token == null) remove(KEY_TOKEN) else putString(KEY_TOKEN, token)
        }.apply()
    }

    override suspend fun getAuthToken(): String? = securePrefs.getString(KEY_AUTH_TOKEN, null)

    override suspend fun setAuthToken(token: String?) {
        securePrefs.edit().apply {
            if (token == null) remove(KEY_AUTH_TOKEN) else putString(KEY_AUTH_TOKEN, token)
        }.apply()
    }

    override suspend fun getUserId(): String? = securePrefs.getString(KEY_USER_ID, null)

    override suspend fun setUserId(userId: String?) {
        securePrefs.edit().apply {
            if (userId == null) remove(KEY_USER_ID) else putString(KEY_USER_ID, userId)
        }.apply()
    }

    override suspend fun hasCachedSupabaseToken(): Boolean = cachedToken.get() != null

    override suspend fun clear() {
        cachedToken.set(null)
        securePrefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_TOKEN = "supabase_token"
        private const val KEY_AUTH_TOKEN = "auth_token"
        private const val KEY_USER_ID = "user_id"
    }
}
