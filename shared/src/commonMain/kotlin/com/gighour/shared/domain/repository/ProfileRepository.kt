package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.EmployeeProfile
import com.gighour.shared.domain.model.EmployerProfile
import kotlinx.coroutines.flow.Flow

interface ProfileRepository {
    // Employee Profile
    suspend fun getEmployeeProfile(userId: String): Result<EmployeeProfile?>
    suspend fun createEmployeeProfile(profile: EmployeeProfile): Result<EmployeeProfile>
    suspend fun updateEmployeeProfile(profile: EmployeeProfile): Result<EmployeeProfile>
    fun observeEmployeeProfile(userId: String): Flow<EmployeeProfile?>

    // Employer Profile
    suspend fun getEmployerProfile(userId: String): Result<EmployerProfile?>
    suspend fun createEmployerProfile(profile: EmployerProfile): Result<EmployerProfile>
    suspend fun updateEmployerProfile(profile: EmployerProfile): Result<EmployerProfile>
    fun observeEmployerProfile(userId: String): Flow<EmployerProfile?>

    // Profile photo
    suspend fun uploadProfilePhoto(userId: String, photoBytes: ByteArray): Result<String>

    /**
     * Composite "GigHour Score" for a worker (0..5), computed server-side by
     * the read-only `compute_worker_rating` RPC from behavioural factors
     * (completion quality, reviews, experience, tenure, no-show penalty) — NOT
     * a raw review average. [hasRating] is false for provisional workers (no
     * completed jobs AND no reviews), in which case the UI hides stars.
     */
    suspend fun getEmployeeRating(userId: String): Result<UserRating>

    /**
     * The worker's most recent reviews (newest first, capped at 10) with the
     * reviewing employer's company name resolved. Used by the employer's
     * worker-profile view. Empty list when the worker has no reviews.
     */
    suspend fun getEmployeeReviews(userId: String): Result<List<EmployeeReview>>
}

/** A single review left for a worker, with the employer's company name resolved. */
data class EmployeeReview(
    val reviewerName: String,
    val rating: Int,
    val comment: String,
    val createdAt: String?,
)

/**
 * Composite worker rating. [hasRating] == false means "provisional / no track
 * record yet" → show no stars. [reviewCount] is how many real reviews fed in;
 * [sampleCount] is finished commitments; [breakdown] is the per-signal map for
 * an optional "why this score" UI.
 */
data class UserRating(
    val average: Double = 0.0,     // composite 0..5 (the displayed rating)
    val stars: Double = 0.0,       // rounded to nearest 0.5 for star UI
    val hasRating: Boolean = false,
    val reviewCount: Int = 0,
    val sampleCount: Int = 0,
    val completionRate: Double? = null,
)
