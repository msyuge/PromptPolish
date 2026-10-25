import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Версия", value: Bundle.main.shortVersion)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
