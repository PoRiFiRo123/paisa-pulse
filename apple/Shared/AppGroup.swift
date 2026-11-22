import Foundation

/// The App Group shared by the app and its widget.
/// SideStore / AltStore re-sign with a free Apple ID and rename the group
/// (group.com.paisapulse.app → group.com.paisapulse.app.<TEAMID>); they list the real name in
/// Info.plist › ALTAppGroups.
enum AppGroup {
  static let base = "group.com.paisapulse.app"

  static let id: String = resolve(Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? [])

  static func resolve(_ groups: [String]) -> String {
    groups.first(where: { $0 == base }) ?? groups.first(where: { $0.hasPrefix(base + ".") }) ?? base
  }

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
  }

  /// Preferences live here so the widget sees them too.
  static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}
