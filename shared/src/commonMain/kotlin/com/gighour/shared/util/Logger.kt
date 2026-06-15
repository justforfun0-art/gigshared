package com.gighour.shared.util

/**
 * Minimal multiplatform logger. Replaces android.util.Log in shared code.
 * Android actual → android.util.Log; iOS actual → NSLog/println.
 */
expect object Logger {
    fun d(tag: String, message: String)
    fun e(tag: String, message: String, throwable: Throwable? = null)
}
