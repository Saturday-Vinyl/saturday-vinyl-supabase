//
//  FlipTimerWidgetLiveActivity.swift
//  FlipTimerWidget
//
//  Created by Dave Latham on 1/7/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

/// Attributes for the Live Activity.
/// IMPORTANT: This struct MUST be named exactly "LiveActivitiesAppAttributes"
/// for the live_activities Flutter plugin to work correctly.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    // ContentState must have appGroupId to match the plugin's internal structure
    public struct ContentState: Codable, Hashable {
        var appGroupId: String
    }

    var id = UUID()
}

/// Extension to handle prefixed keys for the live_activities plugin
extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}

/// Shared UserDefaults for accessing data from Flutter
let sharedDefault = UserDefaults(suiteName: "group.com.saturdayvinyl.consumer")!

/// Live Activity for displaying flip timer on Lock Screen and Dynamic Island.
@available(iOSApplicationExtension 16.1, *)
struct FlipTimerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // Read data from UserDefaults
            let albumTitle = sharedDefault.string(forKey: context.attributes.prefixedKey("albumTitle")) ?? "Unknown Album"
            let artist = sharedDefault.string(forKey: context.attributes.prefixedKey("artist")) ?? "Unknown Artist"
            let currentSide = sharedDefault.string(forKey: context.attributes.prefixedKey("currentSide")) ?? "A"
            let totalDurationSeconds = sharedDefault.integer(forKey: context.attributes.prefixedKey("totalDurationSeconds"))
            let startedAtTimestamp = sharedDefault.integer(forKey: context.attributes.prefixedKey("startedAtTimestamp"))
            let isNearFlip = sharedDefault.bool(forKey: context.attributes.prefixedKey("isNearFlip"))
            let isOvertime = sharedDefault.bool(forKey: context.attributes.prefixedKey("isOvertime"))

            // Calculate the end time for the countdown
            let startDate = Date(timeIntervalSince1970: Double(startedAtTimestamp) / 1000.0)
            let endDate = startDate.addingTimeInterval(Double(totalDurationSeconds))

            // Lock Screen / Banner UI
            LockScreenView(
                albumTitle: albumTitle,
                artist: artist,
                currentSide: currentSide,
                totalDurationSeconds: totalDurationSeconds,
                startDate: startDate,
                endDate: endDate,
                isNearFlip: isNearFlip,
                isOvertime: isOvertime
            )
            .activityBackgroundTint(Color(red: 0.886, green: 0.855, blue: 0.816)) // Saturday cream
            .activitySystemActionForegroundColor(Color(red: 0.247, green: 0.227, blue: 0.204)) // Saturday brown
        } dynamicIsland: { context in
            // Read data from UserDefaults
            let albumTitle = sharedDefault.string(forKey: context.attributes.prefixedKey("albumTitle")) ?? "Unknown Album"
            let artist = sharedDefault.string(forKey: context.attributes.prefixedKey("artist")) ?? "Unknown Artist"
            let currentSide = sharedDefault.string(forKey: context.attributes.prefixedKey("currentSide")) ?? "A"
            let totalDurationSeconds = sharedDefault.integer(forKey: context.attributes.prefixedKey("totalDurationSeconds"))
            let startedAtTimestamp = sharedDefault.integer(forKey: context.attributes.prefixedKey("startedAtTimestamp"))
            let isNearFlip = sharedDefault.bool(forKey: context.attributes.prefixedKey("isNearFlip"))
            let isOvertime = sharedDefault.bool(forKey: context.attributes.prefixedKey("isOvertime"))

            // Calculate the end time for the countdown
            let startDate = Date(timeIntervalSince1970: Double(startedAtTimestamp) / 1000.0)
            let endDate = startDate.addingTimeInterval(Double(totalDurationSeconds))
            let now = Date()
            let timerRange = now...endDate

            return DynamicIsland {
                // Expanded UI (when long-pressed)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        // Vinyl record icon
                        Image(systemName: "record.circle")
                            .font(.title2)
                            .foregroundColor(isNearFlip ? .orange : .primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Side \(currentSide)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(albumTitle)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if isOvertime || now > endDate {
                            Text("FLIP!")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        } else {
                            Text(timerInterval: timerRange, countsDown: true)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(isNearFlip ? .orange : .primary)
                            Text("remaining")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        // Progress indicator
                        let elapsed = now.timeIntervalSince(startDate)
                        let progress = totalDurationSeconds > 0 ? min(1.0, elapsed / Double(totalDurationSeconds)) : 0.0
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(isNearFlip ? .orange : Color(red: 0.247, green: 0.227, blue: 0.204))
                            .frame(width: 100)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Compact leading (pill left side)
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                        .font(.caption)
                        .foregroundColor(isNearFlip ? .orange : .primary)
                    Text("Side \(currentSide)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            } compactTrailing: {
                // Compact trailing (pill right side)
                if isOvertime || now > endDate {
                    Text("FLIP!")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                } else {
                    Text(timerInterval: timerRange, countsDown: true)
                        .font(.caption)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .frame(width: 40)
                        .foregroundColor(isNearFlip ? .orange : .primary)
                }
            } minimal: {
                // Minimal (when other activities are present)
                if isOvertime || now > endDate || isNearFlip {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "record.circle")
                        .font(.caption)
                }
            }
        }
    }
}

/// Lock Screen Live Activity view.
struct LockScreenView: View {
    let albumTitle: String
    let artist: String
    let currentSide: String
    let totalDurationSeconds: Int
    let startDate: Date
    let endDate: Date
    let isNearFlip: Bool
    let isOvertime: Bool

    var body: some View {
        let now = Date()
        let timerRange = now...endDate
        let isExpired = now > endDate

        HStack(spacing: 12) {
            // Vinyl record icon
            ZStack {
                Circle()
                    .fill(Color(red: 0.247, green: 0.227, blue: 0.204))
                    .frame(width: 50, height: 50)

                Circle()
                    .fill(Color(red: 0.886, green: 0.855, blue: 0.816))
                    .frame(width: 16, height: 16)

                // Spinning indicator when playing
                Circle()
                    .stroke(Color(red: 0.886, green: 0.855, blue: 0.816).opacity(0.5), lineWidth: 1)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Side \(currentSide)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.247, green: 0.227, blue: 0.204))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.247, green: 0.227, blue: 0.204).opacity(0.15))
                        )

                    Spacer()

                    if isOvertime || isExpired {
                        Text("Time to flip!")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    } else {
                        // Real-time countdown using SwiftUI's built-in timer
                        Text(timerInterval: timerRange, countsDown: true)
                            .font(.title2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(isNearFlip ? .orange : Color(red: 0.247, green: 0.227, blue: 0.204))
                    }
                }

                Text(albumTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(red: 0.247, green: 0.227, blue: 0.204))
                    .lineLimit(1)

                Text(artist)
                    .font(.caption)
                    .foregroundColor(Color(red: 0.247, green: 0.227, blue: 0.204).opacity(0.7))
                    .lineLimit(1)

                // Progress bar - updates based on timer
                let elapsed = now.timeIntervalSince(startDate)
                let progress = totalDurationSeconds > 0 ? min(1.0, elapsed / Double(totalDurationSeconds)) : 0.0
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.247, green: 0.227, blue: 0.204).opacity(0.2))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(isNearFlip || isExpired ? Color.orange : Color(red: 0.247, green: 0.227, blue: 0.204))
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(16)
    }
}
