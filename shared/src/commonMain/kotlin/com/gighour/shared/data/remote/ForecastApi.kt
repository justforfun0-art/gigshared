package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import kotlinx.serialization.Serializable

/**
 * Demand forecast for a district (#5) from the `secure/forecast` route —
 * which job categories are trending up nearby.
 */
open class ForecastApi(private val client: ApiClient) {

    open suspend fun forecast(state: String?, district: String?, limit: Int): ForecastResponse {
        val resp = client.http.post(client.urlFor("secure/forecast")) {
            client.applyAuth(this)
            setBody(ForecastRequest(state = state, district = district, limit = limit))
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class ForecastRequest(
    val state: String? = null,
    val district: String? = null,
    val limit: Int = 5,
)

@Serializable
data class ForecastResponse(
    val trends: List<DemandTrend> = emptyList(),
    val error: String? = null,
)

@Serializable
data class DemandTrend(
    val category: String,
    val recentCount: Int = 0,
    val trendPct: Int = 0,
    val rising: Boolean = false,
)
