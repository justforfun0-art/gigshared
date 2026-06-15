package com.gighour.shared.domain.model

import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.jsonPrimitive

/**
 * Tolerant deserializer for jobs.language_preference, which in production
 * may be stored as any of:
 *   - JSON array:           ["hi","en"]
 *   - stringified array:    "[]"  or  "[\"hi\"]"   (legacy POST writes)
 *   - comma-separated:      "hi,en"
 *   - null
 * All forms decode to List<String>?. Encoding always writes a proper array.
 */
private object LanguagePrefSerializer : KSerializer<List<String>?> {
    private val backing = ListSerializer(String.serializer())
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("LanguagePreference")

    override fun deserialize(decoder: Decoder): List<String>? {
        val jsonDecoder = decoder as? JsonDecoder
            ?: return decoder.decodeSerializableValue(backing)
        return when (val el = jsonDecoder.decodeJsonElement()) {
            is JsonNull -> null
            is JsonArray -> el.map { it.jsonPrimitive.content }
            is JsonPrimitive -> {
                if (!el.isString) return null
                val raw = el.content.trim()
                when {
                    raw.isEmpty() -> null
                    raw.startsWith("[") && raw.endsWith("]") -> {
                        val inner = raw.substring(1, raw.length - 1).trim()
                        if (inner.isEmpty()) emptyList()
                        else inner.split(",").map {
                            it.trim().trim('"').trim('\'')
                        }.filter { it.isNotEmpty() }
                    }
                    else -> raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                }
            }
            else -> null
        }
    }

    override fun serialize(encoder: Encoder, value: List<String>?) {
        val jsonEncoder = encoder as? JsonEncoder
        if (jsonEncoder == null) {
            encoder.encodeSerializableValue(backing, value ?: emptyList())
            return
        }
        if (value == null) {
            jsonEncoder.encodeJsonElement(JsonNull)
        } else {
            jsonEncoder.encodeJsonElement(buildJsonArray { value.forEach { add(JsonPrimitive(it)) } })
        }
    }
}

@Serializable
data class Job(
    val id: String,
    @SerialName("employer_id") val employerId: String,
    val title: String,
    val description: String,
    val location: String,
    @SerialName("salary_range") val salaryRange: String? = null,
    @SerialName("job_type") val jobType: String = "WEEKDAY",
    @SerialName("is_active") val isActive: Boolean = true,
    val requirements: List<String>? = null,
    @SerialName("application_deadline") val applicationDeadline: String? = null,
    val tags: List<String> = emptyList(),
    @SerialName("job_category") val jobCategory: String? = null,
    @SerialName("work_type") val workType: String? = null,
    @SerialName("preferred_skills") val preferredSkills: List<String> = emptyList(),
    @SerialName("skills_required") val skillsRequired: List<String> = emptyList(),
    @SerialName("work_duration") val workDuration: String? = null,
    @SerialName("break_duration") val breakDuration: Int? = null,
    @SerialName("is_remote") val isRemote: Boolean = false,
    val status: String? = null,
    val district: String? = null,
    val state: String? = null,
    @SerialName("job_date") val jobDate: String? = null,
    @SerialName("start_time") val startTime: String? = null,
    @SerialName("end_time") val endTime: String? = null,
    @SerialName("work_address") val workAddress: String? = null,
    @SerialName("work_google_map_location") val workGoogleMapLocation: String? = null,
    @SerialName("gender_preference") val genderPreference: String? = null,
    @SerialName("language_preference")
    @Serializable(with = LanguagePrefSerializer::class)
    val languagePreference: List<String>? = null,
    @SerialName("job_code") val jobCode: Int? = null,
    @SerialName("is_filled") val isFilled: Boolean = false,
    @SerialName("num_positions") val numPositions: Int = 1,
    @SerialName("accepted_by") val acceptedBy: String? = null,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    // Joined data
    @SerialName("employer_profiles") val employerProfile: EmployerProfile? = null,
    @SerialName("users") val employerUser: EmployerUser? = null,
    @SerialName("applications_count") val applicationsCount: Int? = null
) {
    /** Parsed enum — falls back to WEEKDAY for unknown values (e.g. legacy PART_TIME rows). */
    val jobTypeEnum: JobType get() = JobType.fromString(jobType)

    /**
     * A job is expired once wall-clock time passes its same-day cutoff on
     * job_date (or any day before that). [nowInIndia] is the caller's clock in
     * Asia/Kolkata as a wall-clock [LocalDateTime] — pass
     * ServerTimeService's server-now-in-India so the check tracks the backend,
     * not the device.
     *
     * Cutoff resolution mirrors the web's `isJobExpired`
     * (src/lib/application-status.ts) so both platforms — and the SQL
     * `fn_expire_pending_applications` — agree:
     *   - start_time present → start_time + 30-min grace
     *   - else end_time present → end_time (no grace)
     *   - else → end-of-day (23:59)
     * The end_time / end-of-day fallbacks keep legacy/imported rows that lack a
     * start_time from being treated as never-expiring (the old behaviour here).
     */
    fun isExpired(nowInIndia: LocalDateTime): Boolean {
        val date = jobDate ?: return false
        val jobLocalDate = runCatching { LocalDate.parse(date.take(10)) }.getOrNull()
            ?: return false
        val today = nowInIndia.date
        if (jobLocalDate < today) return true
        if (jobLocalDate > today) return false
        val cutoffMinutes = resolveExpiryCutoffMinutes() ?: return false
        val nowMinutes = nowInIndia.hour * 60 + nowInIndia.minute
        return nowMinutes >= cutoffMinutes
    }

    /**
     * Same-day expiry cutoff time as minutes-since-midnight, following the
     * web's fallback chain. Returns null only when no usable time can be
     * derived (shouldn't happen — the end-of-day fallback always applies).
     *
     * Note: kotlinx-datetime's LocalTime has no arithmetic, so we compute in
     * minutes-of-day. The +30 grace can push start_time past 24h (e.g. a 23:50
     * start → 24:20); that's fine — nowMinutes maxes at 23*60+59 = 1439, so a
     * cutoff ≥ 1440 simply means "never expires today", matching the intent
     * that an almost-midnight job stays open through end of day.
     */
    private fun resolveExpiryCutoffMinutes(): Int? {
        startTime?.takeIf { it.isNotBlank() }?.let { start ->
            runCatching {
                val parts = start.split(":").map { it.toInt() }
                return parts[0] * 60 + parts.getOrElse(1) { 0 } + 30
            }
        }
        endTime?.takeIf { it.isNotBlank() }?.let { end ->
            runCatching {
                val parts = end.split(":").map { it.toInt() }
                return parts[0] * 60 + parts.getOrElse(1) { 0 }
            }
        }
        // No start or end time → expire at end of the job_date (23:59).
        return 23 * 60 + 59
    }

    /**
     * Status-aware expiry. A worker who's already started the job keeps it
     * "active" past the clock cutoff until the work finishes — otherwise the
     * employer card flips to "Expired" while the timer is still ticking.
     * Pass the applications already known for this job; only those in
     * [IN_FLIGHT_WORK_STATUSES] suppress expiry.
     */
    fun isExpired(
        nowInIndia: LocalDateTime,
        applicationsForJob: List<Application>
    ): Boolean {
        if (applicationsForJob.any { it.status in IN_FLIGHT_WORK_STATUSES }) return false
        return isExpired(nowInIndia)
    }

    /**
     * True when the job is awaiting admin approval (server status PENDING /
     * PENDING_APPROVAL). Single source of truth shared by My Jobs (Pending
     * filter, stat counts, card pill) and the employer dashboard's Active-Jobs
     * count, so the numbers can't drift apart.
     */
    fun isPendingApproval(): Boolean =
        status?.uppercase()?.let { it == "PENDING" || it == "PENDING_APPROVAL" } ?: false

    /** True when an admin rejected this listing (jobs.status REJECTED). The
     *  row keeps is_active=true in the DB, so without this check a rejected
     *  job would still read as "active" to the employer. */
    fun isRejectedByAdmin(): Boolean = status?.uppercase() == "REJECTED"

    /**
     * True when the job is a live, approved, non-expired listing — i.e. what
     * the employer thinks of as an "active job". Mirrors the My Jobs "Active"
     * filter exactly. [isExpiredForJob] lets the caller pass its own
     * status-aware expiry result (e.g. one that keeps a job open while a worker
     * is mid-shift); defaults to the plain time-based expiry.
     */
    fun isActiveListing(
        nowInIndia: LocalDateTime,
        isExpiredForJob: Boolean = isExpired(nowInIndia)
    ): Boolean = isActive && !isPendingApproval() && !isRejectedByAdmin() && !isExpiredForJob
}

/**
 * Application statuses that represent work the worker has started but not
 * yet been paid out for. While any application on a job is in one of these
 * states, the job should not be flagged as expired for the employer.
 */
val IN_FLIGHT_WORK_STATUSES: Set<ApplicationStatus> = setOf(
    ApplicationStatus.WORK_IN_PROGRESS,
    ApplicationStatus.COMPLETION_PENDING,
    ApplicationStatus.PAYMENT_PENDING
)

@Serializable
enum class JobType {
    WEEKDAY,
    WEEKEND;

    companion object {
        fun fromString(value: String?): JobType {
            return when (value?.uppercase()) {
                "WEEKDAY" -> WEEKDAY
                "WEEKEND" -> WEEKEND
                else -> WEEKDAY
            }
        }
    }

    fun toDisplayString(): String {
        return when (this) {
            WEEKDAY -> "Weekday"
            WEEKEND -> "Weekend"
        }
    }
}

@Serializable
data class EmployerUser(
    @SerialName("user_id") val userId: String? = null,
    val phone: String? = null
)

@Serializable
data class JobFilter(
    val state: String? = null,
    val district: String? = null,
    val jobType: JobType? = null,
    val minSalary: Int? = null,
    val maxSalary: Int? = null,
    val skills: List<String> = emptyList(),
    val searchQuery: String? = null
)
