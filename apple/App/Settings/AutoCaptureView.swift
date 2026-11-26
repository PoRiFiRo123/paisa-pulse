import SwiftUI

/// iPhone auto-capture: iOS doesn't let apps read SMS, so a Shortcuts automation passes bank messages to
/// the "Log Bank Message" action, which keeps them here to confirm.
struct AutoCaptureView: View {
  @Environment(Router.self) private var router
  @State private var waiting = PendingAlerts.all().count

  var body: some View {
    List {
      Section {
        Button { router.captureMode = "alerts"; router.capture = true } label: {
          Label(waiting == 0 ? "No messages waiting" : "Review \(waiting) message\(waiting == 1 ? "" : "s")", systemImage: "tray.full")
        }
        .disabled(waiting == 0)
      } footer: {
        Text("Each bank SMS becomes a draft with the amount, account and payee filled in. Nothing is added until you confirm it.")
      }
      Section("Set it up once (about a minute)") {
        step(1, "Open the Shortcuts app › Automation › New Automation.")
        step(2, "Choose Message. Set Message Contains to “debited” (make a second one for “credited” and “spent” if you like).")
        step(3, "Choose Run Immediately.")
        step(4, "Add the action Log Bank Message (Paisa Pulse), and set its Message to Shortcut Input › Content.")
        step(5, "Done. The next bank message waits for you on Home.")
        Button { if let u = URL(string: "shortcuts://") { UIApplication.shared.open(u) } } label: {
          Label("Open Shortcuts", systemImage: "square.2.layers.3d")
        }
      }
      Section {} footer: {
        Text("Messages are read on this iPhone and never uploaded. OTPs, payment requests and due-date reminders are ignored.")
      }
    }
    .navigationTitle("Auto-capture")
    .onChange(of: router.capture) { _, open in if !open { waiting = PendingAlerts.all().count } }
  }

  private func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(n)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
        .frame(width: 24, height: 24).background(Circle().fill(Color.accentColor))
      Text(text).font(.subheadline)
    }
  }
}
