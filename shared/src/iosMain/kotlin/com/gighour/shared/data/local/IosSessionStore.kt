package com.gighour.shared.data.local

import com.gighour.shared.domain.model.AuthData
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * iOS [SessionStore] backed by the Keychain (via [IosKeychain]) — the
 * counterpart of AndroidSessionStore. Keychain reads are synchronous, so unlike
 * the Android impl there's no async-init flicker to guard against; the
 * [authDataFlow] is seeded from the Keychain at construction and updated on
 * every write, so collectors never see a transient logged-out value.
 *
 * NOTE: Keychain cinterop NOT compiled against the Apple toolchain here — needs
 * an on-device / linkDebugFramework pass before ship.
 */
class IosSessionStore(
    service: String = "com.gighour.shared.session",
) : SessionStore {

    private val keychain = IosKeychain(service)
    private val state = MutableStateFlow(readAuthData())

    override val authDataFlow: Flow<AuthData?> = state.asStateFlow()

    override suspend fun saveAuthData(authData: AuthData) {
        keychain.write(KEY_USER_ID, authData.userId)
        keychain.write(KEY_PHONE, authData.phone)
        keychain.write(KEY_TOKEN, authData.token)
        keychain.write(KEY_PROFILE_COMPLETE, if (authData.isProfileComplete) "1" else "0")
        if (authData.userType != null) keychain.write(KEY_USER_TYPE, authData.userType)
        else keychain.delete(KEY_USER_TYPE)
        refresh()
    }

    override suspend fun updateUserType(userType: String) {
        keychain.write(KEY_USER_TYPE, userType)
        refresh()
    }

    override suspend fun setProfileComplete(isComplete: Boolean) {
        keychain.write(KEY_PROFILE_COMPLETE, if (isComplete) "1" else "0")
        refresh()
    }

    override suspend fun getToken(): String? = keychain.read(KEY_TOKEN)
    override suspend fun getUserId(): String? = keychain.read(KEY_USER_ID)
    override suspend fun getUserType(): String? = keychain.read(KEY_USER_TYPE)

    override suspend fun getSupabaseToken(): String? = keychain.read(KEY_SB_TOKEN)

    override suspend fun setSupabaseToken(token: String?) {
        if (token == null) keychain.delete(KEY_SB_TOKEN) else keychain.write(KEY_SB_TOKEN, token)
    }

    override fun getCachedSupabaseToken(): String? = keychain.read(KEY_SB_TOKEN)

    override suspend fun clearAuthData() {
        keychain.delete(KEY_USER_ID)
        keychain.delete(KEY_PHONE)
        keychain.delete(KEY_USER_TYPE)
        keychain.delete(KEY_TOKEN)
        keychain.delete(KEY_SB_TOKEN)
        keychain.delete(KEY_PROFILE_COMPLETE)
        refresh()
    }

    private fun refresh() {
        state.value = readAuthData()
    }

    private fun readAuthData(): AuthData? {
        val userId = keychain.read(KEY_USER_ID)
        val token = keychain.read(KEY_TOKEN)
        return if (userId != null && token != null) {
            AuthData(
                userId = userId,
                phone = keychain.read(KEY_PHONE) ?: "",
                userType = keychain.read(KEY_USER_TYPE),
                token = token,
                isProfileComplete = keychain.read(KEY_PROFILE_COMPLETE) == "1",
            )
        } else {
            null
        }
    }

    private companion object {
        const val KEY_USER_ID = "user_id"
        const val KEY_PHONE = "phone"
        const val KEY_USER_TYPE = "user_type"
        const val KEY_TOKEN = "token"
        const val KEY_SB_TOKEN = "sb_token"
        const val KEY_PROFILE_COMPLETE = "profile_complete"
    }
}
