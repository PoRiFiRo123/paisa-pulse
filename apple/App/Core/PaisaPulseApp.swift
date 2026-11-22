import SwiftData
import SwiftUI

@main
struct PaisaPulseApp: App {
  let container: ModelContainer = {
    let c = Store.makeContainer()
    c.mainContext.undoManager = UndoManager() // shake to undo
    return c
  }()
  @State private var router = Router()
  @AppStorage(PrefKey.theme, store: AppGroup.defaults) private var theme = "system"
  @AppStorage(PrefKey.accent, store: AppGroup.defaults) private var accent = "indigo"

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(router)
        .tint(Palette.accent(accent))
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        .onOpenURL { router.handle(url: $0) }
    }
    .modelContainer(container)
  }
}

enum AppTab: Hashable { case home, activity, accounts, settings, search }

/// Where the add sheet should open.
struct AddRequest: Identifiable {
  let id = UUID()
  var type: TxnType = .expense
  var editing: Txn? = nil
  var date: Date? = nil
  var accountId: String? = nil
}

struct ToastMessage: Identifiable, Equatable {
  let id = UUID()
  let text: String
  var undo: (() -> Void)? = nil
  static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

@Observable final class Router {
  var tab: AppTab = .home
  var add: AddRequest?
  var toast: ToastMessage?

  /// paisapulse://add?type=expense|income|transfer (widget, Control Center, Shortcuts).
  func handle(url: URL) {
    guard url.scheme == "paisapulse" else { return }
    if url.host == "add" {
      let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "type" })?.value
      add = AddRequest(type: TxnType(rawValue: type ?? "") ?? .expense)
    } else if url.host == "tab" {
      switch url.lastPathComponent {
      case "activity": tab = .activity
      case "accounts": tab = .accounts
      case "settings": tab = .settings
      case "search": tab = .search
      default: tab = .home
      }
    }
  }

  func show(_ text: String, undo: (() -> Void)? = nil) {
    let msg = ToastMessage(text: text, undo: undo)
    toast = msg
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      if self.toast == msg { self.toast = nil }
    }
  }
}
