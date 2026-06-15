package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.PayoutPage
import com.gighour.shared.domain.model.PayoutStatus

interface PayoutRepository {

    suspend fun getHistory(
        status: PayoutStatus? = null,
        limit: Int = 50,
        offset: Int = 0
    ): Result<PayoutPage>
}
