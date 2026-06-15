package com.gighour.shared.domain.repository

import com.gighour.shared.domain.model.EmployeeProfile
import com.gighour.shared.domain.model.EmployerProfile
import kotlinx.coroutines.flow.Flow

interface ProfileRepository {
    // Employee Profile
    suspend fun getEmployeeProfile(userId: String): Result<EmployeeProfile?>
    suspend fun createEmployeeProfile(profile: EmployeeProfile): Result<EmployeeProfile>
    suspend fun updateEmployeeProfile(profile: EmployeeProfile): Result<EmployeeProfile>
    fun observeEmployeeProfile(userId: String): Flow<EmployeeProfile?>

    // Employer Profile
    suspend fun getEmployerProfile(userId: String): Result<EmployerProfile?>
    suspend fun createEmployerProfile(profile: EmployerProfile): Result<EmployerProfile>
    suspend fun updateEmployerProfile(profile: EmployerProfile): Result<EmployerProfile>
    fun observeEmployerProfile(userId: String): Flow<EmployerProfile?>

    // Profile photo
    suspend fun uploadProfilePhoto(userId: String, photoBytes: ByteArray): Result<String>
}
