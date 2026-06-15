package com.gighour.shared.domain.model

data class PaymentOrder(
    val orderId: String,
    val paymentSessionId: String,
    val paymentLink: String
)

data class PaymentVerifyResult(
    val success: Boolean,
    val orderStatus: String?,
    val paymentStatus: String?,
    val transactionId: String?
)
