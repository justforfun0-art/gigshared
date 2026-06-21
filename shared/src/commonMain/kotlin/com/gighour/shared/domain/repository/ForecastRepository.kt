package com.gighour.shared.domain.repository

interface ForecastRepository {
    /** Rising/steady demand trends for the district. Empty on no data. */
    suspend fun demand(state: String?, district: String?, limit: Int): Result<List<DemandInfo>>
}

/** One category's demand trend in a district. */
data class DemandInfo(
    val category: String,
    val recentCount: Int,
    val trendPct: Int,
    val rising: Boolean,
)
