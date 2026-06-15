package com.gighour.shared

import com.gighour.shared.domain.model.AccountType
import com.gighour.shared.domain.model.ActionLabel
import com.gighour.shared.domain.model.ApplicationAction
import com.gighour.shared.domain.model.ApplicationStatus
import com.gighour.shared.domain.model.PayoutStatus
import com.gighour.shared.domain.model.actionFor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DomainModelTest {

    @Test
    fun applicationStatus_fromString_isCaseInsensitive_andFallsBackToApplied() {
        assertEquals(ApplicationStatus.WORK_IN_PROGRESS, ApplicationStatus.fromString("work_in_progress"))
        assertEquals(ApplicationStatus.COMPLETED, ApplicationStatus.fromString("COMPLETED"))
        assertEquals(ApplicationStatus.APPLIED, ApplicationStatus.fromString("garbage"))
        assertEquals(ApplicationStatus.APPLIED, ApplicationStatus.fromString(null))
    }

    @Test
    fun applicationStatus_active_terminal_partition() {
        assertTrue(ApplicationStatus.WORK_IN_PROGRESS.isActive())
        assertFalse(ApplicationStatus.WORK_IN_PROGRESS.isTerminal())
        assertTrue(ApplicationStatus.COMPLETED.isTerminal())
        assertFalse(ApplicationStatus.COMPLETED.isActive())
    }

    @Test
    fun actionFor_employee_vs_employer() {
        val empWip = ApplicationStatus.WORK_IN_PROGRESS.actionFor(isEmployer = false)
        assertEquals(ApplicationAction.Button(ActionLabel.COMPLETE_WORK, "complete"), empWip)

        val employerWip = ApplicationStatus.WORK_IN_PROGRESS.actionFor(isEmployer = true)
        assertEquals(ApplicationAction.Waiting(ActionLabel.WORK_IN_PROGRESS), employerWip)

        // Unmapped status falls back per role.
        assertEquals(
            ApplicationAction.Button(ActionLabel.VIEW, "view"),
            ApplicationStatus.EXPIRED.actionFor(isEmployer = false)
        )
        assertEquals(
            ApplicationAction.Button(ActionLabel.REVIEW, "review"),
            ApplicationStatus.EXPIRED.actionFor(isEmployer = true)
        )
    }

    @Test
    fun enums_fromString_fallbacks() {
        assertEquals(AccountType.BANK, AccountType.fromString("unknown"))
        assertEquals(AccountType.UPI, AccountType.fromString("upi"))
        assertEquals(PayoutStatus.UNKNOWN, PayoutStatus.fromString("weird"))
        assertEquals(PayoutStatus.SUCCESS, PayoutStatus.fromString("success"))
    }
}
