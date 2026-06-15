package com.gighour.shared.data

/**
 * Fire-and-forget hook invoked after an application status transition, used by
 * Gigand to mint a WhatsApp action-token notification
 * (WhatsAppNotificationService). The actual delivery is platform glue (network
 * call + per-platform notification plumbing), so the shared repo only depends on
 * this interface; platforms wire the real implementation.
 *
 * Must never throw to the caller — failures are swallowed (the repo already
 * launches this on a SupervisorJob so one failure can't cancel future
 * notifications), matching Gigand's notifyStatusChange contract.
 */
interface StatusChangeNotifier {
    suspend fun notifyStatusChange(applicationId: String, status: String)
}

/** Default no-op (iOS-first cut / tests). Wire a real notifier per platform. */
object NoopStatusChangeNotifier : StatusChangeNotifier {
    override suspend fun notifyStatusChange(applicationId: String, status: String) {}
}
