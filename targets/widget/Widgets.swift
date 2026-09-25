import SwiftUI
import WidgetKit

@main
struct PaisaPulseWidgets: WidgetBundle {
  var body: some Widget {
    SpendingWidget()
    if #available(iOS 18.0, *) {
      QuickAddControl()
    }
  }
}
