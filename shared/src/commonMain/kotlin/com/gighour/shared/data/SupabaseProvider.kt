package com.gighour.shared.data

import com.gighour.shared.data.local.SecureTokenStore
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.serializer.KotlinXSerializer
import kotlinx.serialization.json.Json

/**
 * Builds the shared [SupabaseClient] from injected [BackendConfig] + a
 * [SecureTokenStore], with no dependency on Android BuildConfig or Hilt.
 *
 * Mirrors Gigand's SupabaseModule:
 *  - tolerant JSON (ignoreUnknownKeys / isLenient / coerceInputValues) so schema
 *    additions and legacy odd-shaped columns don't throw;
 *  - per-request user JWT via `accessToken = { tokenStore.getSupabaseToken() }`,
 *    so PostgREST resolves auth.uid() and applies RLS, falling back to anon when
 *    the token is null (not authenticated yet).
 *
 * Installs Postgrest + Realtime + Storage (Storage is needed by
 * ProfileRepository's photo upload). The supabase-kt `Auth` plugin is
 * intentionally NOT installed: it is mutually exclusive with the custom
 * `accessToken` callback (supabase-kt throws/ misbehaves if both are present),
 * and nothing here uses supabase-kt's own auth — PostgREST RLS is satisfied
 * entirely by the per-request token from [SecureTokenStore]. Gigand's
 * SupabaseModule likewise installs only Postgrest/Realtime/Storage.
 *
 * (Installing Auth was the cause of an iOS runtime crash:
 *  `-[Shared_kobjc… boolValue]: unrecognized selector` from the Auth plugin's
 *  session-manager init reading boxed Boolean config through the ObjC bridge.)
 */
object SupabaseProvider {

    val tolerantJson: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    fun create(config: BackendConfig, tokenStore: SecureTokenStore): SupabaseClient =
        createSupabaseClient(
            supabaseUrl = config.supabaseUrl,
            supabaseKey = config.supabaseAnonKey,
        ) {
            accessToken = { tokenStore.getSupabaseToken() }
            defaultSerializer = KotlinXSerializer(tolerantJson)
            install(Postgrest)
            install(Realtime)
            install(Storage)
        }
}
