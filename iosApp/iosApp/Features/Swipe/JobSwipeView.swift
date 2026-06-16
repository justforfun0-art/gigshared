import SwiftUI
import Shared

/// Tinder-style job-swipe deck — the iOS port of Android's JobSwipeScreen.
/// A stack of cards (front = top job); drag the top card horizontally:
/// right past the commit threshold (or a fast flick) applies, left skips. The
/// card rotates with the drag, shows APPLY/SKIP stamps, tints the screen with
/// intent, and confetti bursts on an apply.
struct JobSwipeView: View {

    @StateObject private var viewModel: JobSwipeViewModel
    /// Drag offset of the top card (the only card that moves).
    @State private var drag: CGSize = .zero
    @State private var flyOff: CGSize? = nil
    @State private var confetti = false

    private let green = Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)
    private let red = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)

    init(jobs: any JobRepository, applications: any ApplicationRepository,
         employeeId: String, profile: (any ProfileRepository)? = nil) {
        _viewModel = StateObject(wrappedValue: JobSwipeViewModel(
            jobs: jobs, applications: applications, employeeId: employeeId, profile: profile
        ))
    }

    var body: some View {
        ZStack {
            screenTint.ignoresSafeArea()

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Finding gigs near you…")
            case .failed(let message):
                retry(message)
            case .loaded:
                if viewModel.isEmpty {
                    emptyDeck
                } else {
                    deck
                    bottomButtons
                }
            }

            if let chip = viewModel.lastAction {
                actionChip(chip)
            }
            if confetti {
                ConfettiView().allowsHitTesting(false).transition(.opacity)
            }
        }
        .task { await viewModel.load() }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.jobs.map(\.id))
    }

    // MARK: - Deck

    private var deck: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Render the front 3 cards; the back ones are scaled + nudged down.
            ZStack {
                ForEach(Array(viewModel.jobs.prefix(3).enumerated().reversed()), id: \.element.id) { idx, job in
                    let isTop = idx == 0
                    SwipeCardContent(job: job)
                        .frame(width: w * 0.92, height: geo.size.height * 0.86)
                        .scaleEffect(1 - CGFloat(idx) * 0.04)
                        .offset(y: CGFloat(idx) * 14)
                        .offset(isTop ? currentOffset : .zero)
                        .rotationEffect(isTop ? .degrees(Double(currentOffset.width / 20).clamped(-15, 15)) : .zero)
                        .overlay { if isTop { stamps(width: w) } }
                        .gesture(isTop ? dragGesture(cardWidth: w * 0.92) : nil)
                        .allowsHitTesting(isTop && viewModel.applyingJobId == nil)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 90)
    }

    /// Effective top-card offset (live drag, or the committed fly-off).
    private var currentOffset: CGSize { flyOff ?? drag }

    private func dragGesture(cardWidth: CGFloat) -> some Gesture {
        // Commit at 28% of card width (floor 90pt); a fast flick also commits.
        let threshold = max(cardWidth * 0.28, 90)
        return DragGesture()
            .onChanged { value in
                guard viewModel.applyingJobId == nil else { return }
                // Horizontal-dominant only (ignore vertical scroll).
                if abs(value.translation.width) > abs(value.translation.height) {
                    drag = CGSize(width: value.translation.width, height: value.translation.height * 0.15)
                }
            }
            .onEnded { value in
                guard viewModel.applyingJobId == nil else { return }
                let dx = value.translation.width
                let vx = value.predictedEndTranslation.width - dx
                let committedRight = dx > threshold || vx > 250
                let committedLeft = dx < -threshold || vx < -250
                if committedRight {
                    commit(toRight: true)
                } else if committedLeft {
                    commit(toRight: false)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { drag = .zero }
                }
            }
    }

    private func commit(toRight: Bool) {
        let dest = CGSize(width: toRight ? 1500 : -1500, height: drag.height)
        withAnimation(.easeOut(duration: 0.25)) { flyOff = dest }
        if toRight {
            withAnimation { confetti = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            viewModel.swipeRight()
            Task { try? await Task.sleep(nanoseconds: 900_000_000); withAnimation { confetti = false } }
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.swipeLeft()
        }
        // Reset for the next card after the fly-off finishes.
        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            drag = .zero; flyOff = nil
        }
    }

    // MARK: - Stamps + tint

    @ViewBuilder
    private func stamps(width: CGFloat) -> some View {
        let threshold = max(width * 0.92 * 0.28, 90)
        let right = (currentOffset.width / threshold).clamped(0, 1)
        let left = (-currentOffset.width / threshold).clamped(0, 1)
        ZStack {
            stamp(text: "APPLY", color: green, rotation: -18)
                .opacity(right)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            stamp(text: "SKIP", color: red, rotation: 18)
                .opacity(left)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(28)
        }
    }

    private func stamp(text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 32, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(rotation))
    }

    private var screenTint: Color {
        let dx = currentOffset.width
        if dx > 0 { return green.opacity(Double(dx / 600).clamped(0, 0.18)) }
        if dx < 0 { return red.opacity(Double(-dx / 600).clamped(0, 0.18)) }
        return .clear
    }

    // MARK: - Bottom buttons

    private var bottomButtons: some View {
        VStack {
            Spacer()
            HStack(spacing: 48) {
                circleButton(icon: "xmark", tint: red) {
                    guard viewModel.applyingJobId == nil else { return }
                    commit(toRight: false)
                }
                circleButton(icon: "checkmark", tint: green) {
                    guard viewModel.applyingJobId == nil else { return }
                    commit(toRight: true)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func circleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(Color(.systemBackground), in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.4), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
    }

    // MARK: - Chips, empty, retry

    private func actionChip(_ chip: (text: String, isApply: Bool)) -> some View {
        VStack {
            Text(chip.text)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background((chip.isApply ? green : red), in: Capsule())
                .shadow(radius: 4)
                .padding(.top, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyDeck: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(green)
            Text(L("ios_you_re_all_caught_up")).font(.headline)
            Text(L("ios_no_more_gigs_to_swipe_right_now_check_ba"))
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L("refresh")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func retry(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
        }.padding()
    }
}

private extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
