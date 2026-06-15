package com.gighour.shared.data.repository

import com.gighour.shared.data.remote.BeneficiariesApi
import com.gighour.shared.data.remote.BeneficiaryDto
import com.gighour.shared.data.remote.CreateBeneficiaryRequest
import com.gighour.shared.data.remote.UpdateBeneficiaryRequest
import com.gighour.shared.domain.model.AccountType
import com.gighour.shared.domain.model.Beneficiary
import com.gighour.shared.domain.repository.BeneficiaryRepository

/**
 * KMP port of Gigand's BeneficiaryRepositoryImpl (Retrofit → Ktor).
 *
 * Transport difference: the Ktor [BeneficiariesApi] returns the decoded body
 * directly (ApiClient uses expectSuccess=false), so the old Retrofit
 * `Response.isSuccessful`/errorBody() handling is replaced by inspecting the
 * body's `success`/`error` fields — the same signal the server sends. The
 * trim/case normalization on create and the DTO→domain mapping are unchanged.
 */
class BeneficiaryRepositoryImpl(
    private val beneficiariesApi: BeneficiariesApi,
) : BeneficiaryRepository {

    override suspend fun listBeneficiaries(): Result<List<Beneficiary>> = runCatching {
        val body = beneficiariesApi.list()
        if (body.success == false) throw Exception(body.error ?: "Failed to load payment methods")
        body.beneficiaries.map { it.toDomain() }
    }

    override suspend fun addBeneficiary(
        accountHolderName: String,
        accountType: AccountType,
        accountNumber: String?,
        ifscCode: String?,
        bankName: String?,
        upiId: String?,
        phoneNumber: String?,
        isPrimary: Boolean,
    ): Result<Beneficiary> = runCatching {
        val body = beneficiariesApi.create(
            CreateBeneficiaryRequest(
                accountHolderName = accountHolderName.trim(),
                accountType = accountType.name,
                accountNumber = accountNumber?.trim()?.takeIf { it.isNotEmpty() },
                ifscCode = ifscCode?.trim()?.uppercase()?.takeIf { it.isNotEmpty() },
                bankName = bankName?.trim()?.takeIf { it.isNotEmpty() },
                upiId = upiId?.trim()?.lowercase()?.takeIf { it.isNotEmpty() },
                phoneNumber = phoneNumber?.trim()?.takeIf { it.isNotEmpty() },
                isPrimary = isPrimary,
            )
        )
        if (body.success == false && body.beneficiary == null) {
            throw Exception(body.error ?: "Failed to add payment method")
        }
        body.beneficiary?.toDomain()
            ?: throw Exception(body.error ?: "Failed to add payment method")
    }

    override suspend fun setPrimary(beneficiaryId: String): Result<Unit> = runCatching {
        val body = beneficiariesApi.update(beneficiaryId, UpdateBeneficiaryRequest(isPrimary = true))
        if (body.success == false) throw Exception(body.error ?: "Failed to update payment method")
    }

    override suspend fun deleteBeneficiary(beneficiaryId: String): Result<Unit> = runCatching {
        val body = beneficiariesApi.delete(beneficiaryId)
        if (body.success == false) throw Exception(body.error ?: "Failed to remove payment method")
    }

    private fun BeneficiaryDto.toDomain(): Beneficiary = Beneficiary(
        id = id,
        accountHolderName = accountHolderName,
        accountType = AccountType.fromString(accountType),
        accountNumber = accountNumber,
        ifscCode = ifscCode,
        bankName = bankName,
        upiId = upiId,
        phoneNumber = phoneNumber,
        isPrimary = isPrimary,
        isVerified = isVerified,
        createdAt = createdAt,
    )
}
