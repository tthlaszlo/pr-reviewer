import SwiftUI

private struct ShowBuddySettingsKey: FocusedValueKey {
    typealias Value = () -> Void
}
extension FocusedValues {
    var showBuddySettings: (() -> Void)? {
        get { self[ShowBuddySettingsKey.self] }
        set { self[ShowBuddySettingsKey.self] = newValue }
    }
}

struct GitHubSettingsCommands: Commands {
    @FocusedValue(\.showBuddySettings) private var showSettings
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { showSettings?() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(showSettings == nil)
        }
    }
}
