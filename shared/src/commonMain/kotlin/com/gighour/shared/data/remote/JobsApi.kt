package com.gighour.shared.data.remote

import com.gighour.shared.domain.model.Job
import io.ktor.client.call.body
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.request.patch
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNames

/**
 * Ktor port of Gigand's Retrofit `JobsApi`. Same routes, query params, body
 * shapes, and response types — only the transport changed (Retrofit → Ktor) and
 * the JSON annotations (Gson @SerializedName → kotlinx @SerialName/@JsonNames).
 *
 * Routes (relative to config.apiBaseUrl, which ends in `/api/`):
 *   GET    secure/jobs
 *   GET    secure/jobs/{id}
 *   GET    secure/jobs/employer?employerId=
 *   POST   secure/jobs                       (CreateJobRequest)
 *   PATCH  secure/jobs                       (UpdateJobRequest — jobId in body)
 *   DELETE secure/jobs?jobId=
 *   PUT    secure/jobs/{id}/toggle-active     (ToggleActiveRequest)
 */
class JobsApi(private val client: ApiClient) {

    suspend fun getJobs(
        page: Int = 1,
        limit: Int = 20,
        state: String? = null,
        district: String? = null,
        jobType: String? = null,
        search: String? = null,
        minSalary: Int? = null,
        maxSalary: Int? = null,
    ): JobsResponse {
        val resp = client.http.get(client.urlFor("secure/jobs")) {
            client.applyAuth(this)
            parameter("page", page)
            parameter("limit", limit)
            state?.let { parameter("state", it) }
            district?.let { parameter("district", it) }
            jobType?.let { parameter("jobType", it) }
            search?.let { parameter("search", it) }
            minSalary?.let { parameter("minSalary", it) }
            maxSalary?.let { parameter("maxSalary", it) }
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun getJobById(jobId: String): JobResponse {
        val resp = client.http.get(client.urlFor("secure/jobs/$jobId")) {
            client.applyAuth(this)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun getEmployerJobs(employerId: String): JobsResponse {
        val resp = client.http.get(client.urlFor("secure/jobs/employer")) {
            client.applyAuth(this)
            parameter("employerId", employerId)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun createJob(request: CreateJobRequest): JobResponse {
        val resp = client.http.post(client.urlFor("secure/jobs")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun updateJob(request: UpdateJobRequest): JobResponse {
        val resp = client.http.patch(client.urlFor("secure/jobs")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun deleteJob(jobId: String): DeleteJobResponse {
        val resp = client.http.delete(client.urlFor("secure/jobs")) {
            client.applyAuth(this)
            parameter("jobId", jobId)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }

    suspend fun toggleJobActive(jobId: String, request: ToggleActiveRequest): JobResponse {
        val resp = client.http.put(client.urlFor("secure/jobs/$jobId/toggle-active")) {
            client.applyAuth(this)
            setBody(request)
        }
        client.captureRotatedSbToken(resp)
        return resp.body()
    }
}

@Serializable
data class JobsResponse(
    val success: Boolean = false,
    val jobs: List<Job> = emptyList(),
    val total: Int = 0,
    val page: Int = 1,
    val error: String? = null,
)

@Serializable
data class JobResponse(
    val success: Boolean = false,
    // Server returns the job under either "data" or "job" (Gson alternate).
    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @JsonNames("data", "job")
    val job: Job? = null,
    val error: String? = null,
)

@Serializable
data class CreateJobRequest(
    val title: String,
    val description: String,
    val location: String,
    val salaryRange: String? = null,
    val jobType: String,
    val requirements: List<String> = emptyList(),
    val applicationDeadline: String? = null,
    val tags: List<String> = emptyList(),
    val jobCategory: String? = null,
    val preferredSkills: List<String> = emptyList(),
    val skillsRequired: List<String> = emptyList(),
    val workDuration: String? = null,
    val district: String? = null,
    val state: String? = null,
    val jobDate: String? = null,
    val startTime: String? = null,
    val endTime: String? = null,
    val breakDuration: Int? = null,
    val workAddress: String? = null,
    val workGoogleMapLocation: String? = null,
    val genderPreference: String? = null,
    val languagePreference: List<String> = emptyList(),
    val numPositions: Int = 1,
)

@Serializable
data class UpdateJobRequest(
    val jobId: String,
    val title: String? = null,
    val description: String? = null,
    val location: String? = null,
    val salaryRange: String? = null,
    val jobType: String? = null,
    val requirements: List<String>? = null,
    val applicationDeadline: String? = null,
    val tags: List<String>? = null,
    val jobCategory: String? = null,
    val preferredSkills: List<String>? = null,
    val skillsRequired: List<String>? = null,
    val workDuration: String? = null,
    val district: String? = null,
    val state: String? = null,
    val jobDate: String? = null,
    val startTime: String? = null,
    val endTime: String? = null,
    val breakDuration: Int? = null,
    val workAddress: String? = null,
    val workGoogleMapLocation: String? = null,
    val genderPreference: String? = null,
    val languagePreference: List<String>? = null,
    val numPositions: Int? = null,
    val isActive: Boolean? = null,
)

@Serializable
data class ToggleActiveRequest(
    val isActive: Boolean,
)

@Serializable
data class DeleteJobResponse(
    val success: Boolean = false,
    val error: String? = null,
)
