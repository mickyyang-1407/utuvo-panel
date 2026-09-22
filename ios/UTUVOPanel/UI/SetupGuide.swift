// SetupGuide.swift — one-step banner shown above the panel preview.
// Draws a tiny phone (44×76 pt) on the left, title + 1-line description in the middle,
// and a checkmark on the right. Hides itself once `model.setup.allDone`;
// SettingsView adds a "Show setup steps again" link in that case.
//
// Ticket 0007: down to one step. The wallpaper / position steps were killed when
// `preferredBackgroundStyle(.transparent)` made the widget show the live wallpaper
// straight through (no screenshot, no alignment, no slot picker).

import SwiftUI

/// Public entry — SettingsView inserts this as the first Form Section.
struct SetupGuide: View {
    @EnvironmentObject private var model: PanelModel
    /// SettingsView flips this on when the user taps "Show setup steps again" after the guide auto-hid.
    var forceShow: Bool = false

    var body: some View {
        if !model.setup.allDone || forceShow {
            Section {
                StepRow(
                    title: "把面板加到桌面",
                    detail: "長按桌面空白處 › 左上「編輯」› 加入小工具 › 搜尋 UTUVO Panel › 選最高的尺寸",
                    done: model.setup.widgetPlaced
                )
            } footer: {
                // Hint pointing the user at Edit Widget for the only remaining choices (gradient, border).
                VStack(alignment: .leading, spacing: 4) {
                    Text("想換漸層背景或加邊框：長按面板 › 編輯小工具").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct StepRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StepPhone()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                statusIcon
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        } else {
            ZStack {
                Circle().stroke(.secondary, lineWidth: 1)
                Text("1").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 22, height: 22)
        }
    }
}

/// 44×76 pt phone, with a panel-shaped rectangle + "+" badge — the only step left in 0007.
private struct StepPhone: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Color(.secondarySystemFill))
            // A panel-shaped rectangle taking ~80% of the area, with a small "+" badge top-left.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 30, height: 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .padding(2)
        }
        .frame(width: 44, height: 76)
        .clipShape(shape)
        .overlay { shape.stroke(Color.secondary, lineWidth: 1) }
        // Decorative — collapse to one element so VoiceOver doesn't read the SF Symbol's auto label.
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}
