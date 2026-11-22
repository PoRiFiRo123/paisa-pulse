import ExpoModulesCore

/// SideStore / AltStore re-sign the app with a free Apple ID and rename its App Groups
/// (group.com.paisapulse.app → group.com.paisapulse.app.<TEAMID>). They list the real names in
/// Info.plist under ALTAppGroups. Store builds have no such key.
public class AppGroupModule: Module {
  public func definition() -> ModuleDefinition {
    Name("AppGroup")
    Constant("appGroups") { () -> [String] in
      (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
    }
  }
}
