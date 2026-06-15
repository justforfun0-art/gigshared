package com.gighour.shared.util

/**
 * iOS logger — uses Kotlin's [println] (→ stdout), NOT NSLog.
 *
 * NSLog is a C variadic function. Bridging it from Kotlin/Native and passing a
 * Kotlin/ObjC string through its `...` args is unsafe on this toolchain: the
 * varargs runtime tries to read the object as a format argument and crashes in
 * `_NSDescriptionWithStringProxyFunc` / `objc_opt_respondsToSelector`
 * (EXC_BAD_ACCESS) — this fired whenever any repository logged (e.g.
 * JobRepository.getJobs on the Jobs tab). Even `NSLog("%@", str)` is affected
 * because the crash is in the vararg bridge itself, not the format string.
 *
 * [println] needs no varargs and maps cleanly to stdout, which Xcode's console
 * captures, so it's the safe choice for a debug logger.
 */
actual object Logger {
    actual fun d(tag: String, message: String) {
        println("D/$tag: $message")
    }

    actual fun e(tag: String, message: String, throwable: Throwable?) {
        if (throwable != null) {
            println("E/$tag: $message — $throwable")
        } else {
            println("E/$tag: $message")
        }
    }
}
