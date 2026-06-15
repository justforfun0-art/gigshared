package com.gighour.shared.data.repository

import com.gighour.shared.data.local.SecureTokenStore
import com.gighour.shared.domain.repository.DashboardRepository
import com.gighour.shared.domain.repository.EmployeeDashboardStats
import com.gighour.shared.domain.repository.EmployerDashboardStats
import com.gighour.shared.domain.repository.EmployerInsights
import com.gighour.shared.util.Logger
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.math.round

/**
 * Ported from Gigand (Supabase-only repo, no Retrofit). Differences from the
 * Android original, all platform-neutralizing:
 *  - android.util.Log → [Logger]
 *  - AuthPreferences → [SecureTokenStore] (only getUserId() is used, for the
 *    session-vs-requested id security check)
 *  - java.lang.SecurityException → IllegalStateException (KMP has no SecurityException)
 * The view/RPC names, decode shapes, and Math.round() web-parity are unchanged.
 */
class DashboardRepositoryImpl(
    private val supabaseClient: SupabaseClient,
    private val tokenStore: SecureTokenStore,
) : DashboardRepository {

    // Lenient RPC decoder — an added column must not throw and silently disable
    // insights (see project_ranking_decode_bug).
    private val rpcJson = Json { ignoreUnknownKeys = true; isLenient = true }

    override suspend fun getEmployeeStats(userId: String): Result<EmployeeDashboardStats> {
        return try {
            val sessionUserId = tokenStore.getUserId()
            if (sessionUserId != null && sessionUserId != userId) {
                Logger.e(TAG, "getEmployeeStats: userId mismatch — session=$sessionUserId requested=$userId")
                return Result.failure(IllegalStateException("User ID does not match authenticated session"))
            }

            val statsRow = supabaseClient.from("employee_stats")
                .select {
                    filter { eq("user_id", userId) }
                    limit(1L)
                }
                .decodeSingleOrNull<EmployeeStatsRow>()

            if (statsRow != null) {
                // Match web: Math.round() (half-up), not truncation, so the same
                // row produces the same integer rupee value on both platforms.
                Result.success(
                    EmployeeDashboardStats(
                        totalApplications = statsRow.totalApplications ?: 0,
                        activeJobs = statsRow.activeJobs ?: 0,
                        completedJobs = statsRow.completedJobs ?: 0,
                        totalEarnings = round(statsRow.totalEarnings ?: 0.0).toInt(),
                        pendingPayments = round(statsRow.pendingPayments ?: 0.0).toInt(),
                        thisMonthEarnings = round(statsRow.thisMonthEarnings ?: 0.0).toInt(),
                    )
                )
            } else {
                Result.success(EmployeeDashboardStats())
            }
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployeeStats: failed", e)
            Result.failure(e)
        }
    }

    override suspend fun getEmployerInsights(employerId: String): Result<EmployerInsights> {
        return try {
            val result = supabaseClient.postgrest.rpc(
                function = "employer_insights",
                parameters = buildJsonObject { put("p_employer_id", employerId) },
            )
            val rows = rpcJson.decodeFromString<List<EmployerInsightsRow>>(result.data)
            val row = rows.firstOrNull() ?: return Result.success(EmployerInsights())
            Result.success(
                EmployerInsights(
                    totalJobs = row.totalJobs ?: 0,
                    filledJobs = row.filledJobs ?: 0,
                    fillRate = row.fillRate ?: 0.0,
                    avgFillHours = row.avgFillHours,
                    completedSessions = row.completedSessions ?: 0,
                    totalHires = row.totalHires ?: 0,
                    hireNoShows = row.hireNoShows ?: 0,
                    noShowRate = row.noShowRate,
                    topDistrict = row.topDistrict,
                )
            )
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerInsights failed", e)
            Result.failure(e)
        }
    }

    override suspend fun getEmployerStats(employerId: String): Result<EmployerDashboardStats> {
        return try {
            val row = supabaseClient.from("employer_dashboard")
                .select {
                    filter { eq("user_id", employerId) }
                    limit(1L)
                }
                .decodeSingleOrNull<EmployerDashboardRow>()

            if (row != null) {
                Result.success(
                    EmployerDashboardStats(
                        totalJobs = row.totalJobs ?: 0,
                        activeJobs = row.activeJobs ?: 0,
                        totalApplications = row.totalApplicationsReceived ?: 0,
                        pendingReview = row.pendingReview ?: 0,
                        hiredWorkers = row.hiredWorkers ?: 0,
                        totalSpent = round(row.totalSpent ?: 0.0).toInt(),
                        pendingPayments = round(row.pendingPayments ?: 0.0).toInt(),
                        thisMonthSpent = round(row.thisMonthSpent ?: 0.0).toInt(),
                    )
                )
            } else {
                Result.success(EmployerDashboardStats())
            }
        } catch (e: Exception) {
            Logger.e(TAG, "getEmployerStats: failed", e)
            Result.failure(e)
        }
    }

    companion object {
        private const val TAG = "DashboardRepository"
    }
}

@Serializable
private data class EmployerDashboardRow(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("total_jobs") val totalJobs: Int? = null,
    @SerialName("active_jobs") val activeJobs: Int? = null,
    @SerialName("total_applications_received") val totalApplicationsReceived: Int? = null,
    @SerialName("pending_review") val pendingReview: Int? = null,
    @SerialName("hired_workers") val hiredWorkers: Int? = null,
    @SerialName("total_spent") val totalSpent: Double? = null,
    @SerialName("pending_payments") val pendingPayments: Double? = null,
    @SerialName("this_month_spent") val thisMonthSpent: Double? = null,
)

@Serializable
private data class EmployerInsightsRow(
    @SerialName("total_jobs") val totalJobs: Int? = null,
    @SerialName("filled_jobs") val filledJobs: Int? = null,
    @SerialName("fill_rate") val fillRate: Double? = null,
    @SerialName("avg_fill_hours") val avgFillHours: Double? = null,
    @SerialName("completed_sessions") val completedSessions: Int? = null,
    @SerialName("total_hires") val totalHires: Int? = null,
    @SerialName("hire_no_shows") val hireNoShows: Int? = null,
    @SerialName("no_show_rate") val noShowRate: Double? = null,
    @SerialName("top_district") val topDistrict: String? = null,
)

@Serializable
private data class EmployeeStatsRow(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("total_applications") val totalApplications: Int? = null,
    @SerialName("active_jobs") val activeJobs: Int? = null,
    @SerialName("completed_jobs") val completedJobs: Int? = null,
    @SerialName("total_earnings") val totalEarnings: Double? = null,
    @SerialName("pending_payments") val pendingPayments: Double? = null,
    @SerialName("this_month_earnings") val thisMonthEarnings: Double? = null,
)
