package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.ForecastApi
import com.gighour.shared.domain.repository.DemandInfo
import com.gighour.shared.domain.repository.ForecastRepository

class ForecastRepositoryImpl(
    private val api: ForecastApi,
) : ForecastRepository {

    override suspend fun demand(
        state: String?,
        district: String?,
        limit: Int,
    ): Result<List<DemandInfo>> = runCatching {
        val body = api.forecast(state, district, limit)
        if (body.error != null) throw Exception(body.error)
        body.trends.map { DemandInfo(it.category, it.recentCount, it.trendPct, it.rising) }
    }
}
