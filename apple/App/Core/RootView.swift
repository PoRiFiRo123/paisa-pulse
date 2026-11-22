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
    .task {
      DemoData.seedIfRequested(context)
      Seed.ensureCategories(context)
      Maintenance.run(context)
      if appLock { locked = true }
    }
    .onChange(of: phase) { _, new in
      if new == .background, appLock { locked = true }
      if new == .active {
        Maintenance.run(context)
      }
    }
  }
}

struct MainTabs: View {
  @Environment(Router.self) private var router

  var body: some View {
    @Bindable var router = router
    TabView(selection: $router.tab) {
      Tab("Home", systemImage: "house.fill", value: AppTab.home) {
        NavigationStack { HomeView() }
      }
      Tab("Activity", systemImage: "list.bullet.rectangle.fill", value: AppTab.activity) {
        NavigationStack { ActivityView() }
      }
      Tab("Accounts", systemImage: "creditcard.fill", value: AppTab.accounts) {
        NavigationStack { AccountsView() }
      }
      Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
        NavigationStack { SettingsView() }
      }
      // iOS 26: its own Liquid Glass button at the end of the tab bar.
      Tab(value: AppTab.search, role: .search) {
        NavigationStack { SearchView() }
      }
    }
    .modifier(TabBarMinimize())
    .sheet(item: $router.add) { request in
      QuickAddView(request: request)
    }
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
