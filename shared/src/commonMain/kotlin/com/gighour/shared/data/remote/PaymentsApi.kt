package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.isSuccess
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit PaymentsApi. Routes `payments/create-order`,
 * `payments/verify`. Both return [HttpResult] (status+body) because the repo
 * branches on HTTP success for error messages — and because payment must not
 * misread a non-2xx body as success.
 */
open class PaymentsApi(private val client: ApiClient) {

    open suspend fun createOrder(request: CreateOrderRequest): HttpResult<CreateOrderResponse> {
        val resp = client.http.post(client.urlFor("payments/create-order")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }

    open suspend fun verifyOrder(orderId: String): HttpResult<VerifyOrderResponse> {
        val resp = client.http.get(client.urlFor("payments/verify")) {
            client.applyAuth(this)
            parameter("order_id", orderId)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }
}

@Serializable
data class CreateOrderRequest(
    @SerialName("orderId") val orderId: String,
    @SerialName("orderAmount") val orderAmount: Double,
    @SerialName("customerName") val customerName: String,
    @SerialName("customerEmail") val customerEmail: String,
    @SerialName("customerPhone") val customerPhone: String,
    @SerialName("applicationId") val applicationId: String,
    @SerialName("employerId") val employerId: String,
    @SerialName("employeeId") val employeeId: String,
)

@Serializable
data class CreateOrderResponse(
    val success: Boolean? = null,
    val cfOrderId: String? = null,
    val orderId: String? = null,
    val orderStatus: String? = null,
    val paymentSessionId: String? = null,
    val paymentLink: String? = null,
    val error: String? = null,
)

@Serializable
data class VerifyOrderResponse(
    val success: Boolean? = null,
    val orderId: String? = null,
    val orderAmount: Double? = null,
    val orderStatus: String? = null,
    val paymentStatus: String? = null,
    val paymentMethod: String? = null,
    val paymentTime: String? = null,
    val cfPaymentId: String? = null,
    val error: String? = null,
)
