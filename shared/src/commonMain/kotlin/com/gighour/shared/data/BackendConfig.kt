package com.gighour.shared.data

/**
 * Backend connection config, injected at construction so the shared module
 * doesn't depend on Android BuildConfig (or any platform's build system).
 *
 * - [supabaseUrl] / [supabaseAnonKey]: the public Supabase project URL + anon
 *   key, same values Gigand reads from BuildConfig today.
 * - [apiBaseUrl]: base URL of the Next.js backend (the secure API routes under
 *   `/api/secure`), used by the Ktor ApiClient in later phases. Include the
 *   trailing path up to but not including `secure` (e.g.
 *   "https://app.example.com/api/").
 *
 * Each platform fills this from its own source: Android from BuildConfig,
 * iOS from Info.plist / xcconfig.
 */
data class BackendConfig(
    val supabaseUrl: String,
    val supabaseAnonKey: String,
    val apiBaseUrl: String,
)
