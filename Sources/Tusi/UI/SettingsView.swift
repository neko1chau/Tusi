import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var panelState: PanelState

    @State private var editingIndex = 0
    @State private var showKey = false
    @State private var testStates: [Int: TestState] = [:]

    enum TestState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    private var testState: TestState { testStates[editingIndex] ?? .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            slotTabs

            VStack(alignment: .leading, spacing: 12) {
                labeledField("接口地址") {
                    TextField("https://api.example.com/v1", text: $settings.profiles[editingIndex].baseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                }
                labeledField("模型") {
                    TextField("model-name", text: $settings.profiles[editingIndex].model)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                }
                labeledField("供应商路由（可选）", hint: "仅 OpenRouter 等支持 provider 参数的网关生效，如 novita，多个用逗号分隔") {
                    TextField("novita, together", text: $settings.profiles[editingIndex].providerOrder)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                }
                labeledField("API Key") {
                    HStack(spacing: 6) {
                        Group {
                            if showKey {
                                TextField("sk-…", text: $settings.profiles[editingIndex].apiKey)
                            } else {
                                SecureField("sk-…", text: $settings.profiles[editingIndex].apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help(showKey ? "隐藏" : "显示")
                    }
                }
            }

            testRow

            SoftDivider()

            labeledField("附加要求（可选）", hint: "对所有翻译生效，例如统一术语、保留格式") {
                TextField("例：commit 统一译作「提交」", text: $settings.extraInstruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...3)
            }

            shortcutRow

            VStack(alignment: .leading, spacing: 10) {
                Toggle("主用失败时自动切换到备用", isOn: $settings.fallbackEnabled)
                Toggle("翻译完成后自动复制", isOn: $settings.autoCopy)
                Toggle("登录时启动", isOn: $settings.launchAtLogin)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 12.5))

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                Text("API Key 仅保存在本机钥匙串，不会上传")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.quaternary)
        }
        .padding(18)
        .onChange(of: settings.profiles) { testStates[editingIndex] = .idle }
        .onChange(of: editingIndex) { showKey = false }
        // Leaving the page mid-recording would otherwise swallow the next keystroke
        // typed into the translator.
        .onDisappear { panelState.recordingShortcut = false }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    panelState.showSettings = false
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("返回 (Esc)")

            Text("设置")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text("Tusi v1.0")
                .font(.system(size: 10.5))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Slot tabs

    private var slotTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0...1, id: \.self) { index in
                    slotTab(index)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if settings.primaryIndex == editingIndex {
                    Label("当前为主用，优先使用这套", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            settings.primaryIndex = editingIndex
                        }
                    } label: {
                        Label("设为主用", systemImage: "arrow.up.circle")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)

                    Text(settings.fallbackEnabled ? "· 现在是主用失败后的备用" : "· 备用已关闭，这套不会被使用")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    private func slotTab(_ index: Int) -> some View {
        let selected = editingIndex == index
        let isPrimary = settings.primaryIndex == index
        return Button {
            withAnimation(.snappy(duration: 0.2)) { editingIndex = index }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(settings.profiles[index].isUsable
                          ? AnyShapeStyle(Theme.success)
                          : AnyShapeStyle(Color.secondary.opacity(0.35)))
                    .frame(width: 5, height: 5)
                Text(isPrimary ? "主用" : "备用")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(settings.label(for: index))
                    .font(.system(size: 10.5))
                    .opacity(0.7)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.055))
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Copy shortcut

    private var shortcutRow: some View {
        HStack(spacing: 8) {
            Text("复制快捷键")
                .font(.system(size: 12.5))

            Spacer()

            if settings.copyShortcut != .defaultCopy, !panelState.recordingShortcut {
                Button {
                    settings.copyShortcut = .defaultCopy
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("恢复默认 ⇧⌘C")
            }

            Button {
                panelState.recordingShortcut.toggle()
            } label: {
                Text(panelState.recordingShortcut ? "按下新快捷键…" : settings.copyShortcut.display)
                    .font(.system(size: 11.5, weight: .medium, design: panelState.recordingShortcut ? .default : .rounded))
                    .foregroundStyle(panelState.recordingShortcut ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 62)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.primary.opacity(panelState.recordingShortcut ? 0.02 : 0.055))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            panelState.recordingShortcut
                                ? AnyShapeStyle(Theme.accent.opacity(0.6))
                                : AnyShapeStyle(Color.clear),
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(.plain)
            .help(panelState.recordingShortcut ? "按 Esc 取消" : "点击后按下新的组合键")
        }
        .animation(.snappy(duration: 0.18), value: panelState.recordingShortcut)
        .animation(.snappy(duration: 0.18), value: settings.copyShortcut)
    }

    // MARK: - Fields

    private func labeledField(_ label: String, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Test connection

    private var testRow: some View {
        HStack(spacing: 10) {
            Button {
                runTest()
            } label: {
                HStack(spacing: 5) {
                    if testState == .testing {
                        ProgressView().controlSize(.small).scaleEffect(0.6)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                    }
                    Text("测试连接")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.055)))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                .opacity(settings.profiles[editingIndex].isUsable ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(testState == .testing || !settings.profiles[editingIndex].isUsable)

            switch testState {
            case .idle:
                EmptyView()
            case .testing:
                Text("连接中…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            case .success(let ms):
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("连接正常 · \(ms) ms")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            case .failure(let message):
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .lineLimit(2)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: testState)
    }

    private func runTest() {
        let index = editingIndex
        testStates[index] = .testing
        let config = settings.profiles[index].config
        Task {
            do {
                let ms = try await TranslationService.testConnection(config: config)
                testStates[index] = .success(ms)
            } catch {
                testStates[index] = .failure(error.localizedDescription)
            }
        }
    }
}
