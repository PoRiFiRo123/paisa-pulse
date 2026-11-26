import Foundation

/// The App Group shared by the app and its widget.
/// SideStore / AltStore re-sign with a free Apple ID and rename the group
/// (group.com.paisapulse.app → group.com.paisapulse.app.<TEAMID>); they list the real name in
/// Info.plist › ALTAppGroups.
enum AppGroup {
  static let base = "group.com.paisapulse.app"

  /// Every re-signing tool names the group differently, and some (iloader) only write ALTAppGroups into the app, not into
  /// its extensions. So also read the groups this bundle is really signed with (embedded.mobileprovision), and prefer a
  /// group whose container actually exists.
  static let id: String = {
    let candidates = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []) + profileGroups()
    let usable = candidates.filter { $0 == base || $0.hasPrefix(base + ".") }
    return usable.first(where: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil })
      ?? resolve(candidates)
  }()

  static func resolve(_ groups: [String]) -> String {
    groups.first(where: { $0 == base }) ?? groups.first(where: { $0.hasPrefix(base + ".") }) ?? base
  }

  /// App groups from the provisioning profile inside this bundle (the app's or the extension's own).
  static func profileGroups(_ bundle: Bundle = .main) -> [String] {
    guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url) else { return [] }
    return groups(fromProfile: data)
  }

  /// The profile is a signed (CMS) blob with a plain XML plist inside.
  static func groups(fromProfile data: Data) -> [String] {
    guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
          let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
          let ent = plist["Entitlements"] as? [String: Any] else { return [] }
    return ent["com.apple.security.application-groups"] as? [String] ?? []
  }

  /// Settings saved while the group wasn't found went to a private "group.com.paisapulse.app" domain. Copy them into
  /// the real group once, so the move doesn't reset the theme, last account, etc.
  static func moveOldDefaults() {
    guard isMainApp, id != base, let shared = UserDefaults(suiteName: id), !shared.bool(forKey: "movedOldDefaults") else { return }
    for (k, v) in UserDefaults.standard.persistentDomain(forName: base) ?? [:] where shared.object(forKey: k) == nil { shared.set(v, forKey: k) }
    shared.set(true, forKey: "movedOldDefaults")
  }

  /// True in the main app (not the widget or the share extension).
  static var isMainApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
  }

  /// Preferences live here so the widget sees them too.
  static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// Where this build is installed from: "sideload" (GitHub / iloader, in-app update check) or "appstore".
enum Distribution {
  static let isAppStore = (Bundle.main.object(forInfoDictionaryKey: "PaisaDistribution") as? String) == "appstore"
}
