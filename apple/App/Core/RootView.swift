import Combine
import SwiftData
import SwiftUI

struct RootView: View {
  @Environment(Router.self) private var router
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var phase
  @AppStorage(PrefKey.onboarded, store: AppGroup.defaults) private var onboarded = false
  @AppStorage(PrefKey.appLock, store: AppGroup.defaults) private var appLock = false
  @State private var locked = false

  var body: some View {
    Group {
      if onboarded { MainTabs() } else { OnboardingView() }
    }
    .overlay {
      if locked { LockView { locked = false } }
    }
    .overlay(alignment: .bottom) { ToastView() }
    .sheet(item: Binding(get: { router.invite }, set: { router.invite = $0 })) { i in
      NavigationStack { PeopleView(invite: i.code) }
    }
    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).debounce(for: .seconds(4), scheduler: RunLoop.main)) { _ in
      Cloud.shared.pushSoon()
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
    // Our own floating bar (round + beside it) instead of the system tab bar, the same on Android.
    // Every tab stays alive, so each keeps its scroll position and navigation.
    ZStack {
      tab(.home) { HomeView() }
      tab(.activity) { ActivityView() }
      tab(.accounts) { AccountsView() }
      tab(.settings) { SettingsView() }
    }
    .overlay(alignment: .bottom) {
      if !router.hideTabBar {
        FloatingTabBar()
          .ignoresSafeArea(.keyboard, edges: .bottom)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.spring(duration: 0.3), value: router.hideTabBar)
    .sheet(item: $router.add) { request in
      QuickAddView(request: request)
    }
    .sheet(isPresented: $router.capture) { NavigationStack { CaptureView() } }
    .sheet(item: $router.request) { r in NavigationStack { RequestView(request: r) } }
  }

  @ViewBuilder private func tab<V: View>(_ t: AppTab, @ViewBuilder _ content: () -> V) -> some View {
    let on = router.tab == t
    TabStack(tab: t, content: content())
      // Room for the floating bar at the end of every list, on pushed screens too.
      .contentMargins(.bottom, router.hideTabBar ? 0 : 84, for: .scrollContent)
      .contentMargins(.bottom, router.hideTabBar ? 0 : 76, for: .scrollIndicators)
      .opacity(on ? 1 : 0)
      .allowsHitTesting(on)
      .accessibilityHidden(!on)
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
      .animation(.spring, value: router.toast)
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
