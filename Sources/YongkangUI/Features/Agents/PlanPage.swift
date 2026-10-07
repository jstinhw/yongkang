import Foundation
import YongkangCore

/// The page a plan is drawn on: one template, painted from `Theme`, that every plan from setup
/// and Product goes through, so each reads the same and none is grey on grey. The layout comes
/// laid out (`PlanDrawing`); the script only paints it, pans and zooms, and traces a task
/// someone clicks.
///
/// Read in seconds, top to bottom: what the plan gives, what it needs from you, then the graph.
/// Everything the agent wrote goes in as text (`textContent`), never as markup.
package enum PlanPage {
    /// The page for the plan in `url`, or one line saying why it could not be read.
    package static func html(contentsOf url: URL) -> String {
        do {
            let json = String(decoding: try JSONEncoder().encode(PlanDrawing(try Plan.load(url))), as: UTF8.self)
            // `<` escaped, so no title can close the script it sits in.
            return page(json.replacingOccurrences(of: "<", with: "\\u003c"))
        } catch {
            let said = describe(error).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(
                of: "<", with: "&lt;")
            return """
                <!doctype html><meta charset="utf-8"><body style="margin:0;padding:32px;background:\(Theme.bg.css);\
                color:\(Theme.tx2.css);font:13px/18px -apple-system,sans-serif">This plan could not be read: \(said)</body>
                """
        }
    }

    /// Which field was wrong, which is what the agent needs to be told to fix it.
    private static func describe(_ error: any Error) -> String {
        let path = { (keys: [any CodingKey]) in
            keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case DecodingError.keyNotFound(let key, let context): return "\(path(context.codingPath + [key])) is missing."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            return "\(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context): return context.debugDescription
        default: return error.localizedDescription
        }
    }

    private static let tokens = [
        ("bg", Theme.bg), ("panel", Theme.panel), ("card", Theme.card), ("raised", Theme.raised),
        ("line", Theme.line), ("line2", Theme.line2), ("well-line", Theme.wellLine), ("chip-line", Theme.chipLine),
        ("hairline", Theme.hairline), ("dots", Theme.dotGrid), ("tx", Theme.tx), ("prose", Theme.prose),
        ("tx2", Theme.tx2), ("tx3", Theme.tx3), ("tx4", Theme.tx4), ("quiet", Theme.unchanged),
        ("accent", Theme.accent), ("green", Theme.green), ("amber", Theme.amber), ("violet", Theme.violet),
    ].map { "--\($0.0): \($0.1.css);" }.joined(separator: " ")

    private static func page(_ plan: String) -> String {
        #"""
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Plan</title>
        <style>
        :root { \#(tokens) --mono: ui-monospace, SFMono-Regular, Menlo, monospace; }
        * { box-sizing: border-box; }
        [hidden] { display: none !important; }
        html, body { height: 100%; }
        body { margin: 0; display: flex; flex-direction: column; overflow: hidden; background: var(--bg); color: var(--tx);
          font: 13px/18px -apple-system, BlinkMacSystemFont, sans-serif; -webkit-font-smoothing: antialiased; }
        header { padding: 22px 32px 20px; display: flex; flex-direction: column; gap: 18px; border-bottom: 1px solid var(--line); }
        h1 { margin: 0; font-size: 22px; line-height: 28px; font-weight: 600; letter-spacing: -0.01em; }
        .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 8px; }
        .chip { padding: 2px 9px; border-radius: 999px; font-size: 12px; color: var(--prose); background: var(--raised); border: 1px solid var(--chip-line); }
        .chip.green, .chip.amber { font-weight: 500; }
        .chip.green { color: var(--green); background: color-mix(in srgb, var(--green) 10%, var(--bg)); border-color: color-mix(in srgb, var(--green) 28%, var(--bg)); }
        .chip.amber { color: var(--amber); background: color-mix(in srgb, var(--amber) 10%, var(--bg)); border-color: color-mix(in srgb, var(--amber) 28%, var(--bg)); }
        .chip.pending { border-style: dashed; border-color: var(--tx4); }
        .lists { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(320px, 100%), 1fr)); gap: 16px 48px; }
        h2 { margin: 0 0 8px; font-size: 10px; line-height: 14px; font-weight: 600; letter-spacing: .12em; text-transform: uppercase; color: var(--tx2); }
        #needs h2 { color: var(--amber); }
        ul { margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 6px; }
        li { display: flex; align-items: center; gap: 10px; min-width: 0; color: var(--prose); }
        li::before { content: ""; flex: none; width: 5px; height: 5px; border-radius: 50%; background: var(--tx3); }
        li .text { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        #needs li { color: var(--tx); }
        #needs li::before { width: 7px; height: 7px; background: var(--amber); }
        .id { font-family: var(--mono); font-size: 11px; color: var(--tx2); }
        #needs .id { flex: none; }

        main { position: relative; flex: 1; overflow: hidden; cursor: grab; background-color: var(--panel);
          background-image: radial-gradient(var(--dots) 1px, transparent 1.4px); background-size: 18px 18px; }
        main.dragging { cursor: grabbing; }
        #world { position: absolute; left: 0; top: 0; transform-origin: 0 0; -webkit-user-select: none; user-select: none; }
        #edges { position: absolute; left: 0; top: 0; overflow: visible; }
        .band { position: absolute; background: color-mix(in srgb, var(--card) 45%, var(--panel)); border: 1px solid var(--well-line); border-radius: 14px; }
        .band span { position: absolute; left: 16px; top: 9px; font: 11px/14px var(--mono); color: var(--tx2); }
        .edge { fill: none; stroke: var(--tx3); stroke-width: 1.5; }
        .edge.dashed { stroke-dasharray: 4 4; }
        .edge.lit { stroke: var(--accent); stroke-width: 2; }
        .head { fill: var(--tx3); }
        .head-lit { fill: var(--accent); }
        .node { position: absolute; display: flex; flex-direction: column; justify-content: center; padding: 10px 12px; text-align: left;
          font: inherit; color: inherit; background: var(--card); border: 1px solid var(--hairline); border-radius: 10px; cursor: pointer; }
        .node:hover { border-color: var(--tx3); }
        .node:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
        .node.ready { border: 1.5px solid color-mix(in srgb, var(--green) 55%, var(--card)); }
        .node.built, .node.pending { background: var(--panel); border: 1px dashed var(--tx4); }
        .node .title { font-size: 13px; line-height: 18px; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .node.built .title, .node.pending .title { color: color-mix(in srgb, var(--prose) 70%, var(--tx2)); }
        .node .meta { display: flex; align-items: center; gap: 6px; min-width: 0; line-height: 18px; }
        .node .id { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .node.built .id, .node.pending .id, .caption { color: var(--quiet); }
        .node.lit { border-color: var(--accent); }
        .node.focus { border: 2px solid var(--accent); background: color-mix(in srgb, var(--accent) 8%, var(--card));
          box-shadow: 0 0 0 4px color-mix(in srgb, var(--accent) 15%, transparent); }
        .caption { position: absolute; font-size: 11px; line-height: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .dim { opacity: .28; }
        .dot { display: inline-block; flex: none; width: 7px; height: 7px; border-radius: 50%; background: var(--green); margin-right: 7px; vertical-align: 1px; }
        .pill { flex: none; padding: 0 6px; border-radius: 999px; font-size: 10px; line-height: 16px; font-weight: 600; }
        .pill.you { color: var(--amber); background: color-mix(in srgb, var(--amber) 14%, var(--card)); }
        .pill.design { color: var(--violet); background: color-mix(in srgb, var(--violet) 14%, var(--card)); }

        .overlay { position: absolute; cursor: default; }
        .panel { background: var(--card); border: 1px solid var(--line2); border-radius: 8px; }
        #hint { right: 16px; top: 12px; margin: 0; font-size: 11px; line-height: 16px; color: var(--tx2); pointer-events: none; }
        .legend { left: 16px; bottom: 16px; display: flex; flex-wrap: wrap; align-items: center; gap: 16px; padding: 8px 12px;
          font-size: 11px; line-height: 16px; color: var(--prose); }
        .legend > span { display: flex; align-items: center; gap: 6px; }
        .legend .dot { margin: 0; }
        .legend .box { width: 18px; height: 11px; border: 1px dashed var(--tx3); border-radius: 3px; }
        .zoom { right: 16px; bottom: 16px; display: flex; align-items: center; gap: 2px; padding: 3px; }
        .zoom button { height: 28px; min-width: 28px; padding: 0 8px; border: 0; border-radius: 6px; background: transparent;
          color: var(--prose); font: 15px/28px -apple-system, sans-serif; cursor: pointer; }
        .zoom button:hover { background: var(--raised); }
        .zoom #fit { font-size: 12px; }
        .zoom output { min-width: 44px; text-align: center; font: 11px var(--mono); color: var(--tx2); }
        .zoom .rule { width: 1px; height: 16px; background: var(--chip-line); }
        #detail { right: 16px; bottom: 64px; width: 300px; padding: 14px 16px; display: flex; flex-direction: column; gap: 8px; }
        #detail h3 { margin: -6px 0 0; font-size: 15px; line-height: 20px; font-weight: 600; }
        #detail p { margin: 0; font-size: 12px; line-height: 17px; color: var(--prose); }
        #detail dl { margin: 2px 0 0; display: grid; grid-template-columns: 72px 1fr; gap: 4px 8px; font-size: 11px; line-height: 16px; }
        #detail dt { color: var(--tx2); }
        #detail dd { margin: 0; font-family: var(--mono); color: var(--prose); overflow-wrap: anywhere; }
        #detail .foot { margin-top: 2px; padding-top: 10px; border-top: 1px solid var(--line2); font-size: 11px; color: var(--tx2); }
        </style>
        </head>
        <body>
        <header>
          <div><h1 id="title"></h1><div class="chips" id="chips"></div></div>
          <div class="lists" id="lists">
            <section id="gets"><h2>You get</h2><ul id="outcomes"></ul></section>
            <section id="needs"><h2>Needs you</h2><ul id="asks"></ul></section>
          </div>
        </header>
        <main id="view">
          <div id="world"><svg id="edges"><defs>
            <marker id="head" viewBox="0 0 8 8" refX="4" refY="4" markerWidth="8" markerHeight="8" markerUnits="userSpaceOnUse" orient="auto"><path class="head" d="M0 0L8 4L0 8z"/></marker>
            <marker id="head-lit" viewBox="0 0 8 8" refX="4" refY="4" markerWidth="9" markerHeight="9" markerUnits="userSpaceOnUse" orient="auto"><path class="head-lit" d="M0 0L8 4L0 8z"/></marker>
          </defs></svg></div>
          <p id="hint" class="overlay">Drag or scroll to move · pinch to zoom · click a task to trace it</p>
          <aside id="detail" class="overlay panel" hidden></aside>
          <div class="overlay panel legend">
            <span><span class="dot"></span>Ready to start</span>
            <span><span class="pill you">You</span>Needs you</span>
            <span><span class="pill design">Design</span>Designed first</span>
            <span><span class="box"></span>Outside this plan</span>
          </div>
          <div class="overlay panel zoom">
            <button type="button" id="out" aria-label="Zoom out">−</button><output id="pct">100%</output>
            <button type="button" id="in" aria-label="Zoom in">+</button><span class="rule"></span>
            <button type="button" id="fit">Fit</button>
          </div>
        </main>
        <script id="plan" type="application/json">\#(plan)</script>
        <script>\#(script)</script>
        </body>
        </html>
        """#
    }
}
