package com.gighour.shared.data.remote

import com.gighour.shared.domain.model.Application
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.isSuccess
import kotlinx.serialization.Serializable

/**
 * Ktor port of Gigand's Retrofit ApplicationsApi. Routes under
 * `secure/applications` + `secure/work-sessions`. updateApplicationStatus and
 * workSessionAction return [HttpResult] so the repo can pull the server's
 * human-readable error off the body even on a non-2xx (e.g. 409 "Position
 * already filled") — the role Retrofit's errorBody() played.
 */
class ApplicationsApi(private val client: ApiClient) {

    suspend fun applyForJob(request: ApplyRequest): ApplicationResponse {
        val resp = client.http.post(client.urlFor("secure/applications")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun getApplications(
        employeeId: String? = null,
        employerId: String? = null,
        jobId: String? = null,
        status: String? = null,
    ): ApplicationsResponse {
        val resp = client.http.get(client.urlFor("secure/applications")) {
            client.applyAuth(this)
            employeeId?.let { parameter("employeeId", it) }
            employerId?.let { parameter("employerId", it) }
            jobId?.let { parameter("jobId", it) }
            status?.let { parameter("status", it) }
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun getApplicationById(applicationId: String): ApplicationResponse {
        val resp = client.http.get(client.urlFor("secure/applications/$applicationId")) {
            client.applyAuth(this)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun updateApplicationStatus(request: UpdateStatusRequest): HttpResult<UpdateStatusResponse> {
        val resp = client.http.patch(client.urlFor("secure/applications")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }

    suspend fun workSessionAction(request: WorkSessionRequest): HttpResult<WorkSessionResponse> {
        val resp = client.http.post(client.urlFor("secure/work-sessions")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return HttpResult(resp.status.value, resp.status.isSuccess(), resp.body())
    }
}

@Serializable
data class ApplyRequest(
    val jobId: String,
    val employeeId: String,
)

@Serializable
data class ApplicationsResponse(
    val success: Boolean = false,
    val applications: List<Application> = emptyList(),
    val error: String? = null,
)

@Serializable
data class ApplicationResponse(
    val success: Boolean = false,
    val application: Application? = null,
    val error: String? = null,
)

@Serializable
data class UpdateStatusRequest(
    val applicationId: String,
    val status: String,
    val reason: String? = null,
    val termsConfirmed: Boolean? = null,
)

@Serializable
data class UpdateStatusResponse(
    val success: Boolean = false,
    val data: Application? = null,
    val error: String? = null,
)

@Serializable
data class WorkSessionRequest(
    val action: String,
    val applicationId: String,
    val jobId: String? = null,
    val otp: String? = null,
)

@Serializable
data class WorkSessionResponse(
    val success: Boolean = false,
    val data: WorkSessionData? = null,
    val completionOtp: String? = null,
    val elapsedSeconds: Int? = null,
    val totalWages: Double? = null,
    val error: String? = null,
)

@Serializable
data class WorkSessionData(
    val otp: String? = null,
    val completionOtp: String? = null,
)
