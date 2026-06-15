import SwiftUI
import Shared

/// Top-level gate: OTP login until signed in, then the main tab bar.
struct RootView: View {

    let container: AppContainer
    @StateObject private var auth: AuthViewModel

    init(container: AppContainer) {
        self.container = container
        _auth = StateObject(wrappedValue: AuthViewModel(auth: container.auth))
    }

    var body: some View {
        Group {
            if auth.isSignedIn, let session = auth.session {
                if session.userType?.lowercased() == "employer" {
                    employerTabs(session: session)
                } else {
                    employeeTabs(session: session)
                }
            } else {
                AuthView(viewModel: auth)
            }
        }
        // Observe the persisted-session Flow (SKIE-bridged) so a restored or
        // cleared session drives the UI without an imperative reload.
        .task { auth.startObserving() }
    }

    /// Worker-facing tabs: find/track gigs, earnings, alerts, profile.
    @ViewBuilder
    private func employeeTabs(session: AuthData) -> some View {
        TabView {
            DashboardView(dashboard: container.dashboard,
                          referralRepo: container.referral,
                          notifications: container.notifications,
                          swipeJobs: container.jobs,
                          applications: container.applications,
                          session: session)
                .tabItem { Label("Home", systemImage: "house") }

            JobFeedView(jobs: container.jobs,
                        applications: container.applications,
                        employeeId: session.userId)
                .tabItem { Label("Jobs", systemImage: "briefcase") }

            MyApplicationsView(applications: container.applications, employeeId: session.userId)
                .tabItem { Label("Applications", systemImage: "doc.text") }

            EarningsView(payouts: container.payouts)
                .tabItem { Label("Earnings", systemImage: "indianrupeesign.circle") }

            profileTab(session: session)
        }
    }

    /// Employer-facing tabs: hiring overview, jobs/applicants, payments, profile.
    @ViewBuilder
    private func employerTabs(session: AuthData) -> some View {
        TabView {
            DashboardView(dashboard: container.dashboard,
                          referralRepo: container.referral,
                          session: session)
                .tabItem { Label("Overview", systemImage: "chart.bar") }

            MyJobsView(container: container, employerId: session.userId)
                .tabItem { Label("Hiring", systemImage: "person.2.badge.gearshape") }

            PaymentsView(payments: container.payments,
                         employerId: session.userId,
                         employerPhone: session.phone,
                         employerName: "Employer")
                .tabItem { Label("Payments", systemImage: "indianrupeesign.circle") }

            NotificationsView(notifications: container.notifications)
                .tabItem { Label("Alerts", systemImage: "bell") }

            profileTab(session: session)
        }
    }

    @ViewBuilder
    private func profileTab(session: AuthData) -> some View {
        ProfileView(profileRepo: container.profile, session: session) {
            Task { await auth.signOut() }
        }
        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
    }
}
