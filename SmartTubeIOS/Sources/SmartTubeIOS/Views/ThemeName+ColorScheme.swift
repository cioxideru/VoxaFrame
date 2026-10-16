import SmartTubeIOSCore
import SwiftUI

extension AppSettings.ThemeName {
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
