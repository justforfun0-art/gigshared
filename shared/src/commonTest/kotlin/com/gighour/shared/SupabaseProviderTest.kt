package com.gighour.shared

import com.gighour.shared.data.SupabaseProvider
import com.gighour.shared.domain.model.User
import kotlin.test.Test
import kotlin.test.assertEquals

class SupabaseProviderTest {

    /**
     * The tolerant decoder is the contract every repo decode relies on: it must
     * ignore unknown columns (schema additions) rather than throw — the bug
     * class that silently disabled features in prod (project_ranking_decode_bug).
     */
    @Test
    fun tolerantJson_ignoresUnknownColumns() {
        val json = """
            {"id":"row1","userId":"u1","phone":"+910000000000","userType":"EMPLOYEE",
             "isProfileCompleted":true,"some_future_column":42,"another":"x"}
        """.trimIndent()
        val user = SupabaseProvider.tolerantJson.decodeFromString<User>(json)
        assertEquals("u1", user.userId)
        assertEquals("+910000000000", user.phone)
    }
}
