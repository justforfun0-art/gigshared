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
        if auth.isSignedIn, let session = auth.session {
            TabView {
                JobFeedView(jobs: container.jobs,
                            applications: container.applications,
                            employeeId: session.userId)
                    .tabItem { Label("Jobs", systemImage: "briefcase") }

                MyApplicationsView(applications: container.applications, employeeId: session.userId)
                    .tabItem { Label("Applications", systemImage: "doc.text") }

                EarningsView(payouts: container.payouts)
                    .tabItem { Label("Earnings", systemImage: "indianrupeesign.circle") }

                MyJobsView(container: container, employerId: session.userId)
                    .tabItem { Label("Hiring", systemImage: "person.2.badge.gearshape") }

                NotificationsView(notifications: container.notifications)
                    .tabItem { Label("Alerts", systemImage: "bell") }

                ProfileView(profileRepo: container.profile, session: session) {
                    Task { await auth.signOut() }
                }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }
        } else {
            AuthView(viewModel: auth)
        }
    }
}
