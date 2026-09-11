import Foundation

enum KiplessLayout {
    static let popoverWidth: CGFloat = 360
    static let sessionPanelHeight: CGFloat = 180
    static let footerHeight: CGFloat = 36
    static let timerDiameter: CGFloat = 138

    static let optionsHorizontalPadding: CGFloat = 18
    static let optionsVerticalPadding: CGFloat = 8
    static let explanationLineHeight: CGFloat = 11
    static let explanationBottomPadding: CGFloat = 4
    static let modeOptionVerticalPadding: CGFloat = 3
    static let modeTitleLineHeight: CGFloat = 13
    static let modeSubtitleLineHeight: CGFloat = 11
    static let modeTextSpacing: CGFloat = 2
    static let dividerHeight: CGFloat = 1
    static let minimumContentGap: CGFloat = 4
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
        let dividersHeight = CGFloat(max(modeLineCounts.count - 1, 0)) * dividerHeight

        return (optionsVerticalPadding * 2)
            + (CGFloat(explanationLines) * explanationLineHeight)
            + explanationBottomPadding
            + modesHeight
            + dividersHeight
            + minimumContentGap
            + durationRowHeight
    }
}
