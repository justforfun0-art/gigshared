package com.gighour.shared.data.remote

import io.ktor.client.call.body
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit BeneficiariesApi. Routes under `payouts/...`
 * (note: NOT `secure/`). Gson @SerializedName → field names already match the
 * wire (camelCase), so no kotlinx annotations needed.
 */
class BeneficiariesApi(private val client: ApiClient) {

    suspend fun list(): BeneficiariesListResponse {
        val resp = client.http.get(client.urlFor("payouts/beneficiaries")) {
            client.applyAuth(this)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun create(request: CreateBeneficiaryRequest): CreateBeneficiaryResponse {
        val resp = client.http.post(client.urlFor("payouts/beneficiaries")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun update(id: String, request: UpdateBeneficiaryRequest): SimpleSuccessResponse {
        val resp = client.http.put(client.urlFor("payouts/beneficiaries/$id")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun delete(id: String): SimpleSuccessResponse {
        val resp = client.http.delete(client.urlFor("payouts/beneficiaries/$id")) {
            client.applyAuth(this)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class BeneficiaryDto(
    val id: String,
    val accountHolderName: String,
    val accountType: String,
    val accountNumber: String? = null,
    val ifscCode: String? = null,
    val bankName: String? = null,
    val upiId: String? = null,
    val phoneNumber: String? = null,
    val isPrimary: Boolean = false,
    val isVerified: Boolean = false,
    val createdAt: String? = null,
)

@Serializable
data class BeneficiariesListResponse(
    val success: Boolean? = null,
    val beneficiaries: List<BeneficiaryDto> = emptyList(),
    val error: String? = null,
)

@Serializable
data class CreateBeneficiaryRequest(
    val accountHolderName: String,
    val accountType: String,
    val accountNumber: String? = null,
    val ifscCode: String? = null,
    val bankName: String? = null,
    val upiId: String? = null,
    val phoneNumber: String? = null,
    val isPrimary: Boolean = false,
)

@Serializable
data class CreateBeneficiaryResponse(
    val success: Boolean? = null,
    val message: String? = null,
    val beneficiary: BeneficiaryDto? = null,
    val error: String? = null,
)

@Serializable
data class UpdateBeneficiaryRequest(
    val isPrimary: Boolean,
)

@Serializable
data class SimpleSuccessResponse(
    val success: Boolean? = null,
    val message: String? = null,
    val error: String? = null,
)
