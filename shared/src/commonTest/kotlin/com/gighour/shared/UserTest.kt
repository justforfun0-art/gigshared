package com.gighour.shared

import com.gighour.shared.domain.model.UserType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class UserTest {
    @Test
    fun userType_fromString_mapsKnownValues() {
        assertEquals(UserType.EMPLOYEE, UserType.fromString("employee"))
        assertEquals(UserType.EMPLOYER, UserType.fromString("EMPLOYER"))
        assertNull(UserType.fromString("garbage"))
        assertNull(UserType.fromString(null))
    }

    @Test
    fun platformName_isNotBlank() {
        assert(platformName().isNotBlank())
    }
}
