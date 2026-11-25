import Combine
import SwiftData
import SwiftUI

struct RootView: View {
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var phase
  @AppStorage(PrefKey.onboarded, store: AppGroup.defaults) private var onboarded = false
  @AppStorage(PrefKey.appLock, store: AppGroup.defaults) private var appLock = false
  @AppStorage(PrefKey.hideAmounts, store: AppGroup.defaults) private var hideAmounts = false
  @State private var locked = false

  var body: some View {
    Group {
      if onboarded { MainTabs() } else { OnboardingView() }
    }
    .overlay {
      if locked { LockView { locked = false } }
      // Privacy in the app switcher: with Face ID Lock or hidden amounts, nothing shows there.
      else if phase != .active && (appLock || hideAmounts) {
        ZStack {
          Color(.systemGroupedBackground)
          Image("AppLogo").resizable().frame(width: 88, height: 88)
        }
        .ignoresSafeArea()
      }
    }
    .overlay(alignment: .bottom) { ToastView() }
    .overlay { ConfettiOverlay() }
    .sheet(item: Binding(get: { router.invite }, set: { router.invite = $0 })) { i in
      NavigationStack { PeopleView(invite: i.code) }
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).debounce(for: .seconds(4), scheduler: RunLoop.main)) { _ in
      Cloud.shared.pushSoon()
      Celebrations.check(context)
    }
    .task {
      DemoData.seedIfRequested(context)
      // Screenshot automation (CI): -PaisaTab activity, -PaisaAdd YES.
      if let tab = UserDefaults.standard.string(forKey: "PaisaTab"), let url = URL(string: "paisapulse://tab/\(tab)") { router.handle(url: url) }
      if UserDefaults.standard.bool(forKey: "PaisaAdd") { router.add = AddRequest(type: .expense) }
      Seed.ensureCategories(context)
      Maintenance.run(context)
      Cloud.shared.syncSoon()
      if appLock { locked = true }
    }
    .onChange(of: phase) { _, new in
      if new == .background, appLock { locked = true }
      if new == .active {
        Maintenance.run(context)
        Celebrations.check(context)
        Cloud.shared.syncSoon()
      }
      if new == .background { Cloud.scheduleBackground() }
    }
  }
}

struct MainTabs: View {
  @Environment(Router.self) private var router

  var body: some View {
    @Bindable var router = router
    // The system tab bar: real Liquid Glass on iOS 26 (drag the lens across tabs), blur on iOS 18.
    // The + is the separate round button iOS gives the search-role tab; choosing it opens Quick Add
    // and stays on the current tab.
    TabView(selection: Binding(get: { router.tab }, set: { t in
      if t == .search { router.add = AddRequest(type: .expense) } else if t == router.tab { router.popToRoot.toggle() } else { router.tab = t }
    })) {
      Tab("Home", systemImage: "house.fill", value: AppTab.home) { TabStack(tab: .home, content: HomeView()) }
      Tab("Activity", systemImage: "list.bullet.rectangle.fill", value: AppTab.activity) { TabStack(tab: .activity, content: ActivityView()) }
      Tab("Accounts", systemImage: "creditcard.fill", value: AppTab.accounts) { TabStack(tab: .accounts, content: AccountsView()) }
      Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) { TabStack(tab: .settings, content: SettingsView()) }
      Tab("Add", systemImage: "plus", value: AppTab.search, role: .search) { Color.clear }
    }
    .modifier(TabBarMinimize())
    .sheet(item: $router.add) { request in
      QuickAddView(request: request)
    }
    .sheet(isPresented: $router.capture) { NavigationStack { CaptureView() } }
    .sheet(item: $router.request) { r in NavigationStack { RequestView(request: r) } }
  }
}

/// One tab's navigation. Tapping the selected tab again goes back to its first screen.
private struct TabStack<V: View>: View {
  @Environment(Router.self) private var router
  let tab: AppTab
  let content: V
  @State private var path = NavigationPath()
  var body: some View {
    NavigationStack(path: $path) { content }
      .toolbar(router.hideTabBar && router.tab == tab ? .hidden : .automatic, for: .tabBar)
      .onChange(of: router.popToRoot) { if router.tab == tab { path = NavigationPath() } }
  }
}

/// iOS 26: the Liquid Glass tab bar shrinks while you scroll down.
private struct TabBarMinimize: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.tabBarMinimizeBehavior(.onScrollDown)
    } else {
      content
    }
  }
}

struct ToastView: View {
  @Environment(Router.self) private var router

  var body: some View {
    if let toast = router.toast {
      HStack(spacing: 12) {
        Text(toast.text).font(.subheadline.weight(.medium)).lineLimit(2)
        if let undo = toast.undo {
          Button("Undo") {
            undo()
            router.toast = nil
          }
          .font(.subheadline.weight(.semibold))
        }
      }
      .padding(.horizontal, 18).padding(.vertical, 12)
      .glassCapsule()
      .padding(.bottom, 96)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .animation(.quick, value: router.toast)
    }
    EmptyView().sensoryFeedback(trigger: router.toast) { _, new in
      guard let new else { return nil }
      return new.error ? .error : .success
    }
  }
}

extension View {
  /// Liquid Glass on iOS 26, material elsewhere. Only for floating controls.
  @ViewBuilder func glassCapsule() -> some View {
    if #available(iOS 26.0, *) {
      self.glassEffect(.regular, in: .capsule)
    } else {
      self.background(.regularMaterial, in: Capsule())
    }
  }
}
