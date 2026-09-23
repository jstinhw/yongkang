import AppKit
import SwiftUI
import WebKit

/// What a session drew for the user — its plan graph, or the report it left when it stopped —
/// read from `.notebook/pages/<session>.html`. It is shown here, beside the terminal, because an
/// artifact or a file the agent opened itself put a browser tab in front of the window every time.
///
/// The agent rewrites the file in place as the plan changes, and a web view does not watch
/// files, so the file's date is looked at every two seconds and a newer one reloads the page.
struct SessionPage: View {
    let url: URL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
                PageFile(url: url, date: date).id(url)
            } else {
                Text("This session has not drawn a page yet.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.tx3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct PageFile: NSViewRepresentable {
    let url: URL
    let date: Date

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        // The same dark ground as a demo's pane, for the same reason: see `DemoPages`.
        view.underPageBackgroundColor = NSColor(Theme.bg)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != date else { return }
        context.coordinator.loaded = date
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The date of the file last loaded, so a tick with nothing new leaves the page, and where
    /// the user had scrolled to, alone.
    final class Coordinator {
        var loaded: Date?
    }
}
