package com.gighour.shared.data.local.db

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import com.gighour.shared.data.local.JobCache
import com.gighour.shared.db.GighourDb
import com.gighour.shared.domain.model.Job
import com.gighour.shared.util.Logger
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/**
 * SQLDelight-backed [JobCache] — the multiplatform replacement for Gigand's Room
 * JobDao/JobEntity (DATA_LAYER_PLAN Phase 6). Stores each Job as a lossless JSON
 * blob (Gigand's Room comma-join lost commas inside list values); the
 * filter/order columns are denormalized for indexable queries.
 *
 * Wire this in place of NoopJobCache: `SqlDelightJobCache(createGighourDb(driverFactory))`.
 */
class SqlDelightJobCache(
    db: GighourDb,
    private val json: Json = DEFAULT_JSON,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : JobCache {

    private val queries = db.jobCacheQueries

    override suspend fun upsertAll(jobs: List<Job>, cachedAtMillis: Long) = withContext(ioDispatcher) {
        queries.transaction {
            jobs.forEach { job ->
                queries.upsert(
                    id = job.id,
                    employer_id = job.employerId,
                    is_active = if (job.isActive) 1L else 0L,
                    title = job.title,
                    description = job.description,
                    job_date = job.jobDate,
                    created_at = job.createdAt,
                    cached_at = cachedAtMillis,
                    job_json = json.encodeToString(Job.serializer(), job),
                )
            }
        }
    }

    override suspend fun getById(jobId: String): Job? = withContext(ioDispatcher) {
        queries.selectById(jobId).executeAsOneOrNull()?.let { decode(it) }
    }

    override suspend fun getAll(): List<Job> = withContext(ioDispatcher) {
        queries.selectActive().executeAsList().mapNotNull { decode(it) }
    }

    override suspend fun search(query: String): List<Job> = withContext(ioDispatcher) {
        queries.search(query).executeAsList().mapNotNull { decode(it) }
    }

    override suspend fun clear() = withContext(ioDispatcher) {
        queries.clearAll()
    }

    /** Drop entries cached before [cutoffMillis] — the 24h cleanup parity. */
    suspend fun deleteOlderThan(cutoffMillis: Long) = withContext(ioDispatcher) {
        queries.deleteOlderThan(cutoffMillis)
    }

    override fun observeAll(): Flow<List<Job>> =
        queries.selectActive()
            .asFlow()
            .mapToList(ioDispatcher)
            .map { rows -> rows.mapNotNull { decode(it) } }

    private fun decode(jobJson: String): Job? = try {
        json.decodeFromString(Job.serializer(), jobJson)
    } catch (e: Exception) {
        // A schema-drift or corrupt row must not crash the whole list read.
        Logger.e(TAG, "JobCache decode failed: ${e.message}")
        null
    }

    companion object {
        private const val TAG = "JobCache"
        private val DEFAULT_JSON = Json { ignoreUnknownKeys = true; isLenient = true }
    }
}
