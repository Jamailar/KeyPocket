import SwiftUI
import AppKit

struct EnvTextEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = NSTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = editor.maxSize
        editor.textContainer?.widthTracksTextView = false
        editor.setAccessibilityLabel("环境变量文本")
        editor.delegate = context.coordinator
        editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, editor.string != text else { return }
        let selected = editor.selectedRange()
        editor.string = text
        editor.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EnvTextEditor
        init(_ parent: EnvTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}

struct DeveloperView: View {
    @ObservedObject var model: VaultModel
    let project: Project
    @State private var message = "已保存"
    @State private var invalid = false
    private var text: String { model.envDrafts[project.id] ?? project.developerText }
    var body: some View {
        VStack(spacing: 0) {
            EnvTextEditor(text: Binding(get: { text }, set: {
                model.envDrafts[project.id] = $0
                message = "等待保存…"
                invalid = false
            }))
            Divider()
            HStack(spacing: 8) {
                Text(message).font(.caption).foregroundStyle(invalid ? .red : .secondary).lineLimit(2)
                Spacer(minLength: 4)
                Button { model.copy(text) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("复制 .env 内容").accessibilityLabel("复制环境变量文本")
                Text("自动保存").font(.caption).foregroundStyle(.tertiary)
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .task(id: text) {
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            save()
        }
        .onDisappear { save() }
    }
    private func save() {
        guard let draft = model.envDrafts[project.id] else { return }
        do {
            _ = try parseEnv(draft)
            let success = model.commit { vault in
                guard let index = vault.projects.firstIndex(where: { $0.id == project.id }) else { throw AppError("服务配置已不存在。") }
                vault.projects[index] = try applyEnvironment(draft, to: vault.projects[index])
            }
            if success {
                model.envDrafts.removeValue(forKey: project.id)
                message = "已保存"
                invalid = false
            } else {
                message = model.error ?? "保存失败"
                model.error = nil
                invalid = true
            }
        } catch { message = "未保存 · " + error.localizedDescription; invalid = true }
    }
}

struct CompactWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, !context.coordinator.applied else { return }
            context.coordinator.applied = true
            let preview = CommandLine.arguments.contains("--preview")
            if preview || !UserDefaults.standard.bool(forKey: "compactLayoutV3") {
                window.setContentSize(NSSize(width: 720, height: 500))
                window.center()
                if !preview { UserDefaults.standard.set(true, forKey: "compactLayoutV3") }
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var applied = false }
}
