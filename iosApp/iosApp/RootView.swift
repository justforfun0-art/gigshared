import SwiftUI
import Shared

/// Top-level gate: OTP login until signed in, then the main screen with an
/// Android-style custom bottom bar (GHBottomBar) instead of SwiftUI's TabView,
/// so the nav matches Android (role accent, top indicator pill, gray
/// unselected, larger icons). Tabs mirror Android exactly:
///   employee: Home · Jobs · History · Earnings · Profile (violet)
///   employer: Home · My Jobs · Applications · Payments · Profile (green)
struct RootView: View {

    let container: AppContainer
    @StateObject private var auth: AuthViewModel
    @ObservedObject private var locale = LocaleManager.shared
    @State private var selected = 0
    @State private var showAssistant = false
    @State private var showMessages = false
    @State private var showDrawer = false

    init(container: AppContainer) {
        self.container = container
        _auth = StateObject(wrappedValue: AuthViewModel(auth: container.auth))
    }

    var body: some View {
        Group {
            if auth.isSignedIn, let session = auth.session {
                let isEmployer = session.userType?.lowercased() == "employer"
                mainShell(session: session, isEmployer: isEmployer)
            } else {
                AuthView(viewModel: auth)
            }
        }
        // Re-render the whole tree when the in-app language changes, and align
        // SwiftUI's own formatting (dates/numbers) with the chosen locale.
        .environment(\.locale, locale.locale)
        .id(locale.language)
        // Observe the persisted-session Flow (SKIE-bridged) so a restored or
        // cleared session drives the UI without an imperative reload.
        .task { auth.startObserving() }
    }

    @ViewBuilder
    private func mainShell(session: AuthData, isEmployer: Bool) -> some View {
        let tabs = isEmployer ? employerTabs : employeeTabs
        ZStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    screen(for: selected, session: session, isEmployer: isEmployer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Floating AI assistant — available from every tab (Android parity).
                    FloatingAssistantButton(isEmployer: isEmployer) { showAssistant = true }
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                }

                GHBottomBar(
                    tabs: tabs,
                    selected: Binding(
                        get: { min(selected, tabs.count - 1) },
                        set: { selected = $0 }
                    ),
                    isEmployer: isEmployer
                )
            }

            // Side menu drawer (Android NavigationDrawer), slides in from the
            // left over a scrim when the nav-bar hamburger is tapped.
            if showDrawer {
                SideMenuDrawer(
                    isEmployer: isEmployer,
                    userName: session.phone,   // name resolved in the drawer header fallback
                    selectedTab: selected,
                    onSelectTab: { selected = $0 },
                    onMessages: { showMessages = true },
                    onAssistant: { showAssistant = true },
                    onHelp: { showAssistant = true },   // route Help to the assistant for now
                    onLogout: { Task { await auth.signOut() } },
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { showDrawer = false } }
                )
                .zIndex(2)
            }
        }
        // Publish the "open drawer" action so each tab screen can show the
        // hamburger leading nav-bar button via `.drawerToolbar()`.
        .environment(\.openDrawer, { withAnimation(.easeInOut(duration: 0.25)) { showDrawer = true } })
        .sheet(isPresented: $showAssistant) {
            AssistantView(engine: container.assistant, userId: session.userId, isEmployer: isEmployer)
        }
        .sheet(isPresented: $showMessages) {
            MessagesView(repo: container.messages, myUserId: session.userId)
        }
    }

    // MARK: - Tab definitions (icons mirror Android's Lucide set)

    private var employeeTabs: [GHTab] {
        [
            GHTab(label: L("nav_home"), icon: "house"),
            GHTab(label: L("jobs"), icon: "briefcase"),
            GHTab(label: L("nav_applications"), icon: "clock.arrow.circlepath"),
            GHTab(label: L("nav_earnings"), icon: "creditcard"),
            GHTab(label: L("nav_profile"), icon: "person.crop.circle"),
        ]
    }

    private var employerTabs: [GHTab] {
        [
            GHTab(label: L("nav_home"), icon: "house"),
            GHTab(label: L("nav_my_jobs"), icon: "briefcase"),
            GHTab(label: L("nav_employer_applications"), icon: "person.2"),
            GHTab(label: L("nav_payments"), icon: "creditcard"),
            GHTab(label: L("nav_profile"), icon: "person.crop.circle"),
        ]
    }

    // MARK: - Screen for the selected tab

    @ViewBuilder
    private func screen(for index: Int, session: AuthData, isEmployer: Bool) -> some View {
        if isEmployer {
            switch index {
            case 0:
                DashboardView(dashboard: container.dashboard,
                              referralRepo: container.referral,
                              notifications: container.notifications,
                              session: session)
            case 1:
                MyJobsView(container: container, employerId: session.userId)
            case 2:
                // Employer applications — the same history cards + stepper as the
                // employee History, but green-accented and loading applicants to
                // the employer's jobs.
                MyApplicationsView(applications: container.applications,
                                   employeeId: session.userId,
                                   messages: container.messages,
                                   isEmployer: true)
            case 3:
                PaymentsView(payments: container.payments,
                             employerId: session.userId,
                             employerPhone: session.phone,
                             employerName: "Employer")
            default:
                profileScreen(session: session)
            }
        } else {
            switch index {
            case 0:
                DashboardView(dashboard: container.dashboard,
                              referralRepo: container.referral,
                              notifications: container.notifications,
                              swipeJobs: container.jobs,
                              applications: container.applications,
                              profile: container.profile,
                              session: session)
            case 1:
                JobFeedView(jobs: container.jobs,
                            applications: container.applications,
                            employeeId: session.userId,
                            profile: container.profile)
            case 2:
                MyApplicationsView(applications: container.applications, employeeId: session.userId, messages: container.messages)
            case 3:
                EarningsView(dashboard: container.dashboard,
                             applications: container.applications,
                             employeeId: session.userId)
            default:
                profileScreen(session: session)
            }
        }
    }

    @ViewBuilder
    private func profileScreen(session: AuthData) -> some View {
        ProfileView(profileRepo: container.profile, session: session) {
            Task { await auth.signOut() }
        }
    }
}
