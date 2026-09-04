import Foundation
@testable import Apex
import Testing

@MainActor
struct SubtitleSettingsTests {
    @Test func `missing enabled key is on`() {
        let defaults = UserDefaults(suiteName: "test.subtitles.missing.\(UUID().uuidString)")!
        defaults.removeObject(forKey: SubtitleSettings.enabledKey)
        #expect(SubtitleSettings.enabledDefault)
        #expect(SubtitleSettings.isEnabled(in: defaults))
    }

    @Test func `explicit off is respected`() {
        let defaults = UserDefaults(suiteName: "test.subtitles.off.\(UUID().uuidString)")!
        defaults.set(false, forKey: SubtitleSettings.enabledKey)
        #expect(SubtitleSettings.isEnabled(in: defaults) == false)
    }

    @Test func `explicit on is respected`() {
        let defaults = UserDefaults(suiteName: "test.subtitles.on.\(UUID().uuidString)")!
        defaults.set(true, forKey: SubtitleSettings.enabledKey)
        #expect(SubtitleSettings.isEnabled(in: defaults))
    }

    @Test func `apply default writes true when unset`() {
        let defaults = UserDefaults(suiteName: "test.subtitles.apply.\(UUID().uuidString)")!
        defaults.removeObject(forKey: SubtitleSettings.enabledKey)
        SubtitleSettings.applyEnabledDefaultIfNeeded(in: defaults)
        #expect(defaults.bool(forKey: SubtitleSettings.enabledKey))
    }

    @Test func `apply default does not overwrite off`() {
        let defaults = UserDefaults(suiteName: "test.subtitles.keepoff.\(UUID().uuidString)")!
        defaults.set(false, forKey: SubtitleSettings.enabledKey)
        SubtitleSettings.applyEnabledDefaultIfNeeded(in: defaults)
        #expect(defaults.bool(forKey: SubtitleSettings.enabledKey) == false)
    }
}
