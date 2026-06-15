import SwiftUI
import SafariServices

/// Presents a hosted URL (the Cashfree checkout link) inside an in-app Safari
/// view. The native Cashfree SDK checkout is out of scope; the hosted link is
/// the portable path. After the employer completes (or abandons) checkout they
/// dismiss this and pull-to-refresh Payments to re-read status.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
