// AlignView.swift — drag the panel outline over the screenshot until it sits where the widget sits.

import SwiftUI

struct AlignView: View {
    @EnvironmentObject private var model: PanelModel
    @Environment(\.dismiss) private var dismiss
    @State private var dragStart: Double?

    var body: some View {
        let p = model.placement
        GeometryReader { geo in
            // Fit the whole screenshot (screen-shaped) into the view.
            let s = min(geo.size.width / p.screen.width, geo.size.height / p.screen.height)
            let w = p.screen.width * s, h = p.screen.height * s
            let r = p.rect(offset: model.config.backgroundOffset)
            ZStack(alignment: .topLeading) {
                if let shot = model.screenshot {
                    Image(uiImage: shot).resizable().frame(width: w, height: h)
                } else {
                    Color.black.frame(width: w, height: h)
                }
                // Panel outline + live preview of the crop so edges can be matched by eye.
                PanelView(data: model.previewData, inWidget: false)
                    .frame(width: p.panel.width, height: p.panel.height)
                    .scaleEffect(s, anchor: .topLeading)
                    // The full-size panel is larger than this frame; without topLeading SwiftUI centres it,
                    // so the scaled preview drifted up-left of the yellow outline (bug since 09-16).
                    .frame(width: r.width * s, height: r.height * s, alignment: .topLeading)
                    .overlay(RoundedRectangle(cornerRadius: 36 * s, style: .continuous)
                        .strokeBorder(Color.yellow, lineWidth: 2))
                    .offset(x: r.x * s, y: r.y * s)
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                if dragStart == nil { dragStart = model.config.backgroundOffset }
                                let range = max(p.screen.height - p.panel.height, 1)
                                let delta = Double(g.translation.height) / Double(s) / range
                                model.config.backgroundOffset = min(max((dragStart ?? 0) + delta, 0), 1)
                            }
                            .onEnded { _ in
                                dragStart = nil
                                model.recrop()
                            }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("對齊背景")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("往上 1 pt") { nudge(-1) }
                    Spacer()
                    Text(String(format: "y = %.0f pt", p.rect(offset: model.config.backgroundOffset).y)).font(.footnote).monospacedDigit()
                    Spacer()
                    Button("往下 1 pt") { nudge(1) }
                }
            }
        }
    }

    private func nudge(_ pts: Double) {
        let p = model.placement
        let range = max(p.screen.height - p.panel.height, 1)
        model.config.backgroundOffset = min(max(model.config.backgroundOffset + pts / range, 0), 1)
        model.recrop()
    }
}
