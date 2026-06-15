package com.gighour.shared

/**
 * Minimal expect/actual to verify the android + ios source sets are wired.
 * The real platform-specific pieces (secure storage, etc.) will follow this
 * same expect/actual pattern.
 */
expect fun platformName(): String
