import SwiftUI

private struct ResultHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 20
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranslatorView: View {
    @EnvironmentObject private var engine: TranslationEngine
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var panelState: PanelState

    @FocusState private var inputFocused: Bool
    @State private var resultHeight: CGFloat = 20

    private let maxInputHeight: CGFloat = 132
    private let maxResultHeight: CGFloat = 300

    // Panel width minus horizontal padding (16 × 2) and NSTextView's line fragment padding (5 × 2).
    private let editorTextWidth: CGFloat = PanelController.panelWidth - 32 - 10

    /// Measures the input's natural height with AppKit metrics so it matches
    /// TextEditor's actual NSTextView layout (SwiftUI Text metrics differ for CJK).
    private var inputHeight: CGFloat {
        var text = engine.input.isEmpty ? " " : engine.input
        if text.hasSuffix("\n") { text += " " }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .paragraphStyle: style,
        ])
        let rect = attributed.boundingRect(
            with: NSSize(width: editorTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        )
        return ceil(rect.height) + 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputArea
                .padding(.top, 16)
                .padding(.horizontal, 16)

            if engine.hasResultSection {
                SoftDivider()
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                resultArea
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            bottomBar
                .padding(.horizontal, 12)
                .padding(.top, engine.hasResultSection ? 12 : 10)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .bottom) {
            if let toast = engine.toast {
                Group {
                    switch toast {
                    case .fellBack: Toast.fellBack()
                    }
                }
                .padding(.bottom, 48)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: engine.hasResultSection)
        .animation(.snappy(duration: 0.25), value: engine.toast)
        .onReceive(NotificationCenter.default.publisher(for: .tusiFocusInput)) { _ in
            inputFocused = true
        }
        // Switching tone is a request to see the text in that tone, so re-run it —
        // but only when there's already a result the change would apply to.
        .onChange(of: settings.tone) {
            guard engine.hasResultSection, !engine.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            engine.translate()
        }
    }

    // MARK: - Input

    private var inputArea: some View {
        let height = inputHeight
        return ZStack(alignment: .topLeading) {
            if engine.input.isEmpty {
                Text("输入中文或任意语言，⏎ 翻译")
                    .font(Theme.contentFont)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $engine.input)
                .font(Theme.contentFont)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .scrollDisabled(height <= maxInputHeight)
                .scrollIndicators(.never)
                .focused($inputFocused)
                .frame(height: min(max(height, 24), maxInputHeight))
        }
        .overlay(alignment: .topTrailing) {
            if !engine.input.isEmpty {
                Button {
                    engine.clear()
                    inputFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
                .help("清空 (Esc 关闭面板)")
                .transition(.opacity)
            }
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var resultArea: some View {
        switch engine.state {
        case .failed(let message):
            ErrorBox(message: message) { engine.translate() }
        case .translating where engine.output.isEmpty:
            StreamingPlaceholder()
                .padding(.vertical, 2)
        default:
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // The scroll anchor rides on the text itself — a separate spacer
                    // child would add implicit VStack spacing and clip the top.
                    Text(engine.output)
                        .font(Theme.contentFont)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(key: ResultHeightKey.self, value: geometry.size.height)
                            }
                        )
                        .id("end")
                }
                .scrollIndicators(.never)
                .frame(height: min(max(resultHeight, 20), maxResultHeight))
                .onPreferenceChange(ResultHeightKey.self) { resultHeight = $0 }
                .onChange(of: engine.output) {
                    if engine.isTranslating {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            DirectionChip(
                sourceLabel: engine.sourceLabel,
                target: engine.target,
                isActive: !engine.input.isEmpty
            )

            // Tone occupies the slot the model name used to: it's an action, the model
            // is static trivia that settings already shows. It stays in the tooltip.
            ToneSelector(tone: $settings.tone)
                .help("翻译文风 · 当前模型：\(engine.activeModel)")

            Spacer(minLength: 4)

            if engine.isTranslating {
                // No spinner: the shimmering result placeholder already says "working".
                BarIconButton(systemName: "stop.fill", help: "停止") {
                    engine.cancelTranslation()
                }
                .transition(.opacity)
            } else if !engine.input.isEmpty && engine.output.isEmpty {
                Text("⏎ 翻译")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }

            BarIconButton(
                systemName: panelState.pinned ? "pin.fill" : "pin",
                isActive: panelState.pinned,
                help: panelState.pinned ? "取消固定" : "固定面板（点击外部不关闭）"
            ) {
                panelState.pinned.toggle()
            }

            BarIconButton(systemName: "gearshape", help: "设置 (⌘,)") {
                withAnimation(.snappy(duration: 0.25)) {
                    panelState.showSettings = true
                }
            }

            if !engine.output.isEmpty {
                CopyButton(copied: engine.copied, shortcutHint: settings.copyShortcut.display) {
                    engine.copyOutput()
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: engine.output.isEmpty)
        .animation(.snappy(duration: 0.22), value: engine.isTranslating)
    }
}
