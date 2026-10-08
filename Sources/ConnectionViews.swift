import SwiftUI

struct ConnectionEditor: View {
    @ObservedObject var model: VaultModel
    let original: Project?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var key = ""
    @State private var note = ""
    @State private var urlName = "URL"
    @State private var keyName = "API_KEY"
    @State private var showKey = false
    @State private var error = ""
    @State private var developer = UserDefaults.standard.bool(forKey: "developerView")
    @State private var document = "URL=\nAPI_KEY=\n"
    @State private var working = Project(name: "")
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(original == nil ? "添加服务" : "编辑服务").font(.headline)
                Spacer()
                Picker("编辑方式", selection: Binding(get: { developer }, set: switchMode)) {
                    Text("表单").tag(false)
                    Text("Developer").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            field("名称", hint: "例如 阿里云语音", text: $name)
            if developer {
                EnvTextEditor(text: $document)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("每行一个 KEY=VALUE，保存时自动解析。").font(.caption).foregroundStyle(.secondary)
            } else {
                field("API URL", hint: "https://api.example.com/v1", text: $url)
                HStack {
                    Text("API Key").frame(width: 62, alignment: .leading)
                    if showKey { TextField("粘贴 API Key", text: $key) }
                    else { SecureField("粘贴 API Key", text: $key) }
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless).accessibilityLabel("显示或隐藏 API Key")
                }
                DisclosureGroup("环境变量名称") {
                    VStack(spacing: 8) {
                        field("URL 变量", hint: "URL", text: $urlName)
                        field("Key 变量", hint: "API_KEY", text: $keyName)
                    }.padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
            }
            field("备注", hint: "用途（选填）", text: $note)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 430).textFieldStyle(.roundedBorder)
            .onAppear {
                working = original ?? Project(name: "", entries: [Entry(name: "URL", value: ""), Entry(name: "API_KEY", value: "")])
                name = original?.name ?? ""
                note = original?.note ?? ""
                loadFields()
                document = original.flatMap { model.envDrafts[$0.id] } ?? working.developerText
                if original.flatMap({ model.envDrafts[$0.id] }) != nil { developer = true }
            }
    }
    func field(_ title: String, hint: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 62, alignment: .leading)
            TextField(hint, text: text)
        }
    }
    private func loadFields() {
        url = working.urlEntry?.value ?? ""
        key = working.keyEntry?.value ?? ""
        urlName = working.urlEntry?.name ?? "URL"
        keyName = working.keyEntry?.name ?? "API_KEY"
    }
    private func formProject() throws -> Project {
        var temporary = Vault(projects: [working])
        _ = try saveConnection(&temporary, original: working, name: name.isEmpty ? "未命名" : name, note: note,
                               url: url, key: key, urlName: urlName.trimmingCharacters(in: .whitespaces),
                               keyName: keyName.trimmingCharacters(in: .whitespaces))
        return temporary.projects[0]
    }
    private func switchMode(_ next: Bool) {
        guard next != developer else { return }
        do {
            if next {
                working = try formProject()
                document = working.developerText
            } else {
                working = try applyEnvironment(document, to: working)
                loadFields()
            }
            error = ""
            developer = next
            UserDefaults.standard.set(next, forKey: "developerView")
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        do {
            let candidate = try developer ? applyEnvironment(document, to: working) : formProject()
            var savedID: UUID?
            if model.commit({ vault in
                savedID = try saveDocument(&vault, original: original, name: name, note: note, text: candidate.developerText)
                if let i = vault.projects.firstIndex(where: { $0.id == savedID }) {
                    vault.projects[i].urlEntryID = vault.projects[i].entries.first { $0.name == candidate.urlEntry?.name }?.id
                    vault.projects[i].keyEntryID = vault.projects[i].entries.first { $0.name == candidate.keyEntry?.name }?.id
                }
            }) {
                model.selected = savedID
                if let id = savedID { model.envDrafts.removeValue(forKey: id) }
                dismiss()
            } else { error = model.error ?? "保存失败"; model.error = nil }
        } catch { self.error = error.localizedDescription }
    }
}

struct AgentSetupView: View {
    @ObservedObject var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @State private var method = 0
    var executable: String { Bundle.main.executablePath ?? "KeyPocket" }
    var selectedID: String { model.project?.id.uuidString ?? "配置 ID" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("让 Agent 读取服务配置", systemImage: "link").font(.headline)
            Picker("接入方式", selection: $method) {
                Text("本机命令").tag(0)
                Text("MCP").tag(1)
            }.pickerStyle(.segmented)
            if method == 0 {
                Text("将使用说明交给能执行本机命令的 Agent。它可以发现服务，再读取需要的 URL 和 Key。").foregroundStyle(.secondary)
                code(shellQuote(executable) + " list\n\n" + shellQuote(executable) + " get " + shellQuote(selectedID))
                Text("运行脚本时也支持 run … -- 程序，直接注入变量。无需保持管理窗口打开。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("将下面的服务配置加入桌面 Agent 的 MCP 设置。接入后提供“列出服务”和“读取指定配置”两个工具。").foregroundStyle(.secondary)
                code((try? mcpConfig(executable: executable)) ?? "")
                Text("连接的 Agent 可按需读取库中的配置。get_connection 返回真实密钥，会进入该 Agent 的工具上下文。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(method == 0 ? "复制给 Agent 的说明" : "复制 MCP 配置") {
                    model.copy(method == 0 ? agentInstructions(executable: executable) : ((try? mcpConfig(executable: executable)) ?? ""), secret: false)
                    dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width: 500)
    }
    func code(_ text: String) -> some View {
        Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
