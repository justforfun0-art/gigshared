package com.gighour.shared.domain.model

/**
 * The action surfaced on a dashboard action card for a given [ApplicationStatus].
 *
 * Centralizes the status -> (label, action) mapping that used to be duplicated
 * inline across the Compose action cards. Mirrors the web app's
 * `getEmployeeActionConfig` / `getEmployerActionConfig` in
 * `src/lib/application-status.ts` so the two platforms agree on what the worker
 * and employer can do at each stage.
 *
 * The label is a [ActionLabel] key, not a literal string — the UI layer resolves
 * it to a localized string resource. This keeps the helper framework-free and
 * unit-testable (assert on the key, not on English text) while ensuring Hindi
 * users see translated action-card buttons. Colors also stay in the UI.
 */
sealed interface ApplicationAction {
    /** A tappable button. [action] is the string passed to the card's onAction. */
    data class Button(val label: ActionLabel, val action: String) : ApplicationAction

    /** A passive "you're waiting on the other party" chip — no tap target. */
    data class Waiting(val label: ActionLabel) : ApplicationAction
}

/**
 * Stable, locale-independent identifiers for action-card labels. The UI maps
 * each to a string resource; tests assert against these instead of English.
 */
enum class ActionLabel {
    VIEW,
    REVIEW,
    ACCEPT_JOB,
    ENTER_OTP,
    GENERATE_OTP,
    SHOW_OTP,
    COMPLETE_WORK,
    SHOW_CODE,
    VERIFY_CODE,
    PAY_NOW,
    WAITING_FOR_OTP,
    PAYMENT_PENDING,
    WORK_IN_PROGRESS,
}

/**
 * What the *employee* can do at this status. Falls back to a generic "View"
 * button for statuses without a dedicated action (mirrors the UI's `else`).
 */
fun ApplicationStatus.employeeAction(): ApplicationAction = when (this) {
    ApplicationStatus.SELECTED -> ApplicationAction.Button(ActionLabel.ACCEPT_JOB, "accept")
    ApplicationStatus.ACCEPTED -> ApplicationAction.Waiting(ActionLabel.WAITING_FOR_OTP)
    ApplicationStatus.OTP_REQUESTED -> ApplicationAction.Button(ActionLabel.ENTER_OTP, "enter_otp")
    ApplicationStatus.WORK_IN_PROGRESS -> ApplicationAction.Button(ActionLabel.COMPLETE_WORK, "complete")
    ApplicationStatus.COMPLETION_PENDING -> ApplicationAction.Button(ActionLabel.SHOW_CODE, "show_code")
    ApplicationStatus.PAYMENT_PENDING -> ApplicationAction.Waiting(ActionLabel.PAYMENT_PENDING)
    else -> ApplicationAction.Button(ActionLabel.VIEW, "view")
}

/**
 * What the *employer* can do at this status. Falls back to a "Review" button
 * for statuses without a dedicated action (mirrors the UI's `else`).
 */
fun ApplicationStatus.employerAction(): ApplicationAction = when (this) {
    ApplicationStatus.APPLIED -> ApplicationAction.Button(ActionLabel.REVIEW, "review")
    ApplicationStatus.SELECTED -> ApplicationAction.Button(ActionLabel.VIEW, "view")
    ApplicationStatus.ACCEPTED -> ApplicationAction.Button(ActionLabel.GENERATE_OTP, "generate_otp")
    ApplicationStatus.OTP_REQUESTED -> ApplicationAction.Button(ActionLabel.SHOW_OTP, "show_otp")
    ApplicationStatus.WORK_IN_PROGRESS -> ApplicationAction.Waiting(ActionLabel.WORK_IN_PROGRESS)
    ApplicationStatus.COMPLETION_PENDING -> ApplicationAction.Button(ActionLabel.VERIFY_CODE, "verify_code")
    ApplicationStatus.PAYMENT_PENDING -> ApplicationAction.Button(ActionLabel.PAY_NOW, "pay")
    else -> ApplicationAction.Button(ActionLabel.REVIEW, "review")
}

/**
 * Resolve the action for the given role. [isEmployer] selects the employer
 * mapping, otherwise the employee mapping.
 */
fun ApplicationStatus.actionFor(isEmployer: Boolean): ApplicationAction =
    if (isEmployer) employerAction() else employeeAction()
