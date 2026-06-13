//
//  FlipTimerWidgetLiveActivity.swift
//  FlipTimerWidget
//
//  Created by Dave Latham on 1/7/26.
//

import ActivityKit
import CoreText
import WidgetKit
import SwiftUI
import UIKit

/// Attributes for the Live Activity.
/// IMPORTANT: This struct MUST be named exactly "LiveActivitiesAppAttributes"
/// for the live_activities Flutter plugin to work correctly.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
    }

    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}

let sharedDefault = UserDefaults(suiteName: "group.com.saturdayvinyl.consumer")!

// MARK: - Saturday tokens

/// Mirrors `lib/config/tokens/colors.dart`. Hex values are duplicated here
/// because widget extensions can't read Dart tokens at runtime.
///
/// The light tones (`paper`, `ink`, …) are for surfaces we own — the lock
/// screen tint and any rendering on a paper background. The Dynamic Island
/// is always painted on the system's black pill, so its foreground must
/// use the dark-mode tones (`onDarkInk`, `onDarkInkSecondary`, …) which
/// are bright enough to read against black. These mirror
/// `SaturdayColorTokens.dark` in `lib/config/tokens/colors.dart`.
enum SaturdayPalette {
    static let paper = Color(red: 0xF6 / 255, green: 0xF5 / 255, blue: 0xF2 / 255)
    static let ink = Color(red: 0x1A / 255, green: 0x18 / 255, blue: 0x17 / 255)
    static let inkSecondary = Color(red: 0x5A / 255, green: 0x58 / 255, blue: 0x54 / 255)
    static let inkTertiary = Color(red: 0x8A / 255, green: 0x88 / 255, blue: 0x84 / 255)
    static let borderQuiet = Color(red: 0xE8 / 255, green: 0xE6 / 255, blue: 0xE0 / 255)

    static let onDarkInk = Color(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEC / 255)
    static let onDarkInkSecondary = Color(red: 0xB4 / 255, green: 0xB2 / 255, blue: 0xAC / 255)
    static let onDarkInkTertiary = Color(red: 0x7A / 255, green: 0x78 / 255, blue: 0x74 / 255)
}

/// Saturday brand fonts. Bundled into the widget target via UIAppFonts
/// in Info.plist (see `ios/FlipTimerWidget/Fonts/`).
///
/// Inter Tight and JetBrains Mono are weight-variable; Source Serif 4
/// Italic is opsz+wght variable. The PostScript names below address the
/// fonts' default instance — we vary `wght` via the variation axis on
/// the eyebrow (which needs medium 500) and otherwise let the regular
/// instance carry.
enum SaturdayType {
    static let eyebrow = sans(size: 11, weight: 500)
    static let body = sans(size: 14)
    static let artist = sans(size: 13)
    static let trackTitle = sans(size: 13)
    static let mono = Font.custom("JetBrainsMono-Regular", size: 13)
    static let trackPosition = Font.custom("JetBrainsMono-Regular", size: 13)
    static let countdownLockScreen = Font.custom("JetBrainsMono-Regular", size: 32)
    static let countdownExpanded = Font.custom("JetBrainsMono-Regular", size: 20)
    static let countdownCompact = Font.custom("JetBrainsMono-Regular", size: 14)
    static let titleListeningLockScreen = Font.custom("SourceSerif4Italic-Italic", size: 22)
    static let titleListeningExpanded = Font.custom("SourceSerif4Italic-Italic", size: 14)
    static let flipMoment = Font.custom("SourceSerif4Italic-Italic", size: 32)
    static let flipMomentExpanded = Font.custom("SourceSerif4Italic-Italic", size: 20)
    static let flipMomentCompact = Font.custom("SourceSerif4Italic-Italic", size: 14)

    /// 'wght' OpenType axis tag, packed as FourCharCode for CoreText.
    private static let wghtAxisTag = 0x77676874  // 'w' 'g' 'h' 't'

    /// Build an Inter Tight font at the given size and variable weight.
    /// Goes through UIFontDescriptor so the wght axis is set explicitly
    /// — `Font.custom(...).weight(...)` doesn't reliably drive the
    /// variable axis on variable fonts.
    private static func sans(size: CGFloat, weight: CGFloat = 400) -> Font {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "InterTight-Regular",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                wghtAxisTag: weight
            ],
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }
}

// MARK: - Live Activity

@available(iOSApplicationExtension 16.1, *)
struct FlipTimerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            let data = LiveData(context: context)
            LockScreenView(data: data)
                .activityBackgroundTint(SaturdayPalette.paper)
                .activitySystemActionForegroundColor(SaturdayPalette.ink)
        } dynamicIsland: { context in
            let data = LiveData(context: context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Side \(data.currentSide)")
                            .font(SaturdayType.eyebrow)
                            .foregroundColor(SaturdayPalette.onDarkInkTertiary)
                        Text(data.albumTitle)
                            .font(SaturdayType.titleListeningExpanded)
                            .foregroundColor(SaturdayPalette.onDarkInk)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if data.isAtFlipMoment {
                        Text("flip")
                            .font(SaturdayType.flipMomentExpanded)
                            .foregroundColor(SaturdayPalette.onDarkInk)
                    } else {
                        Text(timerInterval: data.timerRange, countsDown: true)
                            .font(SaturdayType.countdownExpanded)
                            .monospacedDigit()
                            .foregroundColor(SaturdayPalette.onDarkInk)
                            .multilineTextAlignment(.trailing)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if !data.currentTrackTitle.isEmpty {
                        HStack(spacing: 8) {
                            Text(data.currentTrackPosition)
                                .font(SaturdayType.trackPosition)
                                .foregroundColor(SaturdayPalette.onDarkInkSecondary)
                            Text(data.currentTrackTitle)
                                .font(SaturdayType.trackTitle)
                                .foregroundColor(SaturdayPalette.onDarkInkSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.top, 4)
                    } else {
                        HStack {
                            Text(data.artist)
                                .font(SaturdayType.artist)
                                .foregroundColor(SaturdayPalette.onDarkInkSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                Text("Side \(data.currentSide)")
                    .font(SaturdayType.eyebrow)
                    .foregroundColor(SaturdayPalette.onDarkInkSecondary)
            } compactTrailing: {
                if data.isAtFlipMoment {
                    Text("flip")
                        .font(SaturdayType.flipMomentCompact)
                        .foregroundColor(SaturdayPalette.onDarkInk)
                } else {
                    Text(timerInterval: data.timerRange, countsDown: true)
                        .font(SaturdayType.countdownCompact)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                        .foregroundColor(SaturdayPalette.onDarkInk)
                }
            } minimal: {
                if data.isAtFlipMoment {
                    Circle()
                        .stroke(SaturdayPalette.onDarkInk, lineWidth: 1)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(SaturdayPalette.onDarkInk)
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
}

// MARK: - Lock screen

struct LockScreenView: View {
    let data: LiveData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Side \(data.currentSide)")
                .font(SaturdayType.eyebrow)
                .foregroundColor(SaturdayPalette.inkTertiary)

            if data.isAtFlipMoment {
                Text("Flip the record.")
                    .font(SaturdayType.flipMoment)
                    .foregroundColor(SaturdayPalette.ink)
            } else {
                Text(timerInterval: data.timerRange, countsDown: true)
                    .font(SaturdayType.countdownLockScreen)
                    .monospacedDigit()
                    .foregroundColor(SaturdayPalette.ink)
            }

            Text(data.albumTitle)
                .font(SaturdayType.titleListeningLockScreen)
                .foregroundColor(SaturdayPalette.ink)
                .lineLimit(1)

            Text(data.artist)
                .font(SaturdayType.artist)
                .foregroundColor(SaturdayPalette.inkSecondary)
                .lineLimit(1)

            if !data.currentTrackTitle.isEmpty {
                HStack(spacing: 8) {
                    Text(data.currentTrackPosition)
                        .font(SaturdayType.trackPosition)
                        .foregroundColor(SaturdayPalette.inkSecondary)
                    Text(data.currentTrackTitle)
                        .font(SaturdayType.trackTitle)
                        .foregroundColor(SaturdayPalette.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

// MARK: - Data

/// One read of the shared-defaults state, computed once per widget render.
struct LiveData {
    let albumTitle: String
    let artist: String
    let currentSide: String
    let currentTrackTitle: String
    let currentTrackPosition: String
    let startDate: Date
    let endDate: Date
    let isOvertime: Bool

    init(context: ActivityViewContext<LiveActivitiesAppAttributes>) {
        let attrs = context.attributes
        self.albumTitle = sharedDefault.string(forKey: attrs.prefixedKey("albumTitle")) ?? ""
        self.artist = sharedDefault.string(forKey: attrs.prefixedKey("artist")) ?? ""
        self.currentSide = sharedDefault.string(forKey: attrs.prefixedKey("currentSide")) ?? "A"
        self.currentTrackTitle = sharedDefault.string(forKey: attrs.prefixedKey("currentTrackTitle")) ?? ""
        self.currentTrackPosition = sharedDefault.string(forKey: attrs.prefixedKey("currentTrackPosition")) ?? ""
        self.isOvertime = sharedDefault.bool(forKey: attrs.prefixedKey("isOvertime"))

        let totalDurationSeconds = sharedDefault.integer(forKey: attrs.prefixedKey("totalDurationSeconds"))
        let startedAtTimestamp = sharedDefault.integer(forKey: attrs.prefixedKey("startedAtTimestamp"))
        self.startDate = Date(timeIntervalSince1970: Double(startedAtTimestamp) / 1000.0)
        self.endDate = startDate.addingTimeInterval(Double(totalDurationSeconds))
    }

    var timerRange: ClosedRange<Date> {
        let now = Date()
        return now...endDate
    }

    var isAtFlipMoment: Bool {
        isOvertime || Date() > endDate
    }
}
