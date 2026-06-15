package com.gighour.shared.data.local

import kotlin.concurrent.AtomicReference

/**
 * iOS [SecureTokenStore] backed by the Keychain (via [IosKeychain]). The
 * Keychain is the iOS equivalent of Android's EncryptedSharedPreferences:
 * OS-protected, not extractable off-device. An in-memory mirror keeps
 * [hasCachedSupabaseToken] cheap and the per-request Supabase callback off the
 * Keychain hot path.
 *
 * NOTE: Keychain cinterop NOT compiled against the Apple toolchain here — needs
 * an on-device / linkDebugFramework pass before ship.
 */
class IosSecureTokenStore(
    service: String = "com.gighour.shared.tokens",
) : SecureTokenStore {

    private val keychain = IosKeychain(service)
    private val cachedToken = AtomicReference<String?>(keychain.read(KEY_TOKEN))

    override suspend fun getSupabaseToken(): String? =
        cachedToken.value ?: keychain.read(KEY_TOKEN)

    override suspend fun setSupabaseToken(token: String?) {
        cachedToken.value = token
        if (token == null) keychain.delete(KEY_TOKEN) else keychain.write(KEY_TOKEN, token)
    }

    override suspend fun getAuthToken(): String? = keychain.read(KEY_AUTH_TOKEN)

    override suspend fun setAuthToken(token: String?) {
        if (token == null) keychain.delete(KEY_AUTH_TOKEN) else keychain.write(KEY_AUTH_TOKEN, token)
    }

    override suspend fun getUserId(): String? = keychain.read(KEY_USER_ID)

    override suspend fun setUserId(userId: String?) {
        if (userId == null) keychain.delete(KEY_USER_ID) else keychain.write(KEY_USER_ID, userId)
    }

    override suspend fun hasCachedSupabaseToken(): Boolean = cachedToken.value != null

    override suspend fun clear() {
        cachedToken.value = null
        keychain.delete(KEY_TOKEN)
        keychain.delete(KEY_AUTH_TOKEN)
        keychain.delete(KEY_USER_ID)
    }

    companion object {
        private const val KEY_TOKEN = "supabase_token"
        private const val KEY_AUTH_TOKEN = "auth_token"
        private const val KEY_USER_ID = "user_id"
    }
}
