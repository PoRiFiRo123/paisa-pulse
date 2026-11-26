import SwiftData
import SwiftUI

/// Pushes that must survive their row disappearing.
///
/// A destination-style `NavigationLink { Detail() }` only works while the link itself stays on screen:
/// when the row that pushed a screen is removed (the plan you just created hides Home's "Plan a trip"
/// row, archiving moves a trip to Archived, a repaid loan moves to Settled), SwiftUI's stack gets stuck
/// and the app looks frozen. Value links (`NavigationLink(value: NavRoute.trip(id))`) live in the
/// stack's path instead, so the open screen stays put whatever happens to the list behind it.
/// Every tab's `NavigationStack` registers `navDestinations()` (see `TabStack` in RootView).
enum NavRoute: Hashable {
  case planning
  case trip(String)
  case account(String)
  case loan(String)
  case group(String)
  case friend(String, group: String? = nil)
}

extension View {
  func navDestinations() -> some View {
    navigationDestination(for: NavRoute.self) { NavRouteView(route: $0) }
  }
}

/// The screen for a route, looked up by id each time it draws.
struct NavRouteView: View {
  let route: NavRoute
  var body: some View {
    switch route {
    case .planning: PlanningView()
    case .trip(let id): TripByID(id: id)
    case .account(let id): AccountByID(id: id)
    case .loan(let id): LoanByID(id: id)
    case .group(let id): GroupByID(id: id)
    case .friend(let id, let group): FriendByID(id: id, groupId: group)
    }
  }
}

/// Shown if the thing a screen was showing is deleted (here or by a sync) while it's open.
private struct Gone: View {
  let text: String
  var body: some View {
    ContentUnavailableView(text, systemImage: "tray", description: Text("Go back to see the rest."))
  }
}

private struct TripByID: View {
  @Query private var found: [Trip]
  init(id: String) { _found = Query(filter: #Predicate<Trip> { $0.id == id }) }
  var body: some View { if let t = found.first { TripDetailView(trip: t) } else { Gone(text: "This plan was deleted") } }
}

private struct AccountByID: View {
  @Query private var found: [Account]
  init(id: String) { _found = Query(filter: #Predicate<Account> { $0.id == id }) }
  var body: some View { if let a = found.first { AccountDetailView(account: a) } else { Gone(text: "This account was deleted") } }
}

private struct LoanByID: View {
  @Query private var found: [Loan]
  init(id: String) { _found = Query(filter: #Predicate<Loan> { $0.id == id }) }
  var body: some View { if let l = found.first { LoanDetailView(loan: l) } else { Gone(text: "This loan was deleted") } }
}

private struct GroupByID: View {
  @Query private var found: [SplitGroup]
  init(id: String) { _found = Query(filter: #Predicate<SplitGroup> { $0.id == id }) }
  var body: some View { if let g = found.first { GroupDetailView(group: g) } else { Gone(text: "This group was deleted") } }
}

private struct FriendByID: View {
  let groupId: String?
  @Query private var found: [Friend]
  init(id: String, groupId: String?) {
    self.groupId = groupId
    _found = Query(filter: #Predicate<Friend> { $0.id == id })
  }
  var body: some View { if let f = found.first { FriendDetailView(friend: f, groupId: groupId) } else { Gone(text: "This person was removed") } }
}
