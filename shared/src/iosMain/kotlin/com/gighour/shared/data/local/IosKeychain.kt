package com.gighour.shared.data.local

import com.gighour.shared.util.Logger
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
import platform.Foundation.NSUserDefaults
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
import platform.Security.kSecUseDataProtectionKeychain
import platform.Security.kSecValueData
import platform.darwin.OSStatus

/**
 * Thin Keychain wrapper (kSecClassGenericPassword) shared by the iOS secure
 * stores. Items are scoped by [service]; each value lives under an account key.
 *
 * The query dictionaries are built as `NSDictionary` whose KEYS and VALUES are
 * the Security framework's CF* constants kept as-is (they are CFStringRef, which
 * is toll-free-bridged to NSString) and proper Foundation objects (NSString /
 * NSData / NSNumber). Earlier hand-rolled CFBridging on individual entries
 * produced malformed queries → SecItem* returned errSecParam (-50) and nothing
 * ever persisted (the app kept asking for OTP on every launch). NSDictionary
 * with bridged CF keys/values round-trips cleanly to CFDictionaryRef.
 */
@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
internal class IosKeychain(private val service: String) {

    // kSec* constants are CFStringRef globals, toll-free bridged to NSString.
    // reinterpret the CFString pointer straight to an NSString instance and use
    // it as an NSDictionary key/value. (CFBridgingRetain/Release round-trips
    // returned an opaque CPointer that failed `as NSString`.)
    private fun CFStringRef?.ns(): NSString = CFBridgingRelease(CFRetain(this)) as NSString
    private val cfClass = kSecClass.ns()
    private val cfService = kSecAttrService.ns()
    private val cfAccount = kSecAttrAccount.ns()
    private val cfValueData = kSecValueData.ns()
    private val cfReturnData = kSecReturnData.ns()
    private val cfMatchLimit = kSecMatchLimit.ns()
    private val cfMatchLimitOne = kSecMatchLimitOne.ns()
    private val cfGenericPassword = kSecClassGenericPassword.ns()
    private val cfUseDataProtection = kSecUseDataProtectionKeychain.ns()

    /** Build the shared query (class + service + account) as a mutable dict. */
    private fun baseQuery(account: String): NSMutableDictionary {
        val q = NSMutableDictionary()
        q.setObject(cfGenericPassword, forKey = cfClass)
        q.setObject(service as NSString, forKey = cfService)
        q.setObject(account as NSString, forKey = cfAccount)
        // Use the data-protection keychain (works on simulator + device once the
        // app declares a keychain-access-group entitlement; without it SecItem*
        // returns errSecMissingEntitlement -34018). The entitlement is in
        // iosApp/iosApp.entitlements.
        q.setObject(NSNumber(bool = true), forKey = cfUseDataProtection)
        return q
    }

    private fun NSMutableDictionary.asCF(): CFDictionaryRef =
        CFBridgingRetain(this) as CFDictionaryRef

    fun write(account: String, value: String) {
        delete(account)
        val data = (value as NSString).dataUsingEncoding(NSUTF8StringEncoding) ?: return
        val q = baseQuery(account)
        q.setObject(data, forKey = cfValueData)
        val status = SecItemAdd(q.asCF(), null)
        if (status != 0) {
            // Keychain unavailable (e.g. errSecMissingEntitlement -34018 on an
            // unsigned simulator build). Fall back to NSUserDefaults so the
            // session still persists; on a properly-signed device the keychain
            // succeeds and this fallback is never reached.
            Logger.e(TAG, "SecItemAdd($account) failed: OSStatus=$status — using NSUserDefaults fallback")
            defaults.setObject(value, forKey = fallbackKey(account))
        } else {
            // Keychain is authoritative — clear any stale fallback copy.
            defaults.removeObjectForKey(fallbackKey(account))
        }
    }

    fun read(account: String): String? {
        memScoped {
            val q = baseQuery(account)
            q.setObject(NSNumber(bool = true), forKey = cfReturnData)
            q.setObject(cfMatchLimitOne, forKey = cfMatchLimit)
            val result = alloc<CFTypeRefVar>()
            val status: OSStatus = SecItemCopyMatching(
                q.asCF(),
                result.ptr as CValuesRef<CFTypeRefVar>,
            )
            if (status == 0) {
                val data = CFBridgingRelease(result.value) as? NSData
                if (data != null) return NSString.create(data, NSUTF8StringEncoding) as String?
            } else if (status != -25300) {
                // Not just "no item" — the keychain is unusable; fall back.
                Logger.e(TAG, "SecItemCopyMatching($account) failed: OSStatus=$status — trying NSUserDefaults fallback")
                return defaults.stringForKey(fallbackKey(account))
            }
        }
        // errSecItemNotFound from the keychain: still check the fallback (an
        // earlier write may have landed there if the keychain was unavailable).
        return defaults.stringForKey(fallbackKey(account))
    }

    fun delete(account: String) {
        SecItemDelete(baseQuery(account).asCF())
        defaults.removeObjectForKey(fallbackKey(account))
    }

    // --- NSUserDefaults fallback (used only when the keychain is unavailable) ---
    private val defaults = NSUserDefaults.standardUserDefaults
    private fun fallbackKey(account: String): String = "kc_fallback_${service}_$account"

    private companion object {
        const val TAG = "IosKeychain"
    }
}
