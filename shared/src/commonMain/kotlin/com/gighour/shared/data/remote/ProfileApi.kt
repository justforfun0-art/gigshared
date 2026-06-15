package com.gighour.shared.data.remote

import com.gighour.shared.domain.model.EmployeeProfile
import com.gighour.shared.domain.model.EmployerProfile
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.isSuccess
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit ProfileApi. Routes under `secure/profiles`.
 * Gson `@SerializedName` → kotlinx `@SerialName` (incl. `data` for the profile
 * payload and the snake_case request fields). getProfileLegacy returns
 * [HttpResult] so the repo can replicate the 404 / PGRST116 "no rows" handling.
 */
class ProfileApi(private val client: ApiClient) {

    suspend fun getProfileLegacy(userId: String): HttpResult<LegacyProfileResponse> {
        val resp = client.http.get(client.urlFor("secure/profiles")) {
            client.applyAuth(this)
            parameter("userId", userId)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }

    suspend fun createEmployeeProfile(request: EmployeeProfileRequest): EmployeeProfileApiResponse {
        val resp = client.http.post(client.urlFor("secure/profiles")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun createEmployerProfile(request: EmployerProfileRequest): EmployerProfileApiResponse {
        val resp = client.http.post(client.urlFor("secure/profiles")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun updateEmployeeProfile(request: EmployeeProfileRequest): EmployeeProfileApiResponse {
        val resp = client.http.patch(client.urlFor("secure/profiles")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun updateEmployerProfile(request: EmployerProfileRequest): EmployerProfileApiResponse {
        val resp = client.http.patch(client.urlFor("secure/profiles")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class LegacyProfileResponse(
    val success: Boolean = false,
    val employeeProfile: EmployeeProfile? = null,
    val employerProfile: EmployerProfile? = null,
    val error: String? = null,
)

@Serializable
data class EmployeeProfileApiResponse(
    val success: Boolean = false,
    @SerialName("data") val profile: EmployeeProfile? = null,
    val error: String? = null,
)

@Serializable
data class EmployerProfileApiResponse(
    val success: Boolean = false,
    @SerialName("data") val profile: EmployerProfile? = null,
    val error: String? = null,
)

@Serializable
data class ProfileTypeRequest(
    @SerialName("profileType") val profileType: String,
)

@Serializable
data class EmployeeProfileRequest(
    @SerialName("profileType") val profileType: String = "employee",
    val name: String? = null,
    val dob: String? = null,
    val gender: String? = null,
    @SerialName("has_computer_knowledge") val hasComputerKnowledge: Boolean? = null,
    val state: String? = null,
    val district: String? = null,
    val email: String? = null,
    @SerialName("profile_photo_url") val profilePhotoUrl: String? = null,
    val bio: String? = null,
    val skills: List<String>? = null,
    @SerialName("languages_known") val languagesKnown: List<String>? = null,
    @SerialName("work_preferences") val workPreferences: List<String>? = null,
    @SerialName("preferred_working_hours") val preferredWorkingHours: String? = null,
    @SerialName("fitness_level") val fitnessLevel: String? = null,
    @SerialName("upi_id") val upiId: String? = null,
)

@Serializable
data class EmployerProfileRequest(
    @SerialName("profileType") val profileType: String = "employer",
    @SerialName("company_name") val companyName: String? = null,
    val industry: String? = null,
    @SerialName("company_size") val companySize: String? = null,
    val website: String? = null,
    val description: String? = null,
    val state: String? = null,
    val district: String? = null,
    val address: String? = null,
    @SerialName("profile_photo_url") val profilePhotoUrl: String? = null,
    @SerialName("gst_number") val gstNumber: String? = null,
    @SerialName("google_map_location") val googleMapLocation: String? = null,
)
