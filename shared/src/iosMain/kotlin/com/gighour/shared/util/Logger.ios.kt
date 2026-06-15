package com.gighour.shared.util

import platform.Foundation.NSLog

/**
 * iOS logger. The message is built in Kotlin and passed as the *single* argument
 * to a constant `"%@"` format — never as the format string itself. Passing a
 * dynamic string as (part of) the NSLog format and substituting it with `%@`
 * is a crash hazard: if the substituted text contains a `%` (URL-encoded data,
 * "%s", a literal percent, etc.) the logging subsystem can re-parse it as a
 * format specifier and dereference a non-existent vararg → EXC_BAD_ACCESS.
 * Kotlin/Native's vararg→NSLog bridging makes this especially fragile, so we
 * keep the format constant and put everything in one already-built argument.
 */
actual object Logger {
    actual fun d(tag: String, message: String) {
        NSLog("%@", "D/$tag: $message")
    }

    actual fun e(tag: String, message: String, throwable: Throwable?) {
        val line = if (throwable != null) "E/$tag: $message — $throwable" else "E/$tag: $message"
        NSLog("%@", line)
    }
}
