package com.gighour.shared.domain.repository

interface DashboardRepository {
    suspend fun getEmployeeStats(userId: String): Result<EmployeeDashboardStats>
    suspend fun getEmployerInsights(employerId: String): Result<EmployerInsights>

    /**
     * Employer dashboard headline stats from the pre-aggregated
     * `employer_dashboard` DB view — the same source the web app reads. The
     * server computes active-jobs, pending-review, hired-workers and the
     * month-scoped spend, so the cards match web exactly instead of being
     * re-derived (and drifting) on the client.
     */
    suspend fun getEmployerStats(employerId: String): Result<EmployerDashboardStats>
}

data class EmployerDashboardStats(
    val totalJobs: Int = 0,
    val activeJobs: Int = 0,
    val totalApplications: Int = 0,
    val pendingReview: Int = 0,
    val hiredWorkers: Int = 0,
    val totalSpent: Int = 0,
    val pendingPayments: Int = 0,
    val thisMonthSpent: Int = 0
)

/**
 * Employer hiring-health metrics from the shared `employer_insights` DB
 * function (server-computed, one round-trip). [fillRate] and [noShowRate] are
 * 0..1 fractions; [avgFillHours] / [noShowRate] / [topDistrict] are null when
 * there's no data to compute them yet.
 */
data class EmployerInsights(
    val totalJobs: Int = 0,
    val filledJobs: Int = 0,
    val fillRate: Double = 0.0,
    val avgFillHours: Double? = null,
    val completedSessions: Int = 0,
    val totalHires: Int = 0,
    val hireNoShows: Int = 0,
    val noShowRate: Double? = null,
    val topDistrict: String? = null
)

data class EmployeeDashboardStats(
    val totalApplications: Int = 0,
    val activeJobs: Int = 0,
    val completedJobs: Int = 0,
    val totalEarnings: Int = 0,
    val pendingPayments: Int = 0,
    val thisMonthEarnings: Int = 0
)
