import Foundation

enum WakeControlLayout: Equatable {
    case timed
    case indefinite
}

enum WakeControlAction: Equatable {
    case start
    case stop
}

enum IndefiniteActionPlacement: Equatable {
    case inline
}

struct IndefiniteParticle: Equatable {
    let progress: Double
    let verticalPosition: Double
    let thickness: Double
    let opacity: Double
}

enum IndefiniteParticleMotion {
    static let cycleDuration: TimeInterval = 1.2

    private struct Seed {
        let phase: Double
        let verticalPosition: Double
        let thickness: Double
        let maxOpacity: Double
    }

    private static let seeds = [
        Seed(phase: 0.00, verticalPosition: 0.28, thickness: 3.2, maxOpacity: 0.38),
        Seed(phase: 0.20, verticalPosition: 0.50, thickness: 2.6, maxOpacity: 0.30),
        Seed(phase: 0.41, verticalPosition: 0.68, thickness: 3.0, maxOpacity: 0.37),
        Seed(phase: 0.63, verticalPosition: 0.38, thickness: 2.4, maxOpacity: 0.28),
        Seed(phase: 0.82, verticalPosition: 0.76, thickness: 2.7, maxOpacity: 0.35)
    ]

    static func particles(at time: TimeInterval) -> [IndefiniteParticle] {
        let remainder = time.truncatingRemainder(dividingBy: cycleDuration)
        let normalizedTime = remainder >= 0 ? remainder : remainder + cycleDuration
        let phase = normalizedTime / cycleDuration

        return seeds.map { seed in
            let wrappedProgress = (seed.phase - phase).truncatingRemainder(dividingBy: 1)
            let progress = wrappedProgress >= 0 ? wrappedProgress : wrappedProgress + 1
            let fade = sin(progress * .pi)

            return IndefiniteParticle(
                progress: progress,
                verticalPosition: seed.verticalPosition,
                thickness: seed.thickness,
                opacity: fade * seed.maxOpacity
            )
        }
    }
}

struct IndefiniteControlLayout: Equatable {
    let actionPlacement: IndefiniteActionPlacement
    let infinityFontSize: CGFloat
    let symbolAreaHeight: CGFloat
    let particleVerticalOffset: CGFloat
    let verticalSpacing: CGFloat
    let statusActionSpacing: CGFloat

    static let compact = IndefiniteControlLayout(
        actionPlacement: .inline,
        infinityFontSize: 80,
        symbolAreaHeight: 84,
        particleVerticalOffset: 5,
        verticalSpacing: 5,
        statusActionSpacing: 10
    )
}

struct WakeControlPresentation: Equatable {
    let layout: WakeControlLayout
    let action: WakeControlAction

    init(duration: WakeDuration, isActive: Bool) {
        layout = duration == .indefinite ? .indefinite : .timed
        action = isActive ? .stop : .start
    }
}

enum KiplessLayout {
    static let popoverWidth: CGFloat = 384
    static let sessionPanelHeight: CGFloat = 180
    static let sessionPanelWidth: CGFloat = 180
    static let optionsPanelWidth: CGFloat = 204
    static let footerHeight: CGFloat = 36
    static let timerDiameter: CGFloat = 138

    static let optionsHorizontalPadding: CGFloat = 18
    static let optionsVerticalPadding: CGFloat = 8
    static let explanationLineHeight: CGFloat = 11
    static let explanationBottomPadding: CGFloat = 4
    static let modeOptionVerticalPadding: CGFloat = 4
    static let modeOptionSpacing: CGFloat = 5
    static let modeTitleLineHeight: CGFloat = 13
    static let modeSubtitleLineHeight: CGFloat = 11
    static let modeTextSpacing: CGFloat = 2
    static let minimumContentGap: CGFloat = 0
    static let durationRowHeight: CGFloat = 18
    static let durationPickerWidth: CGFloat = 96

    static func optionsContentHeight(
        explanationLines: Int,
        modeLineCounts: [(title: Int, subtitle: Int)]
    ) -> CGFloat {
        let modesHeight = modeLineCounts.reduce(CGFloat.zero) { total, lines in
            total
                + (modeOptionVerticalPadding * 2)
                + (CGFloat(lines.title) * modeTitleLineHeight)
                + (CGFloat(lines.subtitle) * modeSubtitleLineHeight)
                + modeTextSpacing
        }
        let modeSpacingHeight = CGFloat(max(modeLineCounts.count - 1, 0)) * modeOptionSpacing

        return (optionsVerticalPadding * 2)
            + (CGFloat(explanationLines) * explanationLineHeight)
            + explanationBottomPadding
            + modesHeight
            + modeSpacingHeight
            + minimumContentGap
            + durationRowHeight
    }
}
