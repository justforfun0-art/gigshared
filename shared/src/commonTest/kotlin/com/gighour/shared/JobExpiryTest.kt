package com.gighour.shared

import com.gighour.shared.domain.model.Application
import com.gighour.shared.domain.model.ApplicationStatus
import com.gighour.shared.domain.model.Job
import com.gighour.shared.domain.model.effectiveStatus
import kotlinx.datetime.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class JobExpiryTest {

    private fun job(
        jobDate: String? = "2026-06-14",
        startTime: String? = null,
        endTime: String? = null,
    ) = Job(
        id = "j1",
        employerId = "e1",
        title = "T",
        description = "D",
        location = "L",
        jobDate = jobDate,
        startTime = startTime,
        endTime = endTime,
    )

    private fun at(date: String, hour: Int, minute: Int) =
        LocalDateTime(
            year = date.substring(0, 4).toInt(),
            monthNumber = date.substring(5, 7).toInt(),
            dayOfMonth = date.substring(8, 10).toInt(),
            hour = hour,
            minute = minute,
        )

    @Test
    fun nullJobDate_neverExpires() {
        assertFalse(job(jobDate = null).isExpired(at("2026-06-14", 23, 59)))
    }

    @Test
    fun pastDate_isExpired_futureDate_isNot() {
        val j = job(jobDate = "2026-06-14", startTime = "10:00")
        assertTrue(j.isExpired(at("2026-06-15", 0, 1)))   // day after
        assertFalse(j.isExpired(at("2026-06-13", 23, 59))) // day before
    }

    @Test
    fun startTime_appliesThirtyMinuteGrace() {
        val j = job(startTime = "10:00") // cutoff = 10:30
        assertFalse(j.isExpired(at("2026-06-14", 10, 29)))
        assertTrue(j.isExpired(at("2026-06-14", 10, 30)))  // boundary: >= cutoff expires
        assertTrue(j.isExpired(at("2026-06-14", 11, 0)))
    }

    @Test
    fun endTime_usedWhenNoStart_noGrace() {
        val j = job(startTime = null, endTime = "18:00") // cutoff = 18:00
        assertFalse(j.isExpired(at("2026-06-14", 17, 59)))
        assertTrue(j.isExpired(at("2026-06-14", 18, 0)))
    }

    @Test
    fun noTimes_fallsBackToEndOfDay() {
        val j = job(startTime = null, endTime = null) // cutoff = 23:59
        assertFalse(j.isExpired(at("2026-06-14", 23, 58)))
        assertTrue(j.isExpired(at("2026-06-14", 23, 59)))
    }

    @Test
    fun nearMidnightStart_graceOverflowsPastDay_staysOpen() {
        val j = job(startTime = "23:50") // cutoff = 24:20 (1460) — beyond max nowMinutes
        assertFalse(j.isExpired(at("2026-06-14", 23, 59)))
    }

    @Test
    fun statusAware_inFlightWork_suppressesExpiry() {
        val j = job(startTime = "10:00")
        val now = at("2026-06-14", 12, 0) // well past cutoff
        assertTrue(j.isExpired(now))
        val wip = Application(id = "a1", jobId = "j1", employeeId = "u1", status = ApplicationStatus.WORK_IN_PROGRESS)
        assertFalse(j.isExpired(now, listOf(wip)))
        val applied = Application(id = "a2", jobId = "j1", employeeId = "u1", status = ApplicationStatus.APPLIED)
        assertTrue(j.isExpired(now, listOf(applied)))
    }

    @Test
    fun effectiveStatus_overridesPendingOnExpiredJob_butNotTerminalOrInFlight() {
        val expiredJob = job(startTime = "10:00")
        val now = at("2026-06-14", 12, 0)

        val applied = Application(id = "a", jobId = "j1", employeeId = "u", status = ApplicationStatus.APPLIED, job = expiredJob)
        assertEquals(ApplicationStatus.EXPIRED, applied.effectiveStatus(now))

        // null clock → never override
        assertEquals(ApplicationStatus.APPLIED, applied.effectiveStatus(null))

        // terminal stays
        val completed = applied.copy(status = ApplicationStatus.COMPLETED)
        assertEquals(ApplicationStatus.COMPLETED, completed.effectiveStatus(now))

        // in-flight stays
        val wip = applied.copy(status = ApplicationStatus.WORK_IN_PROGRESS)
        assertEquals(ApplicationStatus.WORK_IN_PROGRESS, wip.effectiveStatus(now))

        // no job loaded → fall back to stored status
        val noJob = applied.copy(job = null)
        assertEquals(ApplicationStatus.APPLIED, noJob.effectiveStatus(now))
    }
}
