package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import kotlinx.serialization.Serializable

/**
 * Auto-categorize a free-text job description via the Gemini-backed
 * `secure/extract-job` route. Returns suggested category / skills / title /
 * description for the employer to accept in the Post-Job form.
 */
open class JobExtractApi(private val client: ApiClient) {

    open suspend fun extract(text: String): JobExtractResponse {
        val resp = client.http.post(client.urlFor("secure/extract-job")) {
            client.applyAuth(this)
            setBody(JobExtractRequest(text = text))
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class JobExtractRequest(val text: String)

@Serializable
data class JobExtractResponse(
    val category: String? = null,
    val skills: List<String> = emptyList(),
    val title: String? = null,
    val description: String? = null,
    val error: String? = null,
)
