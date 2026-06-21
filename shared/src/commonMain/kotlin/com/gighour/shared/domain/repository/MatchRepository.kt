package com.gighour.shared.domain.repository

interface MatchRepository {
    /** Semantic match scores (jobId → 0..100) for the worker. Empty on no-embedding. */
    suspend fun matchScores(state: String?, district: String?, limit: Int): Result<Map<String, Int>>
}
