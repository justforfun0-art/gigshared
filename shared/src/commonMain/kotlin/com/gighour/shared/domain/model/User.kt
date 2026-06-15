package com.gighour.shared.domain.model

import kotlinx.serialization.Serializable

/**
 * Ported verbatim from the Gigand Android app's domain/model/User.kt — it was
 * already pure kotlinx.serialization (no Android/JVM deps), so it moves into
 * commonMain unchanged and compiles for Android + iOS.
 */
@Serializable
data class User(
    val id: String,
    val userId: String,
    val phone: String,
    val userType: UserType?,
    val isAdmin: Boolean = false,
    val isProfileCompleted: Boolean = false,
    val createdAt: String? = null
)

@Serializable
enum class UserType {
    EMPLOYEE,
    EMPLOYER,
    UNDEFINED;

    companion object {
        fun fromString(value: String?): UserType? {
            return when (value?.uppercase()) {
                "EMPLOYEE" -> EMPLOYEE
                "EMPLOYER" -> EMPLOYER
                "UNDEFINED" -> UNDEFINED
                else -> null
            }
        }
    }
}

@Serializable
data class AuthData(
    val userId: String,
    val phone: String,
    val userType: String?,
    val token: String,
    val isProfileComplete: Boolean = false
)
