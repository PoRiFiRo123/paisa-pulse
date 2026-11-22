import UIKit

/// A small glass "hide keyboard" button that floats just above any keyboard in the app (number pads have no
/// return key), plus tap-outside-to-dismiss. One overlay window, so it works in sheets and alerts too.
@MainActor final class KeyboardDismiss: NSObject, UIGestureRecognizerDelegate {
  static let shared = KeyboardDismiss()
  private var window: PassthroughWindow?
  private var button: UIButton?
  private var installedOn = Set<ObjectIdentifier>()

  func install() {
    guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
    let w = PassthroughWindow(windowScene: scene)
    w.windowLevel = UIWindow.Level(rawValue: 10_000_001) // above the keyboard's window
    w.backgroundColor = .clear
    w.isHidden = true
    let root = UIViewController()
    root.view.backgroundColor = .clear
    w.rootViewController = root

    var config: UIButton.Configuration
    if #available(iOS 26, *) { config = .glass() } else { config = .gray() }
    config.image = UIImage(systemName: "keyboard.chevron.compact.down")
    config.cornerStyle = .capsule
    let b = UIButton(configuration: config, primaryAction: UIAction { _ in
      UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    })
    b.accessibilityLabel = "Hide keyboard"
    root.view.addSubview(b)
    w.button = b
    window = w; button = b

    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(changed(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    nc.addObserver(self, selector: #selector(hidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    nc.addObserver(self, selector: #selector(windowAppeared(_:)), name: UIWindow.didBecomeKeyNotification, object: nil)
    scene.windows.forEach(addTap)
  }

  @objc private func windowAppeared(_ n: Notification) { if let w = n.object as? UIWindow, !(w is PassthroughWindow) { addTap(w) } }

  /// Tap outside a text field to dismiss (taps still reach buttons and rows).
  private func addTap(_ w: UIWindow) {
    guard !(w is PassthroughWindow), installedOn.insert(ObjectIdentifier(w)).inserted else { return }
    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    tap.cancelsTouchesInView = false
    tap.delegate = self
    w.addGestureRecognizer(tap)
  }

  @objc private func tapped(_ g: UITapGestureRecognizer) { g.view?.endEditing(true) }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var v = touch.view
    while let view = v { if view is UITextField || view is UITextView || view is UIControl { return false }; v = view.superview }
    return true
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

  @objc private func changed(_ n: Notification) {
    guard let window, let button, let end = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
    let screen = window.screen.bounds
    guard end.minY < screen.maxY - 40 else { hidden(n); return }
    let size = CGSize(width: 48, height: 36)
    button.frame = CGRect(x: screen.maxX - size.width - 12, y: end.minY - size.height - 8, width: size.width, height: size.height)
    window.isHidden = false
  }

  @objc private func hidden(_ n: Notification) { window?.isHidden = true }
}

/// Lets every touch through except on the button.
final class PassthroughWindow: UIWindow {
  weak var button: UIButton?
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let button, !button.isHidden, button.frame.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
    return super.hitTest(point, with: event)
  }
}
