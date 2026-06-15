package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.AccountType
import com.gighour.shared.domain.model.Beneficiary

interface BeneficiaryRepository {

    suspend fun listBeneficiaries(): Result<List<Beneficiary>>

    suspend fun addBeneficiary(
        accountHolderName: String,
        accountType: AccountType,
        accountNumber: String? = null,
        ifscCode: String? = null,
        bankName: String? = null,
        upiId: String? = null,
        phoneNumber: String? = null,
        isPrimary: Boolean = false
    ): Result<Beneficiary>

    suspend fun setPrimary(beneficiaryId: String): Result<Unit>

    suspend fun deleteBeneficiary(beneficiaryId: String): Result<Unit>
}
