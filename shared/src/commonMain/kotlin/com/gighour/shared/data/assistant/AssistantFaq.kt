package com.gighour.shared.data.assistant

/** Static FAQ + capability copy for the assistant (compact port of AssistantFaq). */
object AssistantFaq {

    fun capabilities(isEmployer: Boolean): String = if (isEmployer) {
        """Here's what I can help with:
• Your job posts & applicants
• Spending & payments
• Posting a new job
• How GigHour works
Just ask!"""
    } else {
        """Here's what I can help with:
• Your applications & active jobs
• Your earnings
• Finding jobs near you
• How to apply, OTP & payments
Just ask!"""
    }

    val howToApply = """To apply: open a job from the Jobs tab (or swipe right on the Home deck) and tap Apply. The employer reviews applicants and selects workers — you'll get a notification if you're picked."""

    val howPaymentWorks = """Payments: once your work is verified by the employer, your payment moves to "Payment Pending" and is processed to your account. You can track everything in the Earnings tab."""

    val otpHelp = """OTPs keep jobs secure. The employer generates a Start OTP — enter it to begin work. When you finish, you generate a completion code and read it to the employer to confirm and release payment."""

    val whatIsGigHour = """GigHour connects workers with short, part-time gigs near them. Find jobs, apply, work, and get paid — all in one app. Every hour matters!"""
}
