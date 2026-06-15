package com.gighour.shared

import com.gighour.shared.data.BackendConfig
import com.gighour.shared.data.local.SecureTokenStore
import com.gighour.shared.data.remote.ApiClient
import com.gighour.shared.data.remote.JobResponse
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JobsApiDtoTest {

    private val json = ApiClient.DEFAULT_JSON

    /**
     * Gigand's Gson DTO used @SerializedName(value="data", alternate=["job"]).
     * The server returns the job under EITHER key, so the kotlinx port must
     * accept both via @JsonNames — verify both shapes decode.
     */
    @Test
    fun jobResponse_acceptsBothDataAndJobKeys() {
        val jobBody = """{"id":"j1","employer_id":"e1","title":"T","description":"D","location":"L"}"""

        val underData = json.decodeFromString<JobResponse>("""{"success":true,"data":$jobBody}""")
        assertNotNull(underData.job)
        assertEquals("j1", underData.job!!.id)

        val underJob = json.decodeFromString<JobResponse>("""{"success":true,"job":$jobBody}""")
        assertNotNull(underJob.job)
        assertEquals("j1", underJob.job!!.id)

        val errorShape = json.decodeFromString<JobResponse>("""{"success":false,"error":"nope"}""")
        assertNull(errorShape.job)
        assertEquals("nope", errorShape.error)
    }

    /** urlFor must join the trailing-slashed base with a leading-slash-tolerant path, no doubles. */
    @Test
    fun apiClient_urlFor_joinsCleanly() = runTest {
        val config = BackendConfig(
            supabaseUrl = "https://x.supabase.co",
            supabaseAnonKey = "anon",
            apiBaseUrl = "https://app.example.com/api/",
        )
        val client = ApiClient(config, NoopTokenStore)
        assertEquals("https://app.example.com/api/secure/jobs", client.urlFor("secure/jobs"))
        assertEquals("https://app.example.com/api/secure/jobs", client.urlFor("/secure/jobs"))
    }

    private object NoopTokenStore : SecureTokenStore {
        override suspend fun getSupabaseToken(): String? = null
        override suspend fun setSupabaseToken(token: String?) {}
        override suspend fun getAuthToken(): String? = null
        override suspend fun setAuthToken(token: String?) {}
        override suspend fun getUserId(): String? = null
        override suspend fun hasCachedSupabaseToken(): Boolean = false
        override suspend fun clear() {}
    }
}
