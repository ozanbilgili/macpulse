import Foundation

/// Locale-aware number pieces for display text. Words come from the app's string
/// catalog through `Bundle.main`; digits and the percent sign follow the user's region.
public enum LocalizedFormat {
    /// `32%` in English, `%32` in Turkish.
    public static func percent(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.percent.locale(locale))
    }

    /// `value` is already a percentage (`32.5` → `32.5%`).
    public static func percent(_ value: Double, digits: Int = 0, locale: Locale = .current) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(digits)).locale(locale))
    }
}
