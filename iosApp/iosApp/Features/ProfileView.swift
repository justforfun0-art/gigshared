import SwiftUI
import PhotosUI
import Shared

/// Employee profile detail + edit + photo upload + sign-out.
struct ProfileView: View {

    @StateObject private var viewModel: ProfileViewModel
    @ObservedObject private var locale = LocaleManager.shared
    let session: AuthData
    /// Opens the notifications list as a sheet (Profile › Notifications row).
    private let notifications: (any NotificationRepository)?
    /// Enables the Settings › Payment-Methods row.
    private let beneficiaries: (any BeneficiaryRepository)?
    /// Routes the Help row to the AI assistant, matching Android's profile Help.
    private let onHelp: (() -> Void)?
    let onSignOut: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showNotifications = false
    @State private var showSettings = false

    init(profileRepo: any ProfileRepository,
         dashboard: (any DashboardRepository)? = nil,
         notifications: (any NotificationRepository)? = nil,
         beneficiaries: (any BeneficiaryRepository)? = nil,
         onHelp: (() -> Void)? = nil,
         session: AuthData,
         onSignOut: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            profileRepo: profileRepo, dashboard: dashboard, userId: session.userId
        ))
        self.session = session
        self.notifications = notifications
        self.beneficiaries = beneficiaries
        self.onHelp = onHelp
        self.onSignOut = onSignOut
    }

    /// Worker tier from completed jobs — port of Android's computeWorkerTier.
    private struct WorkerTier {
        let level: Int; let name: String; let accent: Color
        let emoji: String; let nextThreshold: Int?; let prevThreshold: Int
    }
    private func tier(_ completed: Int) -> WorkerTier {
        switch completed {
        case 50...: return WorkerTier(level: 5, name: "Elite Worker", accent: GHTheme.hex(0xB45309), emoji: "★", nextThreshold: nil, prevThreshold: 50)
        case 25...: return WorkerTier(level: 4, name: "Pro Worker", accent: GHTheme.hex(0x7C3AED), emoji: "◆", nextThreshold: 50, prevThreshold: 25)
        case 10...: return WorkerTier(level: 3, name: "Skilled Worker", accent: GHTheme.hex(0x059669), emoji: "▲", nextThreshold: 25, prevThreshold: 10)
        case 3...:  return WorkerTier(level: 2, name: "Active Worker", accent: GHTheme.hex(0x2563EB), emoji: "●", nextThreshold: 10, prevThreshold: 3)
        default:    return WorkerTier(level: 1, name: "New Worker", accent: GHTheme.hex(0x64748B), emoji: "○", nextThreshold: 3, prevThreshold: 0)
        }
    }

    private var completedJobs: Int { Int(viewModel.stats?.completedJobs ?? 0) }
    private var statsAccent: Color { GHTheme.primary }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("nav_profile"))
            .drawerToolbar()
            .toolbar {
                if viewModel.currentProfile != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { viewModel.isEditing = true } label: { Image(systemName: "pencil") }
                            .tint(GHTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $viewModel.isEditing) {
                if let profile = viewModel.currentProfile {
                    EditProfileSheet(profile: profile, viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showNotifications) {
                if let notifications {
                    NotificationsView(notifications: notifications)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    onNotifications: notifications != nil ? { showNotifications = true } : nil,
                    notificationsRepo: notifications,
                    beneficiaries: beneficiaries,
                    onLogout: onSignOut
                )
            }
            .task { await viewModel.load() }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let profile):
            if let p = profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identityBlock(p)
                        metricTiles
                        totalEarnedPill
                        levelProgress
                        aboutCard(p)
                        chipsCard(L("profile_languages"), items: p.languagesKnown ?? [])
                        chipsCard(L("profile_work_preferences"),
                                  items: (p.workPreferences ?? []).map { $0.name.replacingOccurrences(of: "_", with: " ") })
                        settingsCard
                        logoutButton
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
            } else {
                Text(L("ios_no_profile_yet")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }

    // MARK: - Identity block (avatar + name + location + level + stars)

    @ViewBuilder
    private func identityBlock(_ p: EmployeeProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            avatar(p)
            VStack(alignment: .leading, spacing: 6) {
                Text(p.name).font(.title2.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
                    Text("\(p.district), \(p.state)").font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                levelBadge
                if viewModel.rating > 0 { starRow }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func avatar(_ p: EmployeeProfile) -> some View {
        let url = p.profilePhotoUrl
        ZStack(alignment: .bottomTrailing) {
            Group {
                if viewModel.isSavingPhoto {
                    ProgressView().frame(width: 88, height: 88)
                } else if let url, let parsed = URL(string: url), !url.isEmpty {
                    AsyncImage(url: parsed) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                        .frame(width: 88, height: 88).clipShape(Circle())
                } else {
                    Circle().fill(LinearGradient(colors: [GHTheme.hex(0x8B5CF6), GHTheme.hex(0x7C3AED)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                        .overlay(Text(String(p.name.prefix(2)).uppercased())
                            .font(.title2.weight(.bold)).foregroundStyle(.white))
                }
            }
            // Edit pencil badge bottom-right, opens the photo picker.
            PhotosPicker(selection: $photoItem, matching: .images) {
                Circle().fill(.white).frame(width: 26, height: 26)
                    .overlay(Circle().fill(GHTheme.hex(0xF5F3FF)).frame(width: 22, height: 22))
                    .overlay(Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundStyle(GHTheme.primary))
            }
            .disabled(viewModel.isSavingPhoto)
        }
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.uploadPhoto(jpegData: data)
                }
                photoItem = nil
            }
        }
    }

    private var levelBadge: some View {
        let t = tier(completedJobs)
        return HStack(spacing: 6) {
            Text(t.emoji).font(.subheadline).foregroundStyle(t.accent)
            Text("Level \(t.level) · \(t.name)").font(.caption.weight(.semibold)).foregroundStyle(t.accent)
            if viewModel.rating >= 4.5 && completedJobs >= 5 {
                Text("Top Rated").font(.caption2.weight(.semibold)).foregroundStyle(GHTheme.hex(0xB45309))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(GHTheme.hex(0xFEF3C7), in: Capsule())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(t.accent.opacity(0.10), in: Capsule())
    }

    private var starRow: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                let r = viewModel.rating
                let name = r >= Double(i) ? "star.fill" : (r >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star")
                Image(systemName: name).font(.caption2)
                    .foregroundStyle(r >= Double(i) - 0.5 ? GHTheme.hex(0xF59E0B) : GHTheme.hex(0xD1D5DB))
            }
            Text(String(format: "%.1f", viewModel.rating))
                .font(.caption.weight(.semibold)).foregroundStyle(GHTheme.onSurfaceVariant)
                .padding(.leading, 4)
        }
    }

    // MARK: - Stat tiles + earnings + level progress

    private var metricTiles: some View {
        HStack(spacing: 10) {
            MetricTile(value: "\(Int(viewModel.stats?.activeJobs ?? 0))", label: L("active_stat_label"), accent: statsAccent)
            MetricTile(value: "\(Int(viewModel.stats?.totalApplications ?? 0))", label: L("applications_stat_label"), accent: statsAccent)
            MetricTile(value: "\(completedJobs)", label: L("jobs_completed"), accent: statsAccent)
        }
    }

    private var totalEarnedPill: some View {
        let total = Int(viewModel.stats?.totalEarnings ?? 0)
        let month = Int(viewModel.stats?.thisMonthEarnings ?? 0)
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("total_earned").uppercased())
                    .font(.caption2.weight(.bold)).kerning(0.6).foregroundStyle(GHTheme.hex(0x065F46))
                Text("₹\(total.formatted())")
                    .font(.system(size: 26, weight: .heavy)).foregroundStyle(GHTheme.hex(0x047857))
            }
            Spacer()
            if month > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(GHTheme.hex(0x059669))
                    Text("₹\(month.formatted())").font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.hex(0x065F46))
                }
            }
        }
        .padding(16)
        .background(GHTheme.hex(0xECFDF5), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var levelProgress: some View {
        let t = tier(completedJobs)
        if let next = t.nextThreshold {
            let span = max(next - t.prevThreshold, 1)
            let progress = min(max(Double(completedJobs - t.prevThreshold) / Double(span), 0), 1)
            VStack(spacing: 6) {
                HStack {
                    Text("\(next - completedJobs) jobs to next level")
                        .font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
                    Spacer()
                    Text("\(completedJobs) / \(next)").font(.caption2.weight(.semibold)).foregroundStyle(t.accent)
                }
                ProgressView(value: progress).tint(t.accent)
            }
        }
    }

    // MARK: - About / chips / settings

    @ViewBuilder
    private func aboutCard(_ p: EmployeeProfile) -> some View {
        sectionLabel(L("profile_about"))
        VStack(spacing: 0) {
            aboutRow(L("profile_dob"), formatDob(p.dob))
            Divider()
            aboutRow(L("profile_gender"), p.gender.toDisplayString())
            if let email = p.email, !email.isEmpty {
                Divider(); aboutRow(L("profile_email"), email)
            }
            Divider()
            aboutRow(L("profile_member_since"), formatMemberSince(p.createdAt))
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func chipsCard(_ title: String, items: [String]) -> some View {
        if !items.isEmpty {
            sectionLabel(title)
            FlowChips(items: items)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            sectionLabel(L("profile_settings"))
            VStack(spacing: 0) {
                if notifications != nil {
                    settingsRow("bell", L("profile_notifications")) { showNotifications = true }
                    Divider()
                }
                settingsRow("gearshape", L("profile_settings")) { showSettings = true }
                if onHelp != nil {
                    Divider()
                    settingsRow("questionmark.circle", L("profile_help")) { onHelp?() }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive, action: onSignOut) {
            HStack {
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text(L("log_out"))
                Spacer()
            }
        }
        .tint(GHTheme.error)
        .padding(.vertical, 4)
    }

    // MARK: - Small helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold)).kerning(0.6)
            .foregroundStyle(GHTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
        }
        .padding(.vertical, 10)
    }

    private func settingsRow(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(GHTheme.hex(0x9CA3AF))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatMemberSince(_ createdAt: String?) -> String {
        guard let createdAt, !createdAt.isEmpty else { return "-" }
        return String(createdAt.prefix(7)).replacingOccurrences(of: "-", with: "/")
    }

    private func formatDob(_ dob: String) -> String {
        guard !dob.isEmpty else { return "-" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        if let date = f.date(from: String(dob.prefix(10))) {
            let out = DateFormatter(); out.dateFormat = "dd MMM yyyy"
            return out.string(from: date)
        }
        return dob
    }
}

/// One stat tile (value + uppercase label on a tinted square) — Android MetricTile.
private struct MetricTile: View {
    let value: String; let label: String; let accent: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.heavy)).foregroundStyle(accent).lineLimit(1)
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.5)
                .foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10).padding(.vertical, 12)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Simple wrapping chip flow (Android FlowRow + SuggestionChip).
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption).foregroundStyle(GHTheme.onBackground)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(GHTheme.surfaceVariant, in: Capsule())
                    .overlay(Capsule().stroke(GHTheme.outline, lineWidth: 1))
            }
        }
    }
}

/// A minimal flow layout (iOS 16's Layout protocol) used for the chip groups.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

/// Profile edit — card-sectioned form matching Android's EmployeeProfileEditScreen:
/// a photo picker, Personal Information (name / DOB / gender), Email, Location
/// (cascading state → district menus), About (bio), and Skills. Violet-accented.
private struct EditProfileSheet: View {
    let profile: EmployeeProfile
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var email: String
    @State private var bio: String
    @State private var skillsText: String
    @State private var dob: String
    @State private var gender: String
    @State private var state: String
    @State private var district: String
    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false

    private var accent: Color { GHTheme.hex(0x7C3AED) }

    init(profile: EmployeeProfile, viewModel: ProfileViewModel) {
        self.profile = profile
        self.viewModel = viewModel
        _name = State(initialValue: profile.name)
        _email = State(initialValue: profile.email ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _skillsText = State(initialValue: (profile.skills ?? []).joined(separator: ", "))
        _dob = State(initialValue: profile.dob)
        _gender = State(initialValue: profile.gender.name)
        _state = State(initialValue: profile.state)
        _district = State(initialValue: profile.district)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        photoPicker
                        card(L("personal_information")) {
                            field(L("full_name_required"), "person", text: $name)
                            field(L("dob_required"), "calendar", text: $dob)
                            menuPicker(L("gender_required"), selection: $gender,
                                       options: ["MALE", "FEMALE", "OTHER"],
                                       display: { Gender.companion.fromString(value: $0).toDisplayString() })
                            field(L("email"), "envelope", text: $email,
                                  keyboard: .emailAddress, autocap: false)
                        }
                        card(L("location_label")) {
                            menuPicker(L("state_required"), selection: $state,
                                       options: IndiaData.states) { district = "" }
                            menuPicker(L("district_required"), selection: $district,
                                       options: IndiaData.districts(for: state),
                                       disabled: state.isEmpty)
                        }
                        card(L("about")) {
                            TextField(L("bio_placeholder"), text: $bio, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                        }
                        card(L("skills")) {
                            TextField("Comma-separated (e.g. Cooking, Driving)", text: $skillsText, axis: .vertical)
                                .lineLimit(1...3)
                                .textFieldStyle(.roundedBorder)
                        }
                        if let err = viewModel.actionError {
                            Text(err).font(.footnote).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L("edit_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel_filter")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() }
                    else {
                        Button(L("save")) { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .tint(accent)
                    }
                }
            }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await viewModel.uploadPhoto(jpegData: data)
                    }
                    photoItem = nil
                }
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = profile.profilePhotoUrl, let parsed = URL(string: url), !url.isEmpty {
                        AsyncImage(url: parsed) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                    } else {
                        Circle().fill(LinearGradient(colors: [accent, GHTheme.hex(0x8B5CF6)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Image(systemName: "person.fill").font(.system(size: 34)).foregroundStyle(.white))
                    }
                }
                .frame(width: 84, height: 84).clipShape(Circle())
                .overlay(Circle().stroke(accent, lineWidth: 2))
                Circle().fill(accent).frame(width: 26, height: 26)
                    .overlay(Image(systemName: "camera.fill").font(.system(size: 12)).foregroundStyle(.white))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private func field(_ label: String, _ icon: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default, autocap: Bool = true) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 20)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled(!autocap)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func menuPicker(_ label: String, selection: Binding<String>, options: [String],
                            disabled: Bool = false, display: ((String) -> String)? = nil,
                            onChange: (() -> Void)? = nil) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(display?(opt) ?? opt) { selection.wrappedValue = opt; onChange?() }
            }
        } label: {
            HStack {
                Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Spacer()
                Text(selection.wrappedValue.isEmpty ? L("ios_select") : (display?(selection.wrappedValue) ?? selection.wrappedValue))
                    .foregroundStyle(selection.wrappedValue.isEmpty ? GHTheme.onSurfaceVariant : accent).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .disabled(disabled)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let skills = skillsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ok = await viewModel.save(name: name, email: email, bio: bio, skills: skills,
                                      dob: dob, gender: gender, stateName: state, district: district)
        if ok { dismiss() }
    }
}
