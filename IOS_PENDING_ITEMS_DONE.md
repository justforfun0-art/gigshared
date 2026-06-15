# iOS pending items — implementation notes (2026-06-15)

All previously-pending iOS/KMP items implemented. Build verification is pending
on the user's machine (this environment can't run the Gradle/Xcode build).

## What was done

### Item 3 — Verify-completion OTP loop (the half-built work-session loop)
- `Features/WorkSession/WorkSessionViewModel.swift` + `WorkSessionView.swift`
  (worker side): SELECTED→accept, ACCEPTED/OTP_REQUESTED→enter start OTP
  (`verifyStartOtp`), WORK_IN_PROGRESS→"Complete work" (`generateCompletionOtp`),
  COMPLETION_PENDING→read/regenerate the completion code.
- `Features/MyApplicationsView.swift`: actionable rows now `NavigationLink` into
  the work-session screen.
- `Features/Employer/ApplicantsView.swift` + VM: the COMPLETION_PENDING action
  changed from (wrongly) generating the completion OTP to a sheet where the
  employer **enters** the code the worker read out (`verifyCompletionOtp`).
  Flow direction matches the web app (employee/employer application pages).

### Item 2 — Profile editing + photo upload
- `Features/ProfileView.swift` + `ProfileViewModel.swift`: Edit sheet for
  name/email/bio/skills (`updateEmployeeProfile` via `editEmployeeProfileOrThrow`
  copy-shim), and a PhotosPicker avatar that uploads via
  `uploadProfilePhotoBase64OrThrow` (Swift sends base64; Kotlin decodes — avoids
  the costly Data→KotlinByteArray element copy).

### Item 4 — Dashboard stats + referral
- `Features/Dashboard/DashboardView.swift` + `DashboardViewModel.swift`:
  role-aware stat tiles (employee vs employer) + a referral card (ShareLink).
- `RootView.swift` restructured into **role-based tab bars** (employee vs
  employer) to stay within iOS's 5-tab limit. Employee Home carries a bell
  toolbar button → notifications sheet (employee lost its dedicated Alerts tab
  per the chosen trade-off; employer keeps Alerts).

### Item 1 — Employer payments
- `Features/Payments/PaymentsView.swift` + `PaymentsViewModel.swift` +
  `SafariSheet.swift`: 4 headline tiles + payment-row cards from
  `getEmployerPaymentSummary`. "Pay now" calls `createOrder` and opens the hosted
  Cashfree link in an in-app Safari sheet; `verifyPayment` re-reads status.
  (Native Cashfree SDK checkout remains out of scope — hosted link is the
  portable path. customerPhone uses the employer's session phone — server
  validates exactly 10 digits.)

### Items 6 + 7 — SKIE + dead dep
- Dropped the dead `supabase-auth` dependency (Auth plugin was never installed;
  conflicts with our custom `accessToken` callback).
- Added **SKIE 0.10.12** (`co.touchlab.skie`, supports Kotlin 2.1.20, needs the
  static framework we already use) and wired the first Flow collection:
  `AuthViewModel.startObserving()` consumes `getAuthState()` as an
  `AsyncSequence`, driving login state reactively.

### Xcode project
- All 9 new Swift files registered in `iosApp.xcodeproj/project.pbxproj`
  (PBXBuildFile + PBXFileReference + groups WorkSession/Dashboard/Payments +
  Sources phase). The project uses manual file references, not synchronized
  groups, so this was required.

## ⚠️ Build-verification risks to check first

1. **SKIE enum bridging.** SKIE converts Kotlin enums to native Swift enums.
   Confirm `ApplicationStatus`/`Gender` instance methods still resolve in Swift
   (`status.toDisplayString()`, `status.isTerminal()`, `status.isActive()`,
   `gender.toDisplayString()`) and that case access (`ApplicationStatus.applied`)
   is unchanged. If SKIE moved enum methods, a small migration across the feature
   files is needed. SKIE does NOT change `KotlinInt`/`KotlinDouble` boxing, so
   existing `.intValue` / new `.doubleValue` calls are fine.
2. **SKIE Flow iteration.** `for try await state in auth.getAuthState()` assumes
   SKIE's AsyncSequence bridge. If SKIE surfaces it without `throws`, drop the
   `try`.
3. First SKIE build is slower (it regenerates the Swift bridge). Run
   `./gradlew :shared:assembleSharedReleaseXCFramework` once before opening Xcode.

## Verify
- `./gradlew :shared:assembleSharedReleaseXCFramework` (shared compiles + SKIE)
- Open `iosApp/iosApp.xcodeproj`, build for a simulator, drive
  login → dashboard → (worker) apply/start-OTP/complete and (employer)
  applicants → enter completion code → payments.
