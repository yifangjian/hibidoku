import SwiftUI

// MARK: - Reader Theme

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, dark, sepia

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "ライト"
        case .dark:  "ダーク"
        case .sepia: "セピア"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .light: Color(.systemBackground)
        case .dark:  Color(red: 0.1, green: 0.1, blue: 0.1)
        case .sepia: Color(red: 0.96, green: 0.93, blue: 0.86)
        }
    }

    var textColor: Color {
        switch self {
        case .light: Color(.label)
        case .dark:  Color(white: 0.9)
        case .sepia: Color(red: 0.35, green: 0.25, blue: 0.15)
        }
    }

    var uiBackgroundColor: UIColor {
        switch self {
        case .light: .systemBackground
        case .dark:  UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        case .sepia: UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1)
        }
    }

    var uiTextColor: UIColor {
        switch self {
        case .light: .label
        case .dark:  UIColor(white: 0.9, alpha: 1)
        case .sepia: UIColor(red: 0.35, green: 0.25, blue: 0.15, alpha: 1)
        }
    }

    var iconName: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark:  "moon.fill"
        case .sepia: "book.fill"
        }
    }
}

// MARK: - Font Size

enum ReaderFontSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:  "小"
        case .medium: "中"
        case .large:  "大"
        }
    }

    var basePoints: CGFloat {
        switch self {
        case .small:  18
        case .medium: 22
        case .large:  28
        }
    }

    var rubyFactor: CGFloat { 0.5 }

    var lineHeightMultiple: CGFloat {
        switch self {
        case .small:  1.9
        case .medium: 1.8
        case .large:  1.7
        }
    }
}

// MARK: - Settings Model

@Observable
final class ReaderSettingsModel {
    var theme: ReaderTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "reader_theme") }
    }
    var fontSize: ReaderFontSize {
        didSet { UserDefaults.standard.set(fontSize.rawValue, forKey: "reader_fontSize") }
    }
    var brightness: Double {
        didSet {
            UserDefaults.standard.set(brightness, forKey: "reader_brightness")
            UIScreen.main.brightness = CGFloat(brightness)
        }
    }

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: "reader_theme") ?? ReaderTheme.light.rawValue
        self.theme = ReaderTheme(rawValue: themeRaw) ?? .light

        let sizeRaw = UserDefaults.standard.string(forKey: "reader_fontSize") ?? ReaderFontSize.medium.rawValue
        self.fontSize = ReaderFontSize(rawValue: sizeRaw) ?? .medium

        let saved = UserDefaults.standard.object(forKey: "reader_brightness") as? Double
        self.brightness = saved ?? Double(UIScreen.main.brightness)
    }
}
