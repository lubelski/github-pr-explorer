import AppKit
import SwiftUI

/// The app's name as shown to people.
enum AppName {
    static let display = "GitHub PR Explorer"
}

/// Gives the window it sits in a plain title bar with the app's name centered in it, so every
/// window says which app it belongs to. The content starts below the bar instead of running
/// under it, and there is no toolbar, which is what lets the title sit in the middle.
///
/// It can also put a small SwiftUI view at the right end of the bar, for quiet status, and one
/// just after the window buttons at the left, where Mac apps put the sidebar button.
///
/// AppKit, because SwiftUI has no way to center a label in a title bar without a toolbar, or
/// to place a view in the bar beside the window's own controls.
private struct StandardTitleBar: NSViewRepresentable {
    var leading: AnyView?
    var trailing: AnyView?

    func makeNSView(context: Context) -> NSView { TitleBarView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? TitleBarView else { return }
        view.leading = leading
        view.trailing = trailing
        view.apply()
    }

    final class TitleBarView: NSView {
        var leading: AnyView?
        var trailing: AnyView?
        private var leadingHost: NSHostingView<AnyView>?
        private var trailingHost: NSHostingView<AnyView>?
        private var visibilityObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeTitleVisibility()
            apply()
        }

        /// Marks the views this one adds to the title bar, so each is added once per window.
        private static let labelID = NSUserInterfaceItemIdentifier("StandardTitleBarLabel")
        private static let leadingID = NSUserInterfaceItemIdentifier("StandardTitleBarLeading")
        private static let trailingID = NSUserInterfaceItemIdentifier("StandardTitleBarTrailing")

        func apply() {
            guard let window else { return }
            if window.toolbar != nil { window.toolbar = nil }
            if window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.remove(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .line
            // The window keeps its title for Mission Control and the Window menu, but the bar
            // does not draw it: the system puts it beside the window buttons, and this app
            // wants it in the middle. The label below draws it there instead.
            if window.title != AppName.display { window.title = AppName.display }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            addCenteredLabel(to: window)
            placeLeading(in: window)
            placeTrailing(in: window)
        }

        /// SwiftUI owns the window of a `Window` scene and can set its title visibility again
        /// when the scene updates, after this view last ran. The system's own title then comes
        /// back beside the window buttons, next to the centered label. Hide it again whenever
        /// that happens. Offscreen renders use a plain `NSWindow` that SwiftUI never manages,
        /// which is why they never showed the second title.
        private func observeTitleVisibility() {
            visibilityObservation = nil
            guard let window else { return }
            visibilityObservation = window.observe(\.titleVisibility, options: [.new]) { window, _ in
                // AppKit changes a window on the main thread. Setting it to hidden again
                // changes it once more, to the value wanted, so this settles after one round.
                MainActor.assumeIsolated {
                    if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
                }
            }
        }

        private func addCenteredLabel(to window: NSWindow) {
            guard let bar = window.standardWindowButton(.closeButton)?.superview,
                  !bar.subviews.contains(where: { $0.identifier == Self.labelID })
            else { return }
            let label = NSTextField(labelWithString: AppName.display)
            label.identifier = Self.labelID
            label.font = .titleBarFont(ofSize: NSFont.systemFontSize)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            ])
        }

        /// Just after the window buttons, as far from the zoom button as the buttons are from
        /// each other, the way Mac apps place a sidebar button.
        private func placeLeading(in window: NSWindow) {
            guard let leading else {
                leadingHost?.removeFromSuperview()
                leadingHost = nil
                return
            }
            if let leadingHost, leadingHost.window === window {
                leadingHost.rootView = leading
                return
            }
            guard let zoom = window.standardWindowButton(.zoomButton), let bar = zoom.superview else { return }
            bar.subviews.first { $0.identifier == Self.leadingID }?.removeFromSuperview()
            let host = NSHostingView(rootView: leading)
            host.identifier = Self.leadingID
            host.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: zoom.trailingAnchor, constant: 14),
                host.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            ])
            leadingHost = host
        }

        private func placeTrailing(in window: NSWindow) {
            guard let trailing else {
                trailingHost?.removeFromSuperview()
                trailingHost = nil
                return
            }
            if let trailingHost, trailingHost.window === window {
                trailingHost.rootView = trailing
                return
            }
            guard let bar = window.standardWindowButton(.closeButton)?.superview else { return }
            bar.subviews.first { $0.identifier == Self.trailingID }?.removeFromSuperview()
            let host = NSHostingView(rootView: trailing)
            host.identifier = Self.trailingID
            host.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(host)
            NSLayoutConstraint.activate([
                host.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
                host.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            ])
            trailingHost = host
        }
    }
}

extension View {
    /// A plain title bar that says the app's name, the same on every window.
    func standardTitleBar() -> some View {
        modifier(StandardTitleBarModifier(leading: nil, trailing: nil))
    }

    /// A plain title bar that says the app's name, with `trailing` at its right end.
    func standardTitleBar(@ViewBuilder trailing: () -> some View) -> some View {
        modifier(StandardTitleBarModifier(leading: nil, trailing: AnyView(trailing())))
    }

    /// A plain title bar that says the app's name, with `leading` just after the window
    /// buttons and `trailing` at its right end.
    func standardTitleBar(@ViewBuilder leading: () -> some View, @ViewBuilder trailing: () -> some View) -> some View {
        modifier(StandardTitleBarModifier(leading: AnyView(leading()), trailing: AnyView(trailing())))
    }
}

private struct StandardTitleBarModifier: ViewModifier {
    var leading: AnyView?
    var trailing: AnyView?

    func body(content: Content) -> some View {
        content
            .navigationTitle(AppName.display)
            // Tells SwiftUI itself not to show the title, so a scene update does not bring the
            // system's title back beside the window buttons. The label is the only title drawn.
            .toolbar(removing: .title)
            .background(StandardTitleBar(leading: leading, trailing: trailing))
    }
}
