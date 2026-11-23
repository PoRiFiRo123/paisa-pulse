import AppIntents
import SwiftData
import SwiftUI

@main
struct PaisaPulseApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  let container: ModelContainer = {
    let c = Store.makeContainer()
    c.mainContext.undoManager = UndoManager() // shake to undo
    return c
  }()
  @State private var router = Router()
  @AppStorage(PrefKey.theme, store: AppGroup.defaults) private var theme = "system"
  @AppStorage(PrefKey.accent, store: AppGroup.defaults) private var accent = "indigo"
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(router)
        .tint(Palette.accent(accent))
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        .onOpenURL { router.handle(url: $0) }
        .onReceive(NotificationCenter.default.publisher(for: QuickActions.notification)) { n in
          if let url = n.object as? URL { _ = PendingRoute.take(); router.handle(url: url) }
        }
        .onChange(of: phase) { _, p in if p == .active, let url = PendingRoute.take() { router.handle(url: url) } }
        .task {
          KeyboardDismiss.shared.install()
          QuickActions.install()
          if let url = QuickActions.pending { QuickActions.pending = nil; router.handle(url: url) }
          if let url = PendingRoute.take() { router.handle(url: url) }
        }
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
  /// Screenshot capture sheet (Add button menu, Settings).
  var capture = false
  /// After saving a split: ask the people who owe you (Messages, QR, link).
  var request: SplitRequest?

  /// paisapulse://add?type=expense|income|transfer (widget, Control Center, Shortcuts).
  func handle(url: URL) {
    guard url.scheme == "paisapulse" else { return }
    if url.host == "add" {
      let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "type" })?.value
      add = AddRequest(type: TxnType(rawValue: type ?? "") ?? .expense)
    } else if url.host == "capture" {
      capture = true
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

/// Long-press the app icon: Add Expense, Add Income, From Screenshots, Search (same as Android's shortcuts).
enum QuickActions {
  static let notification = Notification.Name("PaisaQuickAction")
  nonisolated(unsafe) static var pending: URL?

  @MainActor static func install() {
    func item(_ type: String, _ title: String, _ icon: String) -> UIApplicationShortcutItem {
      UIApplicationShortcutItem(type: type, localizedTitle: title, localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: icon))
    }
    UIApplication.shared.shortcutItems = [
      item("paisapulse://add?type=expense", "Add Expense", "minus.circle"),
      item("paisapulse://add?type=income", "Add Income", "plus.circle"),
      item("paisapulse://capture", "From Screenshots", "photo.on.rectangle"),
      item("paisapulse://tab/search", "Search", "magnifyingglass"),
    ]
  }

  static func fire(_ type: String) {
    guard let url = URL(string: type) else { return }
    NotificationCenter.default.post(name: notification, object: url)
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    if let item = options.shortcutItem { QuickActions.pending = URL(string: item.type) }
    let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    config.delegateClass = QuickActionSceneDelegate.self
    return config
  }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    QuickActions.fire(shortcutItem.type)
    completionHandler(true)
  }
}

/// Shows "Add Expense" and "Add Income" in Shortcuts, Spotlight and the Action Button list without setup.
struct PaisaShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: OpenAddExpenseIntent(), phrases: ["Add an expense in \(.applicationName)", "Log spending in \(.applicationName)"],
                shortTitle: "Add Expense", systemImageName: "minus.circle")
    AppShortcut(intent: OpenAddIncomeIntent(), phrases: ["Add income in \(.applicationName)"],
                shortTitle: "Add Income", systemImageName: "plus.circle")
  }
}
