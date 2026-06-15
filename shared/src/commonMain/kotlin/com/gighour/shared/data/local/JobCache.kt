package com.gighour.shared.data.local

import com.gighour.shared.domain.model.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * Local job cache abstraction. Gigand backs this with Room (JobDao/JobEntity),
 * which is Android-only; the shared layer defers a multiplatform cache
 * (SQLDelight) to a later phase (DATA_LAYER_PLAN Phase 6).
 *
 * [NoopJobCache] is the default for the first iOS-first cut: cache writes are
 * dropped and reads return empty, so [JobRepositoryImpl] runs network-direct.
 * Behaviour difference vs Gigand: no offline fallback and `observeJobs` emits
 * nothing — acceptable for the initial shared impl; swap in a real cache later
 * without touching the repo.
 */
interface JobCache {
    suspend fun upsertAll(jobs: List<Job>, cachedAtMillis: Long)
    suspend fun getById(jobId: String): Job?
    suspend fun getAll(): List<Job>
    suspend fun search(query: String): List<Job>
    suspend fun clear()
    fun observeAll(): Flow<List<Job>>
}

object NoopJobCache : JobCache {
    override suspend fun upsertAll(jobs: List<Job>, cachedAtMillis: Long) {}
    override suspend fun getById(jobId: String): Job? = null
    override suspend fun getAll(): List<Job> = emptyList()
    override suspend fun search(query: String): List<Job> = emptyList()
    override suspend fun clear() {}
    override fun observeAll(): Flow<List<Job>> = flowOf(emptyList())
}
