package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.MatchApi
import com.gighour.shared.domain.repository.MatchRepository

class MatchRepositoryImpl(
    private val api: MatchApi,
) : MatchRepository {

    override suspend fun matchScores(
        state: String?,
        district: String?,
        limit: Int,
    ): Result<Map<String, Int>> = runCatching {
        val body = api.match(state, district, limit)
        if (body.error != null) throw Exception(body.error)
        body.matches.associate { it.jobId to it.score }
    }
}
