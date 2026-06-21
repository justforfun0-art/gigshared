package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import kotlinx.serialization.Serializable

/**
 * Semantic job-match scores for the signed-in worker (#4), from the
 * `secure/match` route (pgvector cosine over Gemini embeddings).
 */
open class MatchApi(private val client: ApiClient) {

    open suspend fun match(state: String?, district: String?, limit: Int): MatchResponse {
        val resp = client.http.post(client.urlFor("secure/match")) {
            client.applyAuth(this)
            setBody(MatchRequest(state = state, district = district, limit = limit))
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class MatchRequest(
    val state: String? = null,
    val district: String? = null,
    val limit: Int = 20,
)

@Serializable
data class MatchResponse(
    val matches: List<MatchEntry> = emptyList(),
    val error: String? = null,
)

@Serializable
data class MatchEntry(
    val jobId: String,
    val score: Int, // 0..100 "match %"
)
