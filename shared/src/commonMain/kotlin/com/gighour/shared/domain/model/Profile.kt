package com.gighour.shared.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class EmployeeProfile(
    @SerialName("profile_id") val profileId: String,
    @SerialName("user_id") val userId: String,
    val name: String,
    val dob: String,
    val gender: Gender,
    @SerialName("has_computer_knowledge") val hasComputerKnowledge: Boolean? = null,
    val state: String,
    val district: String,
    val email: String? = null,
    @SerialName("profile_photo_url") val profilePhotoUrl: String? = null,
    val bio: String? = null,
    val skills: List<String>? = null,
    @SerialName("languages_known") val languagesKnown: List<String>? = null,
    // Optional fields — not collected on signup (web parity) but kept for later profile edit
    @SerialName("work_preferences") val workPreferences: List<WorkPreference>? = null,
    @SerialName("preferred_working_hours") val preferredWorkingHours: String? = null,
    @SerialName("fitness_level") val fitnessLevel: String? = null,
    @SerialName("upi_id") val upiId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class EmployerProfile(
    @SerialName("profile_id") val profileId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("company_name") val companyName: String,
    val industry: String,
    @SerialName("company_size") val companySize: String? = null,
    val website: String? = null,
    val description: String? = null,
    val state: String? = null,
    val district: String? = null,
    val address: String? = null,
    @SerialName("profile_photo_url") val profilePhotoUrl: String? = null,
    @SerialName("gst_number") val gstNumber: String? = null,
    @SerialName("google_map_location") val googleMapLocation: String? = null,
    @SerialName("average_rating") val averageRating: Double? = null,
    @SerialName("total_reviews") val totalReviews: Int? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
enum class Gender {
    MALE,
    FEMALE,
    OTHER;

    companion object {
        fun fromString(value: String?): Gender {
            return when (value?.uppercase()) {
                "MALE" -> MALE
                "FEMALE" -> FEMALE
                "OTHER" -> OTHER
                else -> OTHER
            }
        }
    }

    fun toDisplayString(): String {
        return when (this) {
            MALE -> "Male"
            FEMALE -> "Female"
            OTHER -> "Other"
        }
    }
}

@Serializable
enum class WorkPreference {
    WEEKDAY,
    WEEKEND;

    companion object {
        fun fromString(value: String?): WorkPreference? {
            return when (value?.uppercase()) {
                "WEEKDAY" -> WEEKDAY
                "WEEKEND" -> WEEKEND
                else -> null
            }
        }
    }

    fun toDisplayString(): String {
        return when (this) {
            WEEKDAY -> "Weekday"
            WEEKEND -> "Weekend"
        }
    }
}
