package com.gighour.shared.data.local

import com.gighour.shared.domain.model.AuthData
import kotlinx.coroutines.flow.Flow

/**
 * Full auth-session store — the KMP abstraction over Gigand's AuthPreferences.
 * Where [SecureTokenStore] is the narrow token slice the HTTP/Supabase layer
 * reads, [SessionStore] is the richer session the auth flow owns: the whole
 * [AuthData] (userId/phone/userType/token/profileComplete), a reactive
 * [authDataFlow] the app observes for login state, and the Supabase token.
 *
 * Implementations back this with the OS secure store (EncryptedSharedPreferences
 * on Android, Keychain on iOS). Carry over AuthPreferences' guarantees:
 *  - tokens at rest only (never plain prefs);
 *  - [authDataFlow] must not emit a transient logged-out value before the store
 *    has finished its initial load (Gigand gates this on an `initialized`
 *    deferred — replicate so collectors don't flicker to "logged out" on start);
 *  - in-memory mirror so the synchronous token reads don't hit disk.
 *
 * The NonCancellable session-save (so a torn-down viewModelScope can't abort the
 * write mid-commit) lives in the REPOSITORY, not here — see
 * AuthRepositoryImpl.verifyOtp and project_employer_login_5554.
 */
interface SessionStore {
    /** Login state, gated on initial load; never a premature logged-out emit. */
    val authDataFlow: Flow<AuthData?>

    /** Persist the full session after a successful OTP verify. */
    suspend fun saveAuthData(authData: AuthData)

    suspend fun updateUserType(userType: String)
    suspend fun setProfileComplete(isComplete: Boolean)

    suspend fun getToken(): String?
    suspend fun getUserId(): String?
    suspend fun getUserType(): String?

    suspend fun getSupabaseToken(): String?
    suspend fun setSupabaseToken(token: String?)
    /** Synchronous in-memory read; null/blank when no cached Supabase token. */
    fun getCachedSupabaseToken(): String?

    /** Wipe the session (logout). */
    suspend fun clearAuthData()
}
