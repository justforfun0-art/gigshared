package com.gighour.shared.data.local

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.gighour.shared.domain.model.AuthData
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicReference

/**
 * Android [SessionStore] backed by EncryptedSharedPreferences (Android Keystore)
 * — the shared-module counterpart of Gigand's AuthPreferences. Preserves the
 * key guarantees:
 *  - tokens at rest only (encrypted prefs);
 *  - [authDataFlow] gated on an `initialized` deferred so collectors never see a
 *    transient logged-out emit before the first disk load;
 *  - in-memory mirror (AtomicReference) for the synchronous cached reads.
 *
 * Deliberately omits Gigand's one-time legacy-DataStore migration — that's an
 * :app concern. When :app adopts :shared, either keep AuthPreferences as the
 * SessionStore impl or migrate its keys here. Uses a DISTINCT prefs file from
 * Gigand's "gighour_secure_prefs" to avoid two owners of one file.
 */
class AndroidSessionStore(
    context: Context,
    prefsFileName: String = "gighour_shared_session",
) : SessionStore {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

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

    private val cachedToken = AtomicReference<String?>(null)
    private val cachedSupabaseToken = AtomicReference<String?>(null)
    private val cachedUserId = AtomicReference<String?>(null)

    private val authState = MutableStateFlow<AuthData?>(null)
    private val initialized = CompletableDeferred<Unit>()

    override val authDataFlow: Flow<AuthData?> = flow {
        initialized.await()
        emitAll(authState)
    }

    init {
        scope.launch {
            refreshFromPrefs()
            initialized.complete(Unit)
        }
    }

    override suspend fun saveAuthData(authData: AuthData) {
        initialized.await()
        val editor = securePrefs.edit()
            .putString(KEY_USER_ID, authData.userId)
            .putString(KEY_PHONE, authData.phone)
            .putString(KEY_TOKEN, authData.token)
            .putBoolean(KEY_PROFILE_COMPLETE, authData.isProfileComplete)
        authData.userType?.let { editor.putString(KEY_USER_TYPE, it) }
        editor.apply()
        refreshFromPrefs()
    }

    override suspend fun updateUserType(userType: String) {
        initialized.await()
        securePrefs.edit().putString(KEY_USER_TYPE, userType).apply()
        refreshFromPrefs()
    }

    override suspend fun setProfileComplete(isComplete: Boolean) {
        initialized.await()
        securePrefs.edit().putBoolean(KEY_PROFILE_COMPLETE, isComplete).apply()
        refreshFromPrefs()
    }

    override suspend fun getToken(): String? {
        initialized.await()
        return securePrefs.getString(KEY_TOKEN, null)
    }

    override suspend fun getUserId(): String? {
        initialized.await()
        return securePrefs.getString(KEY_USER_ID, null)
    }

    override suspend fun getUserType(): String? {
        initialized.await()
        return securePrefs.getString(KEY_USER_TYPE, null)
    }

    override suspend fun getSupabaseToken(): String? {
        initialized.await()
        return securePrefs.getString(KEY_SB_TOKEN, null)
    }

    override suspend fun setSupabaseToken(token: String?) {
        initialized.await()
        cachedSupabaseToken.set(token)
        val editor = securePrefs.edit()
        if (token != null) editor.putString(KEY_SB_TOKEN, token) else editor.remove(KEY_SB_TOKEN)
        editor.apply()
    }

    override fun getCachedSupabaseToken(): String? = cachedSupabaseToken.get()

    override suspend fun clearAuthData() {
        initialized.await()
        securePrefs.edit()
            .remove(KEY_USER_ID)
            .remove(KEY_PHONE)
            .remove(KEY_USER_TYPE)
            .remove(KEY_TOKEN)
            .remove(KEY_SB_TOKEN)
            .remove(KEY_PROFILE_COMPLETE)
            .apply()
        refreshFromPrefs()
    }

    private fun refreshFromPrefs() {
        val userId = securePrefs.getString(KEY_USER_ID, null)
        val token = securePrefs.getString(KEY_TOKEN, null)
        cachedToken.set(token)
        cachedSupabaseToken.set(securePrefs.getString(KEY_SB_TOKEN, null))
        cachedUserId.set(userId)
        authState.value = if (userId != null && token != null) {
            AuthData(
                userId = userId,
                phone = securePrefs.getString(KEY_PHONE, null) ?: "",
                userType = securePrefs.getString(KEY_USER_TYPE, null),
                token = token,
                isProfileComplete = securePrefs.getBoolean(KEY_PROFILE_COMPLETE, false),
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
