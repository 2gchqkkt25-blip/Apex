//
//  TopShelfSettingsView.swift
//  Apex
//
//  Settings UI for configuring what content appears on the Apple TV Top Shelf
//  when the app is on the top row of the home screen.
//

import SwiftData
import SwiftUI

#if os(tvOS)

struct TopShelfSettingsView: View {
    @AppStorage(TopShelfSettings.contentModeKey, store: UserDefaults(suiteName: TopShelfSettings.appGroupID))
    private var selectedMode: String = TopShelfSettings.ContentMode.recentlyWatched.rawValue

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Top Shelf")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                Text("Choose what content appears on the Top Shelf when Apex is on the top row of your Apple TV home screen.")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                VStack(spacing: 0) {
                    ForEach(TopShelfSettings.ContentMode.allCases) { mode in
                        let isSelected = selectedMode == mode.rawValue
                        Button {
                            selectedMode = mode.rawValue
                            // Notify extension of change
                            notifyExtension()
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 24))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.displayTitle)
                                        .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
                                    Text(mode.description)
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(TVSettingsRowButtonStyle())
                    }
                }
            }
            .frame(maxWidth: TVSettingsMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 48)
            .padding(.vertical, 72)
        }
        .tvSettingsBackground()
    }

    private func notifyExtension() {
        // Write fresh data immediately when the user changes the setting
        TopShelfDataWriter.update(container: modelContext.container)
    }
}

#endif
