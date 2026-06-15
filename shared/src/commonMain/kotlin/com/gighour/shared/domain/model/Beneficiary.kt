package com.gighour.shared.domain.model

data class Beneficiary(
    val id: String,
    val accountHolderName: String,
    val accountType: AccountType,
    val accountNumber: String? = null,
    val ifscCode: String? = null,
    val bankName: String? = null,
    val upiId: String? = null,
    val phoneNumber: String? = null,
    val isPrimary: Boolean = false,
    val isVerified: Boolean = false,
    val createdAt: String? = null
)

enum class AccountType {
    BANK,
    UPI,
    PHONE;

    companion object {
        fun fromString(value: String?): AccountType = when (value?.uppercase()) {
            "BANK" -> BANK
            "UPI" -> UPI
            "PHONE" -> PHONE
            else -> BANK
        }
    }
}
