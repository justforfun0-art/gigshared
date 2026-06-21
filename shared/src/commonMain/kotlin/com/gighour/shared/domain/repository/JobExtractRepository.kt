package com.gighour.shared.domain.repository

interface JobExtractRepository {
    /** AI-suggested fields for a free-text job description (employer Post-Job). */
    suspend fun extract(text: String): Result<JobSuggestion>
}

/** AI suggestions to pre-fill the Post-Job form. */
data class JobSuggestion(
    val category: String?,
    val skills: List<String>,
    val title: String?,
    val description: String?,
)
