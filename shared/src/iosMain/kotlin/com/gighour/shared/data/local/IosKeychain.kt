package com.gighour.shared.data.local

import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.CValuesRef
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.value
import platform.CoreFoundation.CFDictionaryRef
import platform.CoreFoundation.CFRetain
import platform.CoreFoundation.CFStringRef
import platform.CoreFoundation.CFTypeRefVar
import platform.Foundation.CFBridgingRelease
import platform.Foundation.CFBridgingRetain
import platform.Foundation.NSData
import platform.Foundation.NSMutableDictionary
import platform.Foundation.NSNumber
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.create
import platform.Foundation.dataUsingEncoding
import platform.Security.SecItemAdd
import platform.Security.SecItemCopyMatching
import platform.Security.SecItemDelete
import platform.Security.kSecAttrAccount
import platform.Security.kSecAttrService
import platform.Security.kSecClass
import platform.Security.kSecClassGenericPassword
import platform.Security.kSecMatchLimit
import platform.Security.kSecMatchLimitOne
import platform.Security.kSecReturnData
import platform.Security.kSecValueData
import platform.darwin.OSStatus
import platform.darwin.noErr

/**
 * Thin Keychain wrapper (kSecClassGenericPassword) shared by the iOS secure
 * stores. Items are scoped by [service]; each value lives under an account key.
 *
 * NOTE: Security-framework cinterop, NOT compiled against the Apple toolchain in
 * this environment — needs an on-device / linkDebugFramework pass before ship.
 * Follows the standard NSMutableDictionary + SecItem* pattern K/N supports.
 */
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
internal class IosKeychain(private val service: String) {

    // The kSec* constants are CFStringRef GLOBALS we do NOT own. Toll-free-bridge
    // them to NSString WITHOUT a net ownership change: CFBridgingRelease consumes
    // a +1 reference, so calling it directly on an unowned constant over-releases
    // it — and key() runs several times per query, so the global kSec* string is
    // eventually deallocated and every later Keychain op reads freed memory
    // (silent save/read failures → the app always falls back to the login
    // screen). CFRetain first so the CFBridgingRelease balances to net-zero.
    private fun key(cf: CFStringRef?): NSString =
        CFBridgingRelease(CFRetain(cf)) as NSString

    private fun baseQuery(account: String): NSMutableDictionary {
        val q = NSMutableDictionary()
        q.setObject(kSecClassGenericPassword!!, forKey = key(kSecClass))
        q.setObject(service as NSString, forKey = key(kSecAttrService))
        q.setObject(account as NSString, forKey = key(kSecAttrAccount))
        return q
    }

    fun write(account: String, value: String) {
        delete(account)
        val data = (value as NSString).dataUsingEncoding(NSUTF8StringEncoding) ?: return
        val q = baseQuery(account)
        q.setObject(data, forKey = key(kSecValueData))
        SecItemAdd(CFBridgingRetain(q) as CFDictionaryRef, null)
    }

    fun read(account: String): String? = memScoped {
        val q = baseQuery(account)
        // Use NSNumber(true), NOT kCFBooleanTrue: the raw CFBoolean constant put
        // into an NSMutableDictionary gets wrapped as a Kotlin object, and when
        // SecItemCopyMatching later calls CFBooleanGetValue on it the bridge
        // sends `boolValue` to a Shared_kobjc box → crash. A toll-free-bridged
        // NSNumber boolean round-trips cleanly.
        q.setObject(NSNumber(bool = true), forKey = key(kSecReturnData))
        q.setObject(key(kSecMatchLimitOne), forKey = key(kSecMatchLimit))
        val result = alloc<CFTypeRefVar>()
        val status: OSStatus = SecItemCopyMatching(
            CFBridgingRetain(q) as CFDictionaryRef,
            result.ptr as CValuesRef<CFTypeRefVar>,
        )
        if (status != 0) return@memScoped null
        val data = CFBridgingRelease(result.value) as? NSData ?: return@memScoped null
        NSString.create(data, NSUTF8StringEncoding) as String?
    }

    fun delete(account: String) {
        SecItemDelete(CFBridgingRetain(baseQuery(account)) as CFDictionaryRef)
    }
}
