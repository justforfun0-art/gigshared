package com.gighour.shared.data.assistant

/**
 * Keyword intent matcher (focused port of Gigand's IntentMatcher). Order
 * matters — more specific intents are checked before broad ones; anything
 * unmatched is UNKNOWN and routed to the Gemini fallback.
 */
enum class AssistantIntent {
    GREETING, THANKS,
    APPLICATIONS, ACTIVE_JOBS, WHY_REJECTED, EARNINGS, FIND_JOBS,
    HELP_APPLY, HELP_PAYMENT, HELP_OTP, WHAT_IS,
    UNKNOWN;

    companion object {
        fun match(message: String, isEmployer: Boolean): AssistantIntent {
            val t = message.trim().lowercase()
            if (t.isEmpty()) return UNKNOWN

            if (t.anyOf("hi", "hello", "hey", "namaste", "good morning", "good evening")) return GREETING
            if (t.anyOf("thanks", "thank you", "thx", "shukriya")) return THANKS

            if (t.anyOf("why", "rejected", "not selected") && t.contains("reject")) return WHY_REJECTED
            if (t.anyOf("my application", "applications", "applied", "my applies")) return APPLICATIONS
            if (t.anyOf("active job", "ongoing", "in progress", "current job", "my active")) return ACTIVE_JOBS
            if (t.anyOf("earning", "earned", "income", "how much", "salary", "money", "paid")) return EARNINGS
            if (t.anyOf("find job", "jobs near", "nearby job", "jobs in", "show jobs", "available jobs")) return FIND_JOBS

            if (t.anyOf("how to apply", "how do i apply", "apply for")) return HELP_APPLY
            if (t.anyOf("payment work", "how payment", "when paid", "get paid", "withdraw")) return HELP_PAYMENT
            if (t.anyOf("otp", "code", "verify")) return HELP_OTP
            if (t.anyOf("what is gighour", "about gighour", "what is this app")) return WHAT_IS

            return UNKNOWN
        }

        private fun String.anyOf(vararg keys: String): Boolean = keys.any { this.contains(it) }
    }
}
