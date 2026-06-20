package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.EmployeeProfileRequest
import com.gighour.shared.data.remote.EmployerProfileRequest
import com.gighour.shared.data.remote.ProfileApi
import com.gighour.shared.domain.model.EmployeeProfile
import com.gighour.shared.domain.model.EmployerProfile
import com.gighour.shared.domain.repository.EmployeeReview
import com.gighour.shared.domain.repository.ProfileRepository
import com.gighour.shared.domain.repository.UserRating
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * KMP port of Gigand's ProfileRepositoryImpl. Supabase-first reads + Ktor
 * (formerly Retrofit) write/legacy-read fallback. android.util.Log → [Logger].
 * The Retrofit HttpException "no rows" detection (404 / PGRST116) is replicated
 * against [com.gighour.shared.data.remote.HttpResult].statusCode + body error
 * text. The "only send web-editable fields" rule on updateEmployeeProfile is
 * preserved (other columns have CHECK constraints).
 */
class ProfileRepositoryImpl(
    private val profileApi: ProfileApi,
    private val supabaseClient: SupabaseClient,
) : ProfileRepository {

    override suspend fun getEmployeeProfile(userId: String): Result<EmployeeProfile?> {
        try {
            val profile = supabaseClient.from("employee_profiles")
                .select {
                    filter { eq("user_id", userId) }
                    limit(1L)
                }
                .decodeSingleOrNull<EmployeeProfile>()
            if (profile != null) return Result.success(profile)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeProfile: Supabase failed: ${e.message}")
        }

        return try {
            val legacy = runCatching { profileApi.getProfileLegacy(userId) }.getOrNull()
            if (legacy != null) {
                if (!legacy.isSuccessful && !isNoRowsFound(legacy.statusCode, legacy.body.error)) {
                    return Result.failure(Exception(legacy.body.error ?: "Failed to load profile"))
                }
                if (legacy.body.success) return Result.success(legacy.body.employeeProfile)
            }
            Result.success(null)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeProfile: all sources failed", e)
            Result.failure(e)
        }
    }

    override suspend fun createEmployeeProfile(profile: EmployeeProfile): Result<EmployeeProfile> {
        return try {
            val response = profileApi.createEmployeeProfile(profile.toEmployeeProfileRequest())
            if (response.success && response.profile != null) Result.success(response.profile)
            else Result.failure(Exception(response.error ?: "Failed to create profile"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun updateEmployeeProfile(profile: EmployeeProfile): Result<EmployeeProfile> {
        return try {
            // Mirror web: only send fields the web profile edit page sends. Other
            // columns have CHECK constraints with specific enum values; resending
            // stale free-form values from the local profile would trip them.
            val request = EmployeeProfileRequest(
                name = profile.name,
                dob = profile.dob,
                gender = profile.gender.name,
                state = profile.state,
                district = profile.district,
                email = profile.email,
                bio = profile.bio,
                skills = profile.skills,
            )
            val response = profileApi.updateEmployeeProfile(request)
            if (response.success && response.profile != null) Result.success(response.profile)
            else Result.failure(Exception(response.error ?: "Failed to update profile"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override fun observeEmployeeProfile(userId: String): Flow<EmployeeProfile?> = flow {
        emit(getEmployeeProfile(userId).getOrNull())
    }

    override suspend fun getEmployerProfile(userId: String): Result<EmployerProfile?> {
        try {
            val profile = supabaseClient.from("employer_profiles")
                .select {
                    filter { eq("user_id", userId) }
                    limit(1L)
                }
                .decodeSingleOrNull<EmployerProfile>()
            if (profile != null) return Result.success(profile)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerProfile: Supabase failed: ${e.message}")
        }

        return try {
            val legacy = runCatching { profileApi.getProfileLegacy(userId) }.getOrNull()
            if (legacy != null) {
                if (!legacy.isSuccessful && !isNoRowsFound(legacy.statusCode, legacy.body.error)) {
                    return Result.failure(Exception(legacy.body.error ?: "Failed to load profile"))
                }
                if (legacy.body.success) return Result.success(legacy.body.employerProfile)
            }
            Result.success(null)
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerProfile: all sources failed", e)
            Result.failure(e)
        }
    }

    override suspend fun createEmployerProfile(profile: EmployerProfile): Result<EmployerProfile> {
        return try {
            val response = profileApi.createEmployerProfile(profile.toEmployerProfileRequest())
            if (response.success && response.profile != null) Result.success(response.profile)
            else Result.failure(Exception(response.error ?: "Failed to create profile"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun updateEmployerProfile(profile: EmployerProfile): Result<EmployerProfile> {
        return try {
            val response = profileApi.updateEmployerProfile(profile.toEmployerProfileRequest())
            if (response.success && response.profile != null) Result.success(response.profile)
            else Result.failure(Exception(response.error ?: "Failed to update profile"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override fun observeEmployerProfile(userId: String): Flow<EmployerProfile?> = flow {
        emit(getEmployerProfile(userId).getOrNull())
    }

    override suspend fun uploadProfilePhoto(userId: String, photoBytes: ByteArray): Result<String> {
        return try {
            val bucket = supabaseClient.storage.from("profile-photos")
            val path = "$userId/profile.jpg"
            bucket.upload(path, photoBytes) {
                upsert = true
            }
            Result.success(bucket.publicUrl(path))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    override suspend fun getEmployeeRating(userId: String): Result<UserRating> {
        return try {
            // Composite GigHour Score from the read-only compute_worker_rating
            // RPC (completion quality + reviews + experience + tenure − no-show).
            // NOT a raw review average. The fn returns NULL rating for
            // provisional workers (no completed jobs AND no reviews).
            val result = supabaseClient.postgrest.rpc(
                function = "compute_worker_rating",
                parameters = buildJsonObject { put("p_worker_id", userId) },
            )
            val row = rpcJson.decodeFromString<List<WorkerRatingRow>>(result.data).firstOrNull()
            if (row?.rating == null) {
                // Provisional / no track record → no stars.
                Result.success(
                    UserRating(
                        hasRating = false,
                        reviewCount = row?.reviewCount ?: 0,
                        sampleCount = row?.sampleCount ?: 0,
                    )
                )
            } else {
                Result.success(
                    UserRating(
                        average = row.rating,
                        stars = row.stars ?: row.rating,
                        hasRating = true,
                        reviewCount = row.reviewCount ?: 0,
                        sampleCount = row.sampleCount ?: 0,
                        completionRate = row.completionRate,
                    )
                )
            }
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeRating failed", e)
            Result.failure(e)
        }
    }

    override suspend fun getEmployeeReviews(userId: String): Result<List<EmployeeReview>> {
        return try {
            val rows = supabaseClient.from("reviews")
                .select(Columns.raw("id, rating, comment, created_at, reviewer_id")) {
                    filter { eq("reviewee_id", userId) }
                    order("created_at", Order.DESCENDING)
                    limit(10)
                }
                .decodeList<ReviewRow>()

            if (rows.isEmpty()) return Result.success(emptyList())

            // Resolve reviewer (employer) company names in one batch query.
            val reviewerIds = rows.map { it.reviewerId }.distinct()
            val names: Map<String, String> = if (reviewerIds.isNotEmpty()) {
                supabaseClient.from("employer_profiles")
                    .select(Columns.raw("user_id, company_name")) {
                        filter { isIn("user_id", reviewerIds) }
                    }
                    .decodeList<EmployerNameRow>()
                    .associate { it.userId to (it.companyName ?: "Employer") }
            } else emptyMap()

            Result.success(
                rows.map {
                    EmployeeReview(
                        reviewerName = names[it.reviewerId] ?: "Employer",
                        rating = it.rating,
                        comment = it.comment.orEmpty(),
                        createdAt = it.createdAt,
                    )
                }
            )
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeReviews failed", e)
            Result.failure(e)
        }
    }

    @Serializable
    private data class ReviewRow(
        val rating: Int,
        val comment: String? = null,
        @SerialName("created_at") val createdAt: String? = null,
        @SerialName("reviewer_id") val reviewerId: String,
    )

    @Serializable
    private data class EmployerNameRow(
        @SerialName("user_id") val userId: String,
        @SerialName("company_name") val companyName: String? = null,
    )

    @Serializable
    private data class WorkerRatingRow(
        val rating: Double? = null,
        val stars: Double? = null,
        @SerialName("sample_count") val sampleCount: Int? = null,
        @SerialName("review_count") val reviewCount: Int? = null,
        @SerialName("completion_rate") val completionRate: Double? = null,
    )

    private val rpcJson = Json { ignoreUnknownKeys = true; isLenient = true }

    private fun isNoRowsFound(statusCode: Int, errorBody: String?): Boolean {
        if (statusCode == 404) return true
        val body = errorBody.orEmpty()
        return body.contains("PGRST116", ignoreCase = true) ||
            body.contains("no rows returned", ignoreCase = true) ||
            body.contains("JSON object requested", ignoreCase = true)
    }

    companion object {
        private const val TAG = "ProfileRepository"
    }
}

private fun EmployeeProfile.toEmployeeProfileRequest(): EmployeeProfileRequest =
    EmployeeProfileRequest(
        name = name,
        dob = dob,
        gender = gender.name,
        hasComputerKnowledge = hasComputerKnowledge,
        state = state,
        district = district,
        email = email,
        profilePhotoUrl = profilePhotoUrl,
        bio = bio,
        skills = skills,
        languagesKnown = languagesKnown,
        workPreferences = workPreferences?.map { it.name },
        preferredWorkingHours = preferredWorkingHours,
        fitnessLevel = fitnessLevel,
        upiId = upiId,
    )

private fun EmployerProfile.toEmployerProfileRequest(): EmployerProfileRequest =
    EmployerProfileRequest(
        companyName = companyName,
        industry = industry,
        companySize = companySize,
        website = website,
        description = description,
        state = state,
        district = district,
        address = address,
        profilePhotoUrl = profilePhotoUrl,
        gstNumber = gstNumber,
        googleMapLocation = googleMapLocation,
    )
