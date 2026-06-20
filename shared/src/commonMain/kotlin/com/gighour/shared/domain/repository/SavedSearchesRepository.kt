package com.gighour.shared.domain.repository

interface SavedSearchesRepository {
    suspend fun list(): Result<List<SavedSearch>>
    suspend fun delete(id: String): Result<Unit>
}

/** A worker's saved job search (name + the filters it captured). */
data class SavedSearch(
    val id: String,
    val name: String,
    val state: String?,
    val district: String?,
    val category: String?,
    val useCount: Int,
    val createdAt: String?,
)
