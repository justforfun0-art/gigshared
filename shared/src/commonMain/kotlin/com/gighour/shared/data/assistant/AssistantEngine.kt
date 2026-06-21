package com.gighour.shared.data.assistant

import com.gighour.shared.data.remote.AssistantApi
import com.gighour.shared.data.remote.AssistantChatRequest
import com.gighour.shared.data.remote.AssistantContext
import com.gighour.shared.domain.model.JobFilter
import com.gighour.shared.domain.repository.ApplicationRepository
import com.gighour.shared.domain.repository.DashboardRepository
import com.gighour.shared.domain.repository.JobRepository
import com.gighour.shared.domain.repository.ProfileRepository
import com.gighour.shared.util.Logger

/** One label/value stat line in an assistant reply. */
data class AssistantStat(val label: String, val value: String)

/**
 * A confirmable action the assistant proposes (agentic). The UI renders
 * [confirmLabel] as a button; on tap it calls [AssistantEngine.executeAction]
 * with this action. [kind] + [targetId] identify what to do.
 */
data class AssistantAction(
    val kind: Kind,
    val targetId: String,
    val confirmLabel: String,
) {
    enum class Kind { APPLY_TO_JOB }
}

/** The assistant's reply: text + optional stat lines + an optional pending action. */
data class AssistantReply(
    val text: String,
    val stats: List<AssistantStat> = emptyList(),
    val action: AssistantAction? = null,
)

/**
 * KMP port of Gigand's AssistantEngine (focused). Matches the user's message to
 * an intent, answers from app data for the high-value intents (greeting,
 * applications, active jobs, why-rejected, earnings, find-jobs) + a compact FAQ,
 * and falls back to the Gemini-backed secure/assistant API for everything else.
 */
class AssistantEngine(
    private val jobs: JobRepository,
    private val applications: ApplicationRepository,
    private val profile: ProfileRepository,
    private val dashboard: DashboardRepository,
    private val assistantApi: AssistantApi,
) {

    suspend fun respond(userId: String, isEmployer: Boolean, message: String): AssistantReply {
        return when (AssistantIntent.match(message, isEmployer)) {
            AssistantIntent.GREETING -> greeting(userId, isEmployer)
            AssistantIntent.APPLICATIONS -> applications(userId, isEmployer)
            AssistantIntent.ACTIVE_JOBS -> activeJobs(userId, isEmployer)
            AssistantIntent.WHY_REJECTED -> whyRejected(userId)
            AssistantIntent.EARNINGS -> earnings(userId, isEmployer)
            AssistantIntent.FIND_JOBS -> findJobs(userId, isEmployer)
            AssistantIntent.APPLY_TOP_JOB -> proposeApplyTopJob(userId, isEmployer)
            AssistantIntent.HELP_APPLY -> AssistantReply(AssistantFaq.howToApply)
            AssistantIntent.HELP_PAYMENT -> AssistantReply(AssistantFaq.howPaymentWorks)
            AssistantIntent.HELP_OTP -> AssistantReply(AssistantFaq.otpHelp)
            AssistantIntent.WHAT_IS -> AssistantReply(AssistantFaq.whatIsGigHour)
            AssistantIntent.THANKS -> AssistantReply("You’re welcome! 😊 Ask me anything else.")
            AssistantIntent.UNKNOWN -> gemini(userId, isEmployer, message)
        }
    }

    private suspend fun greeting(userId: String, isEmployer: Boolean): AssistantReply {
        val name = if (isEmployer) {
            profile.getEmployerProfile(userId).getOrNull()?.companyName
        } else {
            profile.getEmployeeProfile(userId).getOrNull()?.name
        }
        val hi = if (!name.isNullOrBlank()) "Hi $name! 👋" else "Hi there! 👋"
        return AssistantReply("$hi\n\n${AssistantFaq.capabilities(isEmployer)}")
    }

    private suspend fun applications(userId: String, isEmployer: Boolean): AssistantReply {
        val result = if (isEmployer) applications.getEmployerApplications(userId)
        else applications.getEmployeeApplications(userId)
        return result.fold(
            onSuccess = { apps ->
                if (apps.isEmpty()) {
                    AssistantReply(
                        if (isEmployer) "No applications to your jobs yet."
                        else "You haven’t applied to any jobs yet. Swipe right on a job to apply!"
                    )
                } else {
                    val top = apps.sortedByDescending { it.appliedAt ?: "" }.take(5)
                    val lines = top.joinToString("\n") {
                        "• ${it.job?.title ?: "Job"} — ${it.status.toDisplayString()}"
                    }
                    AssistantReply("Your latest ${top.size} application(s):\n$lines")
                }
            },
            onFailure = { networkError() },
        )
    }

    private suspend fun activeJobs(userId: String, isEmployer: Boolean): AssistantReply {
        val result = if (isEmployer) applications.getEmployerApplications(userId)
        else applications.getEmployeeApplications(userId)
        return result.fold(
            onSuccess = { apps ->
                val active = apps.filter { it.status.isActive() }.take(5)
                if (active.isEmpty()) {
                    AssistantReply("You have no active jobs right now.")
                } else {
                    val lines = active.joinToString("\n") {
                        "• ${it.job?.title ?: "Job"} — ${it.status.toDisplayString()}"
                    }
                    AssistantReply("Your active job(s):\n$lines")
                }
            },
            onFailure = { networkError() },
        )
    }

    private suspend fun whyRejected(userId: String): AssistantReply {
        return applications.getEmployeeApplications(userId).fold(
            onSuccess = { apps ->
                val rejected = apps
                    .filter { it.status.toDisplayString().contains("Reject", ignoreCase = true) }
                    .maxByOrNull { it.updatedAt ?: it.appliedAt ?: "" }
                when {
                    rejected == null -> AssistantReply("Good news — none of your applications were rejected. 🎉")
                    !rejected.rejectionReason.isNullOrBlank() ->
                        AssistantReply("Your application for “${rejected.job?.title ?: "a job"}” was not selected. Reason: ${rejected.rejectionReason}")
                    else ->
                        AssistantReply("Your application for “${rejected.job?.title ?: "a job"}” wasn’t selected. The employer didn’t leave a reason — keep applying, the next one could be yours!")
                }
            },
            onFailure = { networkError() },
        )
    }

    private suspend fun earnings(userId: String, isEmployer: Boolean): AssistantReply {
        if (isEmployer) return AssistantReply("Earnings are for workers. Check your Payments tab for what you’ve paid out.")
        return dashboard.getEmployeeStats(userId).fold(
            onSuccess = { s ->
                AssistantReply(
                    "Here’s your earnings snapshot:",
                    listOf(
                        AssistantStat("Total earned", "₹${s.totalEarnings}"),
                        AssistantStat("This month", "₹${s.thisMonthEarnings}"),
                        AssistantStat("Pending", "₹${s.pendingPayments}"),
                        AssistantStat("Completed jobs", "${s.completedJobs}"),
                    ),
                )
            },
            onFailure = { networkError() },
        )
    }

    private suspend fun findJobs(userId: String, isEmployer: Boolean): AssistantReply {
        if (isEmployer) return AssistantReply("Looking to hire? Post a job from the My Jobs tab.")
        val p = profile.getEmployeeProfile(userId).getOrNull()
        val filter = p?.let { JobFilter(state = it.state, district = it.district) }
        return jobs.getJobs(filter = filter, page = 1, limit = 5).fold(
            onSuccess = { list ->
                if (list.isEmpty()) {
                    AssistantReply("No jobs in ${p?.district ?: "your area"} right now. Check back soon!")
                } else {
                    val lines = list.joinToString("\n") {
                        "• ${it.title}${it.salaryRange?.let { s -> " — $s" } ?: ""}"
                    }
                    AssistantReply("Jobs near ${p?.district ?: "you"}:\n$lines")
                }
            },
            onFailure = { networkError() },
        )
    }

    /**
     * Agentic: propose applying to the best nearby job. Returns a reply with a
     * confirmable action (the UI shows a button; tapping it calls [executeAction]).
     * Never applies directly — the user must confirm.
     */
    private suspend fun proposeApplyTopJob(userId: String, isEmployer: Boolean): AssistantReply {
        if (isEmployer) return AssistantReply("Applying to jobs is for workers. You can post a job from the My Jobs tab.")
        val p = profile.getEmployeeProfile(userId).getOrNull()
        val filter = p?.let { JobFilter(state = it.state, district = it.district) }
        return jobs.getJobs(filter = filter, page = 1, limit = 1).fold(
            onSuccess = { list ->
                val top = list.firstOrNull()
                    ?: return AssistantReply("I couldn’t find an open job near ${p?.district ?: "you"} right now. Check back soon!")
                AssistantReply(
                    text = "The best match near ${p?.district ?: "you"} is “${top.title}”" +
                        (top.salaryRange?.let { " ($it)" } ?: "") +
                        ".\n\nWant me to apply for you?",
                    action = AssistantAction(
                        kind = AssistantAction.Kind.APPLY_TO_JOB,
                        targetId = top.id,
                        confirmLabel = "Apply to “${top.title}”",
                    ),
                )
            },
            onFailure = { networkError() },
        )
    }

    /**
     * Execute a confirmed assistant action (the user tapped the confirm button).
     * Returns the result as a reply.
     */
    suspend fun executeAction(userId: String, action: AssistantAction): AssistantReply {
        return when (action.kind) {
            AssistantAction.Kind.APPLY_TO_JOB ->
                applications.applyToJob(jobId = action.targetId, employeeId = userId).fold(
                    onSuccess = { AssistantReply("Done! ✅ I’ve applied for you. You’ll be notified if you’re selected. Track it in History.") },
                    onFailure = { e ->
                        val msg = e.message ?: ""
                        if (msg.contains("already", ignoreCase = true))
                            AssistantReply("You’ve already applied to that job. 👍")
                        else networkError()
                    },
                )
        }
    }

    /** Free-form fallback through the Gemini-backed API. */
    private suspend fun gemini(userId: String, isEmployer: Boolean, message: String): AssistantReply {
        return try {
            val context = buildContext(userId, isEmployer)
            val resp = assistantApi.chat(
                AssistantChatRequest(
                    message = message,
                    userType = if (isEmployer) "EMPLOYER" else "EMPLOYEE",
                    context = context,
                )
            )
            val reply = resp.reply?.takeIf { it.isNotBlank() }
            if (reply != null) AssistantReply(reply)
            else AssistantReply(AssistantFaq.capabilities(isEmployer))
        } catch (e: Exception) {
            Logger.e(TAG, "gemini fallback failed", e)
            AssistantReply(AssistantFaq.capabilities(isEmployer))
        }
    }

    private suspend fun buildContext(userId: String, isEmployer: Boolean): AssistantContext {
        return try {
            if (isEmployer) {
                val p = profile.getEmployerProfile(userId).getOrNull()
                AssistantContext(name = p?.companyName, location = p?.district)
            } else {
                val p = profile.getEmployeeProfile(userId).getOrNull()
                val stats = dashboard.getEmployeeStats(userId).getOrNull()
                AssistantContext(
                    name = p?.name,
                    location = p?.district,
                    skills = p?.skills,
                    totalEarnings = stats?.totalEarnings?.toDouble(),
                    thisMonthEarnings = stats?.thisMonthEarnings?.toDouble(),
                    pendingPayments = stats?.pendingPayments?.toDouble(),
                    completedCount = stats?.completedJobs,
                )
            }
        } catch (e: Exception) {
            AssistantContext()
        }
    }

    private fun networkError() =
        AssistantReply("I couldn’t reach the server just now. Please check your connection and try again.")

    private companion object {
        const val TAG = "AssistantEngine"
    }
}
