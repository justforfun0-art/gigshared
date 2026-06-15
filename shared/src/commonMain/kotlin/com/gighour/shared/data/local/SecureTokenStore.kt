package com.gighour.shared.data.local

/**
 * Secure, at-rest storage for the auth token + session identity.
 *
 * Mirrors the slice of Gigand's AuthPreferences that shared code needs: the
 * per-request Supabase JWT (minted by the backend's /api/auth/sb-token) and the
 * authenticated user id. Backed per-platform by the OS secure store —
 * EncryptedSharedPreferences (Android Keystore) / Keychain (iOS) — so tokens
 * can't be read off a rooted/jailbroken device. NEVER persist these in plain
 * preferences.
 *
 * Honour the existing anti-tamper rule: callers must not invent a token or fall
 * back to device-derived values; a null token means "not authenticated yet".
 */
interface SecureTokenStore {
    /** The cached Supabase access token, or null if none is stored. */
    suspend fun getSupabaseToken(): String?

    /** Persist (or clear, when null) the Supabase access token. */
    suspend fun setSupabaseToken(token: String?)

    /**
     * The app auth token (Gigand's AuthPreferences "auth_token") used for the
     * Next.js secure API routes — sent as both `Authorization: Bearer` and
     * the `auth_token` cookie. Distinct from the Supabase JWT above. Null when
     * not logged in.
     */
    suspend fun getAuthToken(): String?

    /** Persist (or clear, when null) the app auth token. */
    suspend fun setAuthToken(token: String?)

    /** The authenticated user's id, or null if not logged in. */
    suspend fun getUserId(): String?

    /** Persist (or clear, when null) the authenticated user's id. */
    suspend fun setUserId(userId: String?)

    /** True when a token is already cached in memory/at-rest (skip re-mint). */
    suspend fun hasCachedSupabaseToken(): Boolean

    /** Wipe all stored auth material (logout). */
    suspend fun clear()
}
