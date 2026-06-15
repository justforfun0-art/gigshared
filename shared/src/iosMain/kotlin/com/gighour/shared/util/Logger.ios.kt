package com.gighour.shared.util

import platform.Foundation.NSLog

actual object Logger {
    actual fun d(tag: String, message: String) {
        NSLog("D/%@: %@", tag, message)
    }

    actual fun e(tag: String, message: String, throwable: Throwable?) {
        if (throwable != null) {
            NSLog("E/%@: %@ — %@", tag, message, throwable.toString())
        } else {
            NSLog("E/%@: %@", tag, message)
        }
    }
}
