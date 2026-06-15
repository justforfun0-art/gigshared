package com.gighour.shared.data.remote

import com.gighour.shared.data.BackendConfig
import com.gighour.shared.data.local.SecureTokenStore
import io.ktor.client.HttpClient
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

/**
 * Shared Ktor client for the Next.js secure API backend — the KMP replacement
 * for Gigand's Retrofit + OkHttp auth interceptor (NetworkModule).
 *
 * Ktor auto-selects the engine on the classpath (OkHttp on Android, Darwin on
 * iOS), so no engine is named here. Replicates the Android contract:
 *  - base URL = config.apiBaseUrl (already includes the trailing `/api/`);
 *  - `Authorization: Bearer <authToken>` + the cookie trio
 *    `auth_token / user_id / sb_access_token` when an app auth token exists;
 *  - `Content-Type: application/json`;
 *  - captures a rotated `sb_access_token` from any `Set-Cookie` response and
 *    writes it back to the token store (the on-demand sb-token refresh path).
 *
 * NOTE not yet ported: cert pinning (BuildConfig.CERT_PINS), HTTP logging, and
 * timeouts (Retrofit used 15s/15s/30s) — all per-platform engine concerns; add
 * when hardening for release.
 */
class ApiClient(
    private val config: BackendConfig,
    private val tokenStore: SecureTokenStore,
    json: Json = DEFAULT_JSON,
) {
    val http: HttpClient = HttpClient {
        expectSuccess = false // mirror Retrofit: inspect body.success, don't throw on non-2xx
        install(ContentNegotiation) { json(json) }
        defaultRequest {
            contentType(ContentType.Application.Json)
        }
    }

    /** Absolute URL for a `secure/...`-style relative path. */
    fun urlFor(path: String): String = config.apiBaseUrl.trimEnd('/') + "/" + path.trimStart('/')

    /**
     * Apply the auth headers Gigand's interceptor adds, onto [builder]. Reads
     * the app auth token; if present, adds Bearer + the cookie trio. No token →
     * request goes out unauthenticated (server returns 401), matching the
     * interceptor's behaviour.
     */
    suspend fun applyAuth(builder: HttpRequestBuilder) {
        val token = tokenStore.getAuthToken() ?: return
        builder.headers.append(HttpHeaders.Authorization, "Bearer $token")
        val userId = tokenStore.getUserId()
        val sbToken = tokenStore.getSupabaseToken()
        val cookieParts = mutableListOf("auth_token=$token")
        if (!userId.isNullOrBlank()) cookieParts += "user_id=$userId"
        if (!sbToken.isNullOrBlank()) cookieParts += "sb_access_token=$sbToken"
        builder.headers.append(HttpHeaders.Cookie, cookieParts.joinToString("; "))
    }

    /**
     * Capture a server-minted `sb_access_token` from Set-Cookie and persist it,
     * mirroring the interceptor's response hook so later Supabase queries
     * resolve auth.uid().
     */
    suspend fun captureRotatedSbToken(response: HttpResponse) {
        val current = tokenStore.getSupabaseToken()
        response.headers.getAll(HttpHeaders.SetCookie)?.forEach { header ->
            val sbCookie = header.split(";")
                .map { it.trim() }
                .firstOrNull { it.startsWith("sb_access_token=") }
                ?.removePrefix("sb_access_token=")
            if (!sbCookie.isNullOrBlank() && sbCookie != current) {
                tokenStore.setSupabaseToken(sbCookie)
            }
        }
    }

    companion object {
        val DEFAULT_JSON: Json = Json {
            ignoreUnknownKeys = true
            isLenient = true
            coerceInputValues = true
            encodeDefaults = true
        }
    }
}
