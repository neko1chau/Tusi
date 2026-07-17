import AppKit
import Combine
import Foundation

@MainActor
final class TranslationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case translating
        case done
        case failed(String)
    }

    @Published var input = "" {
        didSet { updateDirection() }
    }
    @Published private(set) var output = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var target: TargetLanguage = .english
    @Published private(set) var sourceLabel = "中"
    /// Drives the copy button's confirmation. Auto-copy sets it too, so the button is the
    /// single place that reports a copy — no extra chrome competing for the bottom bar.
    @Published private(set) var copied = false

    /// Transient banner shown at the bottom of the panel, then auto-dismissed.
    /// Whether primary or backup served the request is an implementation detail —
    /// the only thing worth surfacing is the one-time "primary failed" notice.
    enum Toast: Equatable {
        case fellBack
    }
    @Published private(set) var toast: Toast?

    private let settings: SettingsStore
    private var translationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isTranslating: Bool { state == .translating }

    /// Model shown in the bottom bar: always the primary slot's model.
    /// The bar never reveals which slot actually served — that stays behind the scenes.
    var activeModel: String {
        let model = settings.profiles[settings.primaryIndex].model.trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? "未配置模型" : model
    }

    var hasResultSection: Bool {
        state != .idle || !output.isEmpty
    }

    /// A translation ran to completion and its input is still sitting in the box.
    var hasFinishedTranslation: Bool {
        state == .done && !output.isEmpty && !input.isEmpty
    }

    private func updateDirection() {
        let (target, label) = LanguageDetector.detect(input)
        if target != self.target { self.target = target }
        if label != sourceLabel { sourceLabel = label }
    }

    func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let chain = settings.resolvedChain
        guard !chain.isEmpty else {
            state = .failed(TranslationError.emptyKey.localizedDescription)
            return
        }

        translationTask?.cancel()
        output = ""
        copied = false
        toast = nil
        state = .translating
        let target = target
        let tone = settings.tone
        let extra = settings.extraInstruction

        translationTask = Task { [weak self] in
            guard let self else { return }
            var lastError: Error?

            for (position, link) in chain.enumerated() {
                do {
                    for try await piece in TranslationService.stream(text: text, target: target, tone: tone, extra: extra, config: link.config) {
                        self.output += piece
                    }
                    guard !Task.isCancelled else { return }
                    // Normalize punctuation once the full text is in — the conversion
                    // needs to see the character after a quote to place it.
                    self.output = SmartQuotes.apply(to: self.output)
                    self.state = self.output.isEmpty ? .failed("模型没有返回内容") : .done
                    if self.settings.autoCopy, !self.output.isEmpty {
                        self.copyToPasteboard()
                        self.flashCopied(auto: true)
                    }
                    // A backup that quietly saved the day still deserves a heads-up
                    // that the primary is down; otherwise stay silent.
                    if position > 0 {
                        self.flashToast(.fellBack)
                    }
                    return
                } catch is CancellationError {
                    return  // Cancelled by a newer request or by the user.
                } catch let urlError as URLError where urlError.code == .cancelled {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    lastError = error
                    // Only fall back before any token landed — retrying mid-stream
                    // would splice two different translations together.
                    guard self.output.isEmpty, position < chain.count - 1 else { break }
                }
            }

            guard !Task.isCancelled else { return }
            let message = lastError?.localizedDescription ?? "翻译失败"
            self.state = .failed(chain.count > 1 ? "主用和备用都失败了 · \(message)" : message)
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        state = output.isEmpty ? .idle : .done
    }

    func clear() {
        translationTask?.cancel()
        translationTask = nil
        input = ""
        output = ""
        copied = false
        toast = nil
        state = .idle
    }

    /// Fills the panel with sample content for visual inspection (TUSI_PREVIEW).
    func debugPreview(input: String, output: String, toast: Toast? = nil) {
        self.input = input
        self.output = output
        self.state = .done
        self.toast = toast
    }

    private func copyToPasteboard() {
        guard !output.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }

    private func flashToast(_ kind: Toast) {
        toast = kind
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(kind == .fellBack ? 2.4 : 1.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        copyToPasteboard()
        flashCopied()
    }

    /// Morphs the copy button into a check for a beat. Auto-copy holds it a little longer:
    /// nobody clicked, so it has to survive being noticed rather than confirming a click.
    private func flashCopied(auto: Bool = false) {
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(auto ? 2.2 : 1.6))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }
}
