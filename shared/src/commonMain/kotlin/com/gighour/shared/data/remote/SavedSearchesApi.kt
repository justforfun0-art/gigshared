package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit SavedSearchesApi. The worker's saved job
 * searches live behind the `secure/saved-searches` REST route (list + delete;
 * create is web-only for now). Auth + token rotation handled by [ApiClient].
 */
open class SavedSearchesApi(private val client: ApiClient) {

    open suspend fun list(): SavedSearchesListResponse {
        val resp = client.http.get(client.urlFor("secure/saved-searches")) {
            client.applyAuth(this)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    open suspend fun delete(id: String): SavedSearchDeleteResponse {
        val resp = client.http.delete(client.urlFor("secure/saved-searches")) {
            client.applyAuth(this)
            parameter("id", id)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class SavedSearchesListResponse(
    val searches: List<SavedSearchDto> = emptyList(),
    val error: String? = null,
)

@Serializable
data class SavedSearchDeleteResponse(
    val success: Boolean = false,
    val error: String? = null,
)

@Serializable
data class SavedSearchDto(
    val id: String,
    @SerialName("user_id") val userId: String? = null,
    val name: String? = null,
    val state: String? = null,
    val district: String? = null,
    val category: String? = null,
    @SerialName("is_default") val isDefault: Boolean? = null,
    @SerialName("use_count") val useCount: Int? = null,
    @SerialName("last_used_at") val lastUsedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)
