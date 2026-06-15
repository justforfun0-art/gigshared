import SwiftUI
import Shared

/// The visual content of one job card (port of Android's SwipeCard body):
/// job-type tag + share, big green PAY, time/date fact pills, title, location,
/// 3-line description, and skill chips — in the same decision-first order.
struct SwipeCardContent: View {
    let job: Job

    private let payGreen = Color(red: 0x04/255, green: 0x78/255, blue: 0x57/255)
    private let payIcon = Color(red: 0x05/255, green: 0x96/255, blue: 0x69/255)
    private let subtle = Color(red: 0x6B/255, green: 0x72/255, blue: 0x80/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let salary = job.salaryRange, !salary.isEmpty {
                Spacer().frame(height: 4)
                HStack(alignment: .bottom, spacing: 2) {
                    Image(systemName: "indianrupeesign")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(payIcon)
                    Text(salary)
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(payGreen)
                }
                Text("Total pay for this gig")
                    .font(.caption2).foregroundStyle(subtle)
                Spacer().frame(height: 18)
            }

            HStack(spacing: 10) {
                if let time = formatTimeRange(job.startTime, job.endTime) {
                    FactPill(icon: "clock", text: time)
                }
                if let date = formatJobDate(job.jobDate) {
                    FactPill(icon: "calendar", text: date)
                }
            }

            Spacer().frame(height: 16)

            Text(job.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer().frame(height: 6)

            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0x9C/255, green: 0xA3/255, blue: 0xAF/255))
                Text(locationText)
                    .font(.caption).foregroundStyle(subtle)
            }

            Spacer().frame(height: 14)

            Text(job.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 14)

            if !job.skillsRequired.isEmpty {
                skillChips
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color(red: 0xE5/255, green: 0xE7/255, blue: 0xEB/255), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }

    private var header: some View {
        HStack {
            Spacer()
            Text(jobTypeDisplay)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(red: 0x37/255, green: 0x41/255, blue: 0x51/255))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(red: 0xF3/255, green: 0xF4/255, blue: 0xF6/255), in: Capsule())
        }
    }

    private var locationText: String {
        [job.district, job.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var jobTypeDisplay: String {
        switch job.jobType.uppercased() {
        case "WEEKEND": return "Weekend"
        case "WEEKDAY": return "Weekday"
        default: return job.jobType.capitalized
        }
    }

    private var skillChips: some View {
        // Up to 3 skills as small chips (SwiftUI has no FlowRow; a single wrap row).
        HStack(spacing: 6) {
            ForEach(Array(job.skillsRequired.prefix(3)), id: \.self) { skill in
                Text(skill)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0x37/255, green: 0x41/255, blue: 0x51/255))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(red: 0xF3/255, green: 0xF4/255, blue: 0xF6/255), in: Capsule())
            }
            if job.skillsRequired.count > 3 {
                Text("+\(job.skillsRequired.count - 3)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// A small icon+text pill used for time/date facts (Android's FactPill).
struct FactPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.primary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(red: 0xF9/255, green: 0xFA/255, blue: 0xFB/255), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Formatting (mirrors Android's formatTimeRange / formatJobDate)

/// "09:00"+"17:00" → "9:00 AM – 5:00 PM"; nil when both absent.
func formatTimeRange(_ start: String?, _ end: String?) -> String? {
    let s = formatClock(start)
    let e = formatClock(end)
    switch (s, e) {
    case let (s?, e?): return "\(s) – \(e)"
    case let (s?, nil): return s
    case let (nil, e?): return e
    default: return nil
    }
}

private func formatClock(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    let parts = raw.split(separator: ":")
    guard let h = Int(parts.first ?? "") else { return raw }
    let m = parts.count > 1 ? String(parts[1]).prefix(2) : "00"
    let ampm = h >= 12 ? "PM" : "AM"
    let h12 = h % 12 == 0 ? 12 : h % 12
    return "\(h12):\(m) \(ampm)"
}

/// "2026-06-20" → "Jun 20"; passes through anything unparseable.
func formatJobDate(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    let iso = DateFormatter()
    iso.dateFormat = "yyyy-MM-dd"
    iso.locale = Locale(identifier: "en_US_POSIX")
    guard let date = iso.date(from: String(raw.prefix(10))) else { return raw }
    let out = DateFormatter()
    out.dateFormat = "MMM d"
    out.locale = Locale(identifier: "en_US")
    return out.string(from: date)
}
