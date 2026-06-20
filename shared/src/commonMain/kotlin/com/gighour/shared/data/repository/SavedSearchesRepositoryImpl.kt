package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.SavedSearchDto
import com.gighour.shared.data.remote.SavedSearchesApi
import com.gighour.shared.domain.repository.SavedSearch
import com.gighour.shared.domain.repository.SavedSearchesRepository

/**
 * KMP port of Gigand's SavedSearchesRepository (Retrofit → Ktor). Body-error
 * check replaces Response.isSuccessful; DTO→domain is straightforward.
 */
class SavedSearchesRepositoryImpl(
    private val api: SavedSearchesApi,
) : SavedSearchesRepository {

    override suspend fun list(): Result<List<SavedSearch>> = runCatching {
        val body = api.list()
        if (body.error != null) throw Exception(body.error)
        body.searches.map { it.toDomain() }
    }

    override suspend fun delete(id: String): Result<Unit> = runCatching {
        val body = api.delete(id)
        if (body.error != null) throw Exception(body.error)
        if (!body.success) throw Exception("Failed to delete saved search")
        Unit
    }

    private fun SavedSearchDto.toDomain(): SavedSearch = SavedSearch(
        id = id,
        name = name ?: category ?: "Saved search",
        state = state,
        district = district,
        category = category,
        useCount = useCount ?: 0,
        createdAt = createdAt,
    )
}
