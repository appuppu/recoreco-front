import SwiftUI

// MARK: - アプリ全体のテーマカラー設定
/// ここを変更するだけで、アプリ全体の色が変わります
enum AppTheme {
    // MARK: - グラデーションカラー設定（6桁のHEXコードで指定）
    // 色を変えたい場合はここの値を変更してください

    /// グラデーション開始色（明るい方）
    static let gradientStartHex = "cc208e"  // ワインレッド（明）

    /// グラデーション終了色（暗い方）
    static let gradientEndHex = "6713d2"    // ワインレッド（暗）

    // MARK: - 計算プロパティ（変更不要）

    /// グラデーション開始色
    static var gradientStartColor: Color {
        Color(hex: gradientStartHex)
    }

    /// グラデーション終了色
    static var gradientEndColor: Color {
        Color(hex: gradientEndHex)
    }

    /// 横方向のグラデーション
    static var horizontalGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 縦方向のグラデーション
    static var verticalGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [gradientStartColor, gradientEndColor]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// リフレッシュインジケーター用の色
    static var tintColor: Color {
        gradientStartColor
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: 1
        )
    }
}
