import SwiftUI

enum TimeEstimatePresentation: Equatable, Sendable {
    case runtime
    case untilFull
    case fullyCharged

    static func forSnapshot(_ snapshot: PowerSnapshot) -> TimeEstimatePresentation {
        if !snapshot.externalConnected || snapshot.flowMode == .underpowered {
            return .runtime
        }
        if snapshot.fullyCharged || (!snapshot.isCharging && snapshot.percent >= 99.5) {
            return .fullyCharged
        }
        return .untilFull
    }
}

struct TimeEstimateRow: View {
    var snapshot: PowerSnapshot
    var language: AppLanguage

    var body: some View {
        let presentation = TimeEstimatePresentation.forSnapshot(snapshot)
        labeledRow(
            title: title(for: presentation),
            value: value(for: presentation)
        )
        .font(.callout)
    }

    private func title(for presentation: TimeEstimatePresentation) -> String {
        switch presentation {
        case .runtime:
            Localization.string("estimate.runtime", language: language)
        case .untilFull:
            Localization.string("estimate.full", language: language)
        case .fullyCharged:
            Localization.string("estimate.charged", language: language)
        }
    }

    private func value(for presentation: TimeEstimatePresentation) -> String {
        switch presentation {
        case .runtime:
            runtimeText
        case .untilFull:
            fullText
        case .fullyCharged:
            ""
        }
    }

    private var runtimeText: String {
        guard let minutes = snapshot.timeToEmptyMinutes else {
            return Localization.string("estimate.calculating", language: language)
        }
        return Localization.string(
            "estimate.about %@",
            language: language,
            DurationFormatter.string(minutes: minutes, language: language)
        )
    }

    private var fullText: String {
        guard snapshot.isCharging, let minutes = snapshot.timeToFullMinutes else {
            return "—"
        }
        return Localization.string(
            "estimate.about %@",
            language: language,
            DurationFormatter.string(minutes: minutes, language: language)
        )
    }

    private func labeledRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .autoFittingCaption(minimumScale: 0.7)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .autoFittingCaption(minimumScale: 0.65)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

enum DurationFormatter {
    static func string(minutes: Int, language: AppLanguage = .system) -> String {
        let hours = minutes / 60
        let remain = minutes % 60
        if hours > 0 && remain > 0 {
            return Localization.string("duration.hoursMinutes %lld %lld", language: language, Int64(hours), Int64(remain))
        }
        if hours > 0 {
            return Localization.string("duration.hours %lld", language: language, Int64(hours))
        }
        return Localization.string("duration.minutes %lld", language: language, Int64(remain))
    }
}
