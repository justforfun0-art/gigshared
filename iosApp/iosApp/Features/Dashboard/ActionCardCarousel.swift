import SwiftUI
import Shared

/// The Home dashboard's actionable-card carousel — a full port of Android's
/// `ActionCardCarousel`. Each in-flight application (SELECTED → PAYMENT_PENDING)
/// renders as its own status-specific card with the same content and button
/// actions as Android:
///   SELECTED            → purple Accept-Job card (Maps/Call) → confirm + accept
///   ACCEPTED            → green Start-Work card → request OTP (waiting state)
///   OTP_REQUESTED       → green Start-Work card → Enter-OTP dialog
///   WORK_IN_PROGRESS    → deep-purple card w/ live HH:MM:SS timer → Complete Work
///   COMPLETION_PENDING  → peach Show-Code voucher → reveal completion code
///   PAYMENT_PENDING     → lavender voucher → View details
/// A peek of the next card + paging dots cue swipeability.
struct ActionCardCarousel: View {

    let applications: any ApplicationRepository
    let employeeId: String
    let messages: (any MessageRepository)?

    @StateObject private var viewModel: ActionCarouselViewModel
    @State private var page = 0
    @State private var tappedPage: Int?
    @State private var containerWidth: CGFloat = 0
    /// The carousel row's leading-edge X in global space (the reference the
    /// active-dot calc compares each card's leading edge against).
    @State private var rowLeadingX: CGFloat = 0
    // Action sheets/dialogs driven by card buttons.
    @State private var acceptTarget: Application?
    @State private var otpTarget: Application?
    @State private var otpInput = ""
    @State private var codeTarget: Application?
    @State private var revealedCode: String?
    @State private var detailTarget: Application?


    init(applications: any ApplicationRepository, employeeId: String,
         messages: (any MessageRepository)? = nil) {
        self.applications = applications
        self.employeeId = employeeId
        self.messages = messages
        _viewModel = StateObject(wrappedValue: ActionCarouselViewModel(
            applications: applications, employeeId: employeeId
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(L("ios_needs_your_attention"), systemImage: "bell.badge")
                        .font(.headline)
                    carousel
                    if viewModel.items.count > 1 { dots }
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task { await viewModel.load() }
        // Navigate to the full status screen (title tap / View Details / View).
        // iOS 16-compatible hidden NavigationLink(isActive:) — navigationDestination(item:)
        // is iOS 17+.
        .background(
            NavigationLink(isActive: detailBinding) {
                if let app = detailTarget {
                    ApplicationStatusView(application: app, messages: messages, myUserId: employeeId, applications: applications)
                }
            } label: { EmptyView() }
            .hidden()
        )
        // SELECTED: confirm before accepting (Android pendingAcceptId dialog).
        .alert(L("ios_accept_offer"), isPresented: acceptBinding, presenting: acceptTarget) { app in
            Button(L("ios_accept_offer")) { Task { await viewModel.accept(app) } }
            Button(L("cancel_filter"), role: .cancel) { }
        } message: { app in
            Text("\(app.job?.title ?? "this job") — accept this job offer?")
        }
        // OTP_REQUESTED: enter the start OTP (Android enter_otp dialog).
        .alert(L("ios_enter_start_otp"), isPresented: otpBinding, presenting: otpTarget) { app in
            TextField("6-digit code", text: $otpInput).keyboardType(.numberPad)
            Button(L("start_work")) { Task { await viewModel.submitStartOtp(app, otp: otpInput); otpInput = "" } }
            Button(L("cancel_filter"), role: .cancel) { otpInput = "" }
        } message: { _ in Text(L("ios_ask_your_employer_for_the_start_code_the")) }
        // COMPLETION_PENDING: rich completion-code sheet (Android
        // CompletionOtpDisplayDialog) — giant code + regenerate + Done.
        .sheet(isPresented: codeBinding) {
            if let code = revealedCode, let app = codeTarget {
                WorkerCompletionCodeSheet(
                    code: code,
                    onRegenerate: { await viewModel.regenerateCompletionCode(app) },
                    onDone: { codeTarget = nil; revealedCode = nil }
                )
            }
        }
        .alert("Couldn’t complete that", isPresented: errBinding) {
            Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
        } message: { Text(viewModel.actionError ?? "") }
    }

    // MARK: - Carousel + dots

    private var carousel: some View {
        let spacing: CGFloat = 12
        let peek: CGFloat = viewModel.items.count > 1 ? 36 : 0
        // Measure the row width with a zero-height background probe so the
        // ScrollView can size its HEIGHT to the cards' own content (each card
        // hugs its content, like Android's vouchers — no forced uniform height
        // that left a void on short cards).
        let cardWidth = max(containerWidth - peek, 1)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { idx, app in
                        ActionCard(
                            application: app,
                            count: viewModel.items.count,
                            startTime: viewModel.startTimes[app.id],
                            isBusy: viewModel.busyId == app.id,
                            onAction: { handle($0, app) }
                        )
                        // Width fixed; height hugs each card's content (Android
                        // vouchers are short, WIP is tall).
                        .frame(width: cardWidth)
                        // Report this card's leading-edge X in GLOBAL space,
                        // keyed by index, so the carousel can pick the nearest.
                        .background(GeometryReader { g in
                            Color.clear.preference(key: CardOffsetsKey.self,
                                value: [idx: g.frame(in: .global).minX])
                        })
                        .id(app.id)
                    }
                }
            }
            .onChange(of: tappedPage) { target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(viewModel.items[target].id, anchor: .leading) }
                tappedPage = nil
            }
        }
        // Capture the row's own leading edge (global) + width; the active page is
        // the card whose leading edge is closest to the row's leading edge.
        .background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    containerWidth = geo.size.width
                    rowLeadingX = geo.frame(in: .global).minX
                }
                .onChange(of: geo.size.width) { containerWidth = $0 }
                .onChange(of: geo.frame(in: .global).minX) { rowLeadingX = $0 }
        })
        .onPreferenceChange(CardOffsetsKey.self) { offsets in
            guard !offsets.isEmpty, rowLeadingX != 0 else { return }
            let nearest = offsets.min { abs($0.value - rowLeadingX) < abs($1.value - rowLeadingX) }
            if let idx = nearest?.key {
                page = min(max(idx, 0), viewModel.items.count - 1)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<viewModel.items.count, id: \.self) { i in
                Circle()
                    .fill(i == page ? GHTheme.primary : GHTheme.primary.opacity(0.25))
                    .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: page)
                    .onTapGesture { tappedPage = i }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action routing (mirrors Android EmployeeDashboardScreen onAction)

    private func handle(_ action: CardAction, _ app: Application) {
        switch action {
        case .openDetails, .viewDetails, .view: detailTarget = app
        case .accept: acceptTarget = app
        case .startWork:
            // ACCEPTED: generate the start OTP (→ OTP_REQUESTED), then open the
            // enter-OTP step so the worker enters the code right away.
            Task {
                if await viewModel.requestStartOtp(app) != nil { otpInput = ""; otpTarget = app }
            }
        case .enterOtp: otpInput = ""; otpTarget = app
        case .completeWork: detailTarget = app   // completion flow lives on the detail screen
        case .showCode:
            // Fetch the code FIRST, then present the alert. SwiftUI's
            // .alert(message:) captures its content when shown and does NOT
            // re-render when an async update lands later — presenting before the
            // fetch left it stuck on "Loading code…".
            Task {
                let code = await viewModel.completionCode(app)
                revealedCode = code
                if code == nil { viewModel.actionError = "Couldn’t load the completion code. Pull to refresh and try again." }
                else { codeTarget = app }
            }
        }
    }

    private var detailBinding: Binding<Bool> {
        Binding(get: { detailTarget != nil }, set: { if !$0 { detailTarget = nil } })
    }
    private var acceptBinding: Binding<Bool> {
        Binding(get: { acceptTarget != nil }, set: { if !$0 { acceptTarget = nil } })
    }
    private var otpBinding: Binding<Bool> {
        Binding(get: { otpTarget != nil }, set: { if !$0 { otpTarget = nil } })
    }
    private var codeBinding: Binding<Bool> {
        Binding(get: { codeTarget != nil }, set: { if !$0 { codeTarget = nil; revealedCode = nil } })
    }
    private var errBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }
}

/// Card button actions, mirroring Android's onAction strings.
enum CardAction { case openDetails, viewDetails, view, accept, startWork, enterOtp, completeWork, showCode }

// MARK: - Per-status card dispatcher

/// Routes each application to its Android-equivalent card design.
private struct ActionCard: View {
    let application: Application
    let count: Int
    let startTime: String?
    let isBusy: Bool
    let onAction: (CardAction) -> Void

    var body: some View {
        switch application.status {
        case .selected:
            AcceptJobOfferCard(application: application, count: count, isBusy: isBusy, onAction: onAction)
        case .accepted, .otpRequested:
            StartWorkCard(application: application, count: count, isBusy: isBusy, onAction: onAction)
        case .workInProgress:
            WorkInProgressCard(application: application, count: count, startTime: startTime, onAction: onAction)
        case .completionPending:
            ShowCodeVoucherCard(application: application, isBusy: isBusy, onAction: onAction)
        case .paymentPending:
            PaymentPendingVoucherCard(application: application, onAction: onAction)
        default:
            PaymentPendingVoucherCard(application: application, onAction: onAction)
        }
    }
}

// MARK: - Shared bits

private func grad(_ a: UInt, _ b: UInt, _ start: UnitPoint = .topLeading, _ end: UnitPoint = .bottomTrailing) -> LinearGradient {
    LinearGradient(colors: [GHTheme.hex(a), GHTheme.hex(b)], startPoint: start, endPoint: end)
}

/// White count badge (Android's circular count pill in card headers).
private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold)).foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.22), in: Circle())
    }
}

/// "View Details →" footer link used across cards.
private struct DetailsFooter: View {
    let hint: String
    let onTap: () -> Void
    var body: some View {
        HStack {
            Text(hint).font(.caption).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onTap) {
                HStack(spacing: 2) {
                    Text(L("view_details")).font(.caption.weight(.semibold))
                    Text("→").font(.caption)
                }.foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
    }
}

// MARK: - SELECTED → Accept Job Offer (purple)

private struct AcceptJobOfferCard: View {
    let application: Application
    let count: Int
    let isBusy: Bool
    let onAction: (CardAction) -> Void
    @Environment(\.openURL) private var openURL
    private var job: Job? { application.job }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("ios_job_offer_received")).font(.headline.weight(.bold)).foregroundStyle(.white)
                    Text(L("accept_to_confirm")).font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(); CountBadge(count: count)
            }
            // White inner panel: title + location + Maps/Call + Accept.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    iconTile("briefcase.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job?.title ?? "Job").font(.subheadline.weight(.bold))
                            .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                        if let c = job?.employerProfile?.companyName, !c.isEmpty {
                            Text(c).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                if let addr = workAddress {
                    Label(addr, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(2)
                    HStack(spacing: 8) {
                        smallButton("Maps", "map.fill", GHTheme.hex(0x22C55E)) { openMaps(addr) }
                        smallButton(L("call"), "phone.fill", GHTheme.hex(0x2563EB), enabled: phone != nil) {
                            if let p = phone, let u = URL(string: "tel://\(p)") { openURL(u) }
                        }
                    }
                }
                ctaButton(L("accept_job"), grad(0x8B5CF6, 0x7C3AED), icon: "checkmark", busy: isBusy) {
                    onAction(.accept)
                }
            }
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 10)
            DetailsFooter(hint: L("action_hint_tap_accept_job")) { onAction(.viewDetails) }
        }
        .voucherChrome(grad(0x8B5CF6, 0x7C3AED, .top, .bottom))
    }

    private var workAddress: String? {
        let a = job?.employerProfile?.address
        if let a, !a.isEmpty { return a }
        return job?.location
    }
    private var phone: String? { job?.employerUser?.phone }
    private func openMaps(_ q: String) {
        let s = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let u = URL(string: "http://maps.apple.com/?q=\(s)") { openURL(u) }
    }
}

// MARK: - ACCEPTED / OTP_REQUESTED → Start Work (green)

private struct StartWorkCard: View {
    let application: Application
    let count: Int
    let isBusy: Bool
    let onAction: (CardAction) -> Void
    private var job: Job? { application.job }
    private var isOtpReady: Bool { application.status == .otpRequested }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("ready_to_start")).font(.headline.weight(.bold)).foregroundStyle(.white)
                    Text(isOtpReady ? L("ios_enter_start_otp") : L("ios_waiting_for_employer_otp"))
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(); CountBadge(count: count)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    iconTile("briefcase.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job?.title ?? "Job").font(.subheadline.weight(.bold))
                            .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                        if let c = job?.employerProfile?.companyName, !c.isEmpty {
                            Text(c).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                if let loc = job?.district ?? job?.location {
                    Label(loc, systemImage: "mappin").font(.caption)
                        .foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                }
                // Android shows an active "Start Work" CTA for both ACCEPTED and
                // OTP_REQUESTED (both open the start-OTP flow); the subtitle is
                // what differs. OTP_REQUESTED → "Enter OTP"; ACCEPTED → "Start Work".
                Text(isOtpReady ? L("ios_enter_otp_to_start_work") : L("ios_waiting_for_employer_otp"))
                    .font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ctaButton(isOtpReady ? L("ios_enter_start_otp") : L("start_work"),
                          grad(0x10B981, 0x059669), icon: "key.fill", busy: isBusy) {
                    onAction(isOtpReady ? .enterOtp : .startWork)
                }
            }
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 10)
            DetailsFooter(hint: L("tap_start_work_to_proceed")) { onAction(.viewDetails) }
        }
        .voucherChrome(grad(0x10B981, 0x059669, .top, .bottom))
    }
}

// MARK: - WORK_IN_PROGRESS → live timer (deep purple)

private struct WorkInProgressCard: View {
    let application: Application
    let count: Int
    let startTime: String?
    let onAction: (CardAction) -> Void
    private var job: Job? { application.job }
    @State private var elapsed: TimeInterval = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("ios_work_in_progress")).font(.headline.weight(.bold)).foregroundStyle(.white)
                    Text(L("complete_and_verify")).font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(); CountBadge(count: count)
            }
            VStack(alignment: .leading, spacing: 8) {
                // Row 1: job title + company (timer moved to its own row so the
                // title isn't squeezed off-screen).
                HStack(spacing: 8) {
                    iconTile("briefcase.fill", gradient: grad(0xA78BFA, 0x8B5CF6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job?.title ?? "Job").font(.subheadline.weight(.bold))
                            .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                        if let c = job?.employerProfile?.companyName, !c.isEmpty {
                            Text(c).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                // Row 2: full-width green live timer chip.
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill").font(.caption)
                    Text(timeString).font(.title3.weight(.bold).monospacedDigit())
                    Spacer(minLength: 0)
                }
                .foregroundStyle(GHTheme.hex(0x16A34A))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GHTheme.hex(0xECFDF5), in: RoundedRectangle(cornerRadius: 10))

                ctaButton(L("complete_work"), grad(0xA78BFA, 0x4F46E5), icon: "checkmark.circle.fill") {
                    onAction(.completeWork)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 10)
            DetailsFooter(hint: L("action_hint_tap_complete_work")) { onAction(.viewDetails) }
        }
        .voucherChrome(grad(0x5B21B6, 0x7C3AED, .top, .bottom))
        .onReceive(tick) { _ in recompute() }
        .onAppear { recompute() }
    }

    private var timeString: String {
        let s = Int(max(elapsed, 0))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    private func recompute() {
        guard let startTime, let start = parseISO(startTime) else { elapsed = 0; return }
        elapsed = Date().timeIntervalSince(start)
    }
    // Robust against Postgres' "yyyy-MM-dd HH:mm:ss.SSSSSS+00" shape.
    private func parseISO(_ s: String) -> Date? { ActiveJobBarViewModel.parseISO(s) }
}

// MARK: - COMPLETION_PENDING → Show Code voucher (peach)

private struct ShowCodeVoucherCard: View {
    let application: Application
    let isBusy: Bool
    let onAction: (CardAction) -> Void
    private var job: Job? { application.job }
    private var amount: String? {
        guard let a = application.paymentAmount?.doubleValue, a > 0 else { return nil }
        return Money.rupees(a)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job?.title ?? "Job").font(.subheadline.weight(.bold))
                        .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                    Text(L("ios_awaiting_verification")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                Spacer()
                Text(application.status.toDisplayString()).font(.caption2.weight(.semibold))
                    .foregroundStyle(GHTheme.hex(0xC2410C))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(GHTheme.hex(0xFED7AA), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("action_card_show_code_hint")).font(.caption)
                    .foregroundStyle(GHTheme.hex(0x374151)).lineLimit(2)
                if let amount {
                    HStack {
                        Text(L("estimated_payment_label")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                        Spacer()
                        Text(amount).font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.hex(0xEA580C))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white, in: TicketShape(cornerRadius: 10, notchRadius: 6))
            // Fixed gap (not greedy) so the CTA sits right under the sub-ticket
            // — voucher cards hug their content with no empty void.
            Spacer().frame(height: 12)
            ctaButton(L("show_code"), grad(0xFB923C, 0xEA580C, .leading, .trailing), icon: "key.fill", busy: isBusy) {
                onAction(.showCode)
            }
        }
        .voucherChrome(bg: GHTheme.hex(0xFEF3E7), border: GHTheme.hex(0xFDBA74), darkText: true)
    }
}

// MARK: - PAYMENT_PENDING → voucher (lavender)

private struct PaymentPendingVoucherCard: View {
    let application: Application
    let onAction: (CardAction) -> Void
    private var job: Job? { application.job }
    private var amount: String? {
        guard let a = application.paymentAmount?.doubleValue, a > 0 else { return nil }
        return Money.rupees(a)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job?.title ?? "Job").font(.subheadline.weight(.bold))
                        .foregroundStyle(GHTheme.onBackground).lineLimit(1)
                    Text(L("ios_payment_being_processed")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                Spacer()
                Text(application.status.toDisplayString()).font(.caption2.weight(.semibold))
                    .foregroundStyle(GHTheme.hex(0x6D28D9))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(GHTheme.hex(0xEDE9FE), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("payment_pending_instruction")).font(.caption)
                    .foregroundStyle(GHTheme.hex(0x374151)).lineLimit(2)
                if let amount {
                    HStack {
                        Text(L("estimated_payment_label")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                        Spacer()
                        Text(amount).font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.hex(0x7C3AED))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white, in: TicketShape(cornerRadius: 10, notchRadius: 6))
            Spacer().frame(height: 12)
            ctaButton(L("view_action"), grad(0x8B5CF6, 0x7C3AED, .leading, .trailing), icon: nil) {
                onAction(.view)
            }
        }
        .voucherChrome(bg: GHTheme.hex(0xF5F3FF), border: GHTheme.hex(0xC4B5FD), darkText: true)
    }
}

// MARK: - Shared view helpers

/// Small violet icon tile used in white inner panels.
private func iconTile(_ symbol: String, gradient: LinearGradient = LinearGradient(colors: [GHTheme.hex(0xEDE9FE)], startPoint: .top, endPoint: .bottom)) -> some View {
    RoundedRectangle(cornerRadius: 8).fill(gradient).frame(width: 32, height: 32)
        .overlay(Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(GHTheme.primary))
}

/// Full-width gradient CTA with optional icon + busy spinner.
private func ctaButton(_ title: String, _ gradient: LinearGradient, icon: String?, busy: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            if busy { ProgressView().tint(.white) }
            else {
                if let icon { Image(systemName: icon).font(.caption.weight(.bold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(gradient, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(busy)
}

/// Small dual-action button (Maps / Call).
private func smallButton(_ title: String, _ icon: String, _ color: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(enabled ? color : color.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
}

/// Outer card chrome — either a gradient ticket (status cards) or a tinted
/// voucher (peach/lavender). darkText toggles for light voucher backgrounds.
private extension View {
    func voucherChrome(_ gradient: LinearGradient) -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // notchFromTop nil → notch at each card's vertical centre.
            .background(gradient, in: TicketShape(cornerRadius: 18, notchRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
    func voucherChrome(bg: Color, border: Color, darkText: Bool) -> some View {
        let shape = TicketShape(cornerRadius: 18, notchRadius: 12)
        return self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg, in: shape)
            .overlay(shape.stroke(border, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Carousel infra (scroll offset → active dot)

/// Each card reports its leading-edge X (in global space) keyed by index. The
/// carousel then picks whichever card's edge is nearest the row's own leading
/// edge as the active page. Global space is used because it reliably reflects
/// real scroll position (a named space on the ScrollView resolves to the moving
/// content and stays ~0).
private struct CardOffsetsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Ticket outline with concave side notches — port of Android's TicketShape.
private struct TicketShape: Shape {
    var cornerRadius: CGFloat = 18
    var notchRadius: CGFloat = 12
    var notchFromTop: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius, n = notchRadius
        let w = rect.width, h = rect.height
        let midY = (notchFromTop ?? h / 2).clamped(to: (r + n)...max(r + n, h - r - n))
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: w, y: midY - n))
        p.addArc(center: CGPoint(x: w, y: midY), radius: n, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r, y: h))
        p.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: midY + n))
        p.addArc(center: CGPoint(x: 0, y: midY), radius: n, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
