import SwiftUI
import AppKit
import Combine

@MainActor final class VaultModel: ObservableObject {
    @Published var vault = Vault()
    @Published var selected: UUID?
    @Published var error: String?
    @Published var ready = false
    @Published var feedback = ""
    @Published var envDrafts: [UUID: String] = [:]
    private var clipboardChange: Int?
    private var terminationObserver: NSObjectProtocol?
    let store = KeychainStore()
    let preview = CommandLine.arguments.contains("--preview")
    init() {
        reload()
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushDrafts()
                if let count = self?.clipboardChange, NSPasteboard.general.changeCount == count {
                    NSPasteboard.general.clearContents()
                }
            }
        }
    }
    func reload() {
        if preview {
            vault = Vault(projects: [Project(name: "示例项目", entries: [
                Entry(name: "DEMO_API_KEY", value: "demo-only-not-a-real-key", note: "仅用于界面预览"),
                Entry(name: "DEMO_API_BASE", value: "https://example.com")
            ])])
            selected = vault.projects.first?.id
            ready = true
            return
        }
        do {
            vault = try store.read()
            ready = true
            if !vault.projects.contains(where: { $0.id == selected }) { selected = vault.projects.first?.id }
        } catch { ready = false; self.error = error.localizedDescription }
    }
    func commit(_ change: (inout Vault) throws -> Void) -> Bool {
        do {
            var updated = preview ? vault : try store.read()
            try change(&updated)
            if !preview { try store.write(updated) }
            vault = updated
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func copy(_ value: String, secret: Bool = true) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        let count = pasteboard.changeCount
        clipboardChange = secret ? count : nil
        feedback = secret ? "已复制 · 30 秒后清除剪贴板" : "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.feedback = "" }
        if secret {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if pasteboard.changeCount == count { pasteboard.clearContents() }
            }
        }
    }
    func flushDrafts() {
        for (id, text) in envDrafts {
            guard (try? parseEnv(text)) != nil else { continue }
            if commit({ vault in
                guard let i = vault.projects.firstIndex(where: { $0.id == id }) else { throw AppError("服务配置不存在。") }
                vault.projects[i] = try applyEnvironment(text, to: vault.projects[i])
            }) { envDrafts.removeValue(forKey: id) }
        }
    }
    var project: Project? { vault.projects.first { $0.id == selected } }
}

struct KeyPocketApp: App {
    @StateObject private var model = VaultModel()
    var body: some Scene {
        WindowGroup("KeyPocket") {
            MainView(model: model)
                .frame(minWidth: 640, minHeight: 420)
                .background(CompactWindow())
                .tint(Color(red: 0.17, green: 0.43, blue: 0.36))
        }
        .defaultSize(width: 720, height: 500)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct MainView: View {
    @ObservedObject var model: VaultModel
    @State private var search = ""
    @AppStorage("developerView") private var developer = false
    @State private var newProject = false
    @State private var renameProject = false
    @State private var editing: Entry?
    @State private var adding = false
    @State private var deletingProject = false
    @State private var deletingEntry: Entry?
    @State private var importItems: [Entry]?
    @State private var importFile = ""
    @State private var overwrite = false
    @State private var commandHelp = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "key.horizontal.fill").font(.title2).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("KeyPocket").font(.headline)
                        Text(model.preview ? "预览模式 · 不保存数据" : "本地服务配置").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12)
                List(selection: $model.selected) {
                    Section("服务配置") {
                        ForEach(model.vault.projects) { project in
                            HStack {
                                Label(project.name, systemImage: "folder")
                                Spacer()
                                Text("\(project.entries.count)").font(.caption).foregroundStyle(.secondary)
                            }.tag(project.id)
                        }
                    }
                }.listStyle(.sidebar)
                Button { newProject = true } label: {
                    Label("添加服务", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(12).disabled(!model.ready)
                Divider()
                Button { commandHelp = true } label: { Label("接入 Agent", systemImage: "link") }.buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 10)
                Label("存储于系统钥匙串", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }.navigationSplitViewColumnWidth(min: 160, ideal: 175, max: 210)
        } detail: {
            if !model.ready {
                VStack(spacing: 18) {
                    Image(systemName: "lock.trianglebadge.exclamationmark").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("暂时无法打开密钥库").font(.title2)
                    Button("重试") { model.reload() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let project = model.project {
                projectDetail(project)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "key.horizontal").font(.system(size: 36, weight: .light)).foregroundStyle(.tint)
                    Text("保存一次，Agent 随时取用").font(.system(size: 20, weight: .semibold))
                    Text("将 API URL、API Key 和用途保存在一起。").foregroundStyle(.secondary)
                    Button("添加第一个服务") { newProject = true }
                        .buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: model.selected) { _, _ in search = "" }
        .sheet(isPresented: $newProject) { ConnectionEditor(model: model, original: nil) }
        .sheet(isPresented: $renameProject) { ConnectionEditor(model: model, original: model.project) }
        .sheet(isPresented: $adding) {
            if let project = model.project { EntryEditor(model: model, project: project, entry: nil) }
        }
        .sheet(item: $editing) { entry in
            if let project = model.project { EntryEditor(model: model, project: project, entry: entry) }
        }
        .sheet(isPresented: Binding(get: { importItems != nil }, set: { if !$0 { importItems = nil } })) { importPreview }
        .sheet(isPresented: $commandHelp) { commandSheet }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("删除服务配置？", isPresented: $deletingProject) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                let id = model.selected
                if model.commit({ $0.projects.removeAll { $0.id == id } }) { model.selected = model.vault.projects.first?.id }
            }
        } message: { Text("将删除「\(model.project?.name ?? "")」及其中所有密钥。此操作无法撤销。") }
        .alert("删除密钥？", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } })) {
            Button("取消", role: .cancel) { deletingEntry = nil }
            Button("删除", role: .destructive) {
                let entryID = deletingEntry?.id
                let projectID = model.selected
                _ = model.commit { vault in
                    guard let i = vault.projects.firstIndex(where: { $0.id == projectID }) else { throw AppError("服务配置不存在。") }
                    vault.projects[i].entries.removeAll { $0.id == entryID }
                }
                deletingEntry = nil
            }
        } message: { Text("删除 \(deletingEntry?.name ?? "")？此操作无法撤销。") }
    }

    func projectDetail(_ project: Project) -> some View {
        let filtered = project.entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) }.sorted {
            func rank(_ entry: Entry) -> Int { entry.id == project.urlEntry?.id ? 0 : (entry.id == project.keyEntry?.id ? 1 : 2) }
            return rank($0) == rank($1) ? $0.name < $1.name : rank($0) < rank($1)
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    if let note = project.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Button("编辑配置") { renameProject = true }
                Menu {
                    Button("刷新") { model.reload() }
                    Divider()
                    Button("删除服务配置…", role: .destructive) { deletingProject = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).frame(width: 26)
            }.padding(16)
            HStack(spacing: 8) {
                Picker("视图", selection: $developer) {
                    Text("概览").tag(false)
                    Text("Developer").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                if !developer {
                    TextField("搜索变量", text: $search).textFieldStyle(.roundedBorder)
                } else { Spacer() }
                Button("导入 .env") { selectImport() }
                if !developer {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .help("添加变量").accessibilityLabel("添加变量")
                }
            }.controlSize(.small).padding(.horizontal, 16).padding(.bottom, 10)
            Divider()
            if developer {
                DeveloperView(model: model, project: project).id(project.id)
            } else if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: search.isEmpty ? "tray" : "magnifyingglass").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text(search.isEmpty ? "还没有变量" : "没有匹配的变量").font(.headline)
                    Text(search.isEmpty ? "添加 API Key，或导入已有的 .env 文件。" : "试试其他变量名或备注。").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            EntryRow(entry: entry, role: entry.id == project.urlEntry?.id ? "API URL" : (entry.id == project.keyEntry?.id ? "API Key" : nil), copy: { model.copy(entry.value) }, edit: { editing = entry }, delete: { deletingEntry = entry })
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            if !developer {
                Divider()
                HStack {
                    Text(model.feedback.isEmpty ? (model.envDrafts[project.id] == nil ? "\(project.entries.count) 个变量 · 系统钥匙串" : "Developer 中有未保存的草稿") : model.feedback)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }

    func selectImport() {
        let panel = NSOpenPanel()
        panel.title = "选择 .env 文件"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                guard (attrs[.size] as? Int ?? 0) <= 1_048_576 else { throw AppError("文件超过 1 MB，请选择较小的 .env 文件。") }
                let items = try parseEnv(String(contentsOf: url, encoding: .utf8))
                importFile = url.lastPathComponent
                overwrite = false
                importItems = items
            } catch { model.error = error.localizedDescription }
        }
    }

    var importPreview: some View {
        let items = importItems ?? []
        let existing = Set(model.project?.entries.map(\.name) ?? [])
        let duplicates = items.filter { existing.contains($0.name) }.count
        return VStack(alignment: .leading, spacing: 18) {
            Text("导入 \(importFile)").font(.title2.bold())
            Text("\(items.count) 个变量 → \(model.project?.name ?? "")").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { entry in
                        HStack {
                            Text(entry.name).font(.system(.body, design: .monospaced))
                            Spacer()
                            if existing.contains(entry.name) { Text("已存在").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.frame(maxHeight: 220)
            if duplicates > 0 { Toggle("覆盖 \(duplicates) 个同名变量（默认跳过）", isOn: $overwrite) }
            Text("支持单行值和引号；不执行命令或展开 ${变量}。原文件保留。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { importItems = nil }.keyboardShortcut(.cancelAction)
                Button("导入") {
                    let projectID = model.selected
                    if model.commit({ vault in
                        guard let i = vault.projects.firstIndex(where: { $0.id == projectID }) else { throw AppError("服务配置不存在。") }
                        for entry in items {
                            if let j = vault.projects[i].entries.firstIndex(where: { $0.name == entry.name }) {
                                if overwrite { vault.projects[i].entries[j].value = entry.value }
                            } else { vault.projects[i].entries.append(entry) }
                        }
                        vault.projects[i].bindImportedRoles(from: items)
                    }) { importItems = nil }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 490)
    }

    var commandSheet: some View {
        AgentSetupView(model: model)
    }
}

struct EntryRow: View {
    let entry: Entry
    var role: String? = nil
    let copy: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var revealed = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key").font(.title3).foregroundStyle(.secondary)
                .frame(width: 28, height: 28).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(role ?? entry.name).font(.system(.body, design: role == nil ? .monospaced : .default).weight(.medium)).lineLimit(1)
                if role != nil { Text(entry.name).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                Text((revealed || role == "API URL") ? (entry.value.isEmpty ? "（未填写）" : entry.value) : "••••••••••••••••")
                    .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    .privacySensitive()
                if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if role != "API URL" { Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }.help(revealed ? "隐藏" : "显示").accessibilityLabel(revealed ? "隐藏密钥" : "显示密钥") }
            Button(action: copy) { Image(systemName: "doc.on.doc") }.help("复制值").accessibilityLabel("复制值")
            Menu {
                Button("编辑", action: edit)
                Button("删除…", role: .destructive, action: delete)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22).accessibilityLabel("变量操作")
        }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
            .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
            .onChange(of: entry) { _, _ in revealed = false }
            .task(id: revealed) {
                if revealed {
                    try? await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled { revealed = false }
                }
            }
    }
}

struct EntryEditor: View {
    @ObservedObject var model: VaultModel
    let project: Project
    let entry: Entry?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ""
    @State private var note = ""
    @State private var visible = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(entry == nil ? "添加变量" : "编辑变量").font(.title2.bold())
            VStack(alignment: .leading, spacing: 7) {
                Text("变量名").font(.subheadline.weight(.medium))
                TextField("例如 DASHSCOPE_API_KEY", text: $name).font(.system(.body, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("值").font(.subheadline.weight(.medium))
                HStack {
                    if visible { TextField("密钥或配置值", text: $value) }
                    else { SecureField("密钥或配置值", text: $value) }
                    Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye") }.buttonStyle(.borderless).accessibilityLabel("切换值的可见性")
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("备注（选填）").font(.subheadline.weight(.medium))
                TextField("用途、服务商或环境", text: $note)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard validName(key) else { error = "变量名仅允许字母、数字和下划线，且不能以数字开头。"; return }
                    guard !value.contains("\0") else { error = "值不能包含空字符。"; return }
                    let updated = Entry(id: entry?.id ?? UUID(), name: key, value: value, note: note)
                    if model.commit({ vault in
                        guard let i = vault.projects.firstIndex(where: { $0.id == project.id }) else { throw AppError("服务配置不存在。") }
                        guard !vault.projects[i].entries.contains(where: { $0.id != updated.id && $0.name == key }) else { throw AppError("项目里已存在同名变量。") }
                        if let j = vault.projects[i].entries.firstIndex(where: { $0.id == updated.id }) { vault.projects[i].entries[j] = updated }
                        else { vault.projects[i].entries.append(updated) }
                    }) { dismiss() }
                    else { error = model.error ?? "保存失败"; model.error = nil }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(16).frame(width: 400)
            .onAppear { name = entry?.name ?? ""; value = entry?.value ?? ""; note = entry?.note ?? "" }
    }
}
