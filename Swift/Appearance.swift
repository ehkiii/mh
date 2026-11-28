import SwiftUI

/// Light / dark choice from Settings. "Default" follows the device.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Default"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "don't override": follow the device setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
