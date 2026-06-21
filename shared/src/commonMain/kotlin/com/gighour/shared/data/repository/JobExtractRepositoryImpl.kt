package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.JobExtractApi
import com.gighour.shared.domain.repository.JobExtractRepository
import com.gighour.shared.domain.repository.JobSuggestion

class JobExtractRepositoryImpl(
    private val api: JobExtractApi,
) : JobExtractRepository {

    override suspend fun extract(text: String): Result<JobSuggestion> = runCatching {
        val body = api.extract(text)
        if (body.error != null) throw Exception(body.error)
        JobSuggestion(
            category = body.category,
            skills = body.skills,
            title = body.title,
            description = body.description,
        )
    }
}
