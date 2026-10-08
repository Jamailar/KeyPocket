import Foundation
import Security

struct Entry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var value: String
    var note: String = ""
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var entries: [Entry] = []
    var note: String?
    var urlEntryID: UUID?
    var keyEntryID: UUID?
    var envSource: String?

    var urlEntry: Entry? {
        if let id = urlEntryID { return entries.first { $0.id == id } }
        let matches = entries.filter { ["URL", "API_URL", "API_BASE", "BASE_URL", "API_BASE_URL"].contains($0.name) || $0.name.hasSuffix("_API_BASE") || $0.name.hasSuffix("_BASE_URL") || $0.name.hasSuffix("_API_URL") }
        return matches.count == 1 ? matches.first : nil
    }
    var keyEntry: Entry? {
        if let id = keyEntryID { return entries.first { $0.id == id } }
        let matches = entries.filter { ["KEY", "API_KEY", "TOKEN"].contains($0.name) || $0.name.hasSuffix("_API_KEY") }
        return matches.count == 1 ? matches.first : nil
    }
    var summary: [String: Any] {
        ["id": id.uuidString, "name": name, "description": note ?? "",
         "api_url": publicURL as Any? ?? NSNull(),
         "has_api_key": !(keyEntry?.value.isEmpty ?? true),
         "url_variable": urlEntry?.name as Any? ?? NSNull(),
         "key_variable": keyEntry?.name as Any? ?? NSNull(),
         "variable_names": entries.map(\.name).sorted()]
    }
    var credentials: [String: Any] {
        var data = summary
        data["api_url"] = urlEntry?.value as Any? ?? NSNull()
        data["api_key"] = keyEntry?.value as Any? ?? NSNull()
        data["environment"] = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.value) })
        return data
    }
    private var publicURL: String? {
        guard let value = urlEntry?.value, !value.isEmpty,
              var parts = URLComponents(string: value), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else { return nil }
        parts.user = nil; parts.password = nil; parts.query = nil; parts.fragment = nil
        return parts.string
    }
    var developerText: String {
        if let source = envSource, let parsed = try? parseEnv(source),
           parsed.map({ [$0.name, $0.value] }) == entries.map({ [$0.name, $0.value] }) { return source }
        return formatEnv(entries)
    }
    mutating func bindImportedRoles(from imported: [Entry]) {
        let candidates = Project(name: name, entries: imported)
        let previousURL = urlEntry
        let previousKey = keyEntry
        if previousURL?.value.isEmpty ?? true, let candidate = candidates.urlEntry,
           let matching = entries.first(where: { $0.name == candidate.name }) {
            urlEntryID = matching.id
            if let previous = previousURL, previous.id != matching.id, previous.value.isEmpty { entries.removeAll { $0.id == previous.id } }
        }
        if previousKey?.value.isEmpty ?? true, let candidate = candidates.keyEntry,
           let matching = entries.first(where: { $0.name == candidate.name }) {
            keyEntryID = matching.id
            if let previous = previousKey, previous.id != matching.id, previous.value.isEmpty { entries.removeAll { $0.id == previous.id } }
        }
    }
}

func formatEnv(_ entries: [Entry]) -> String {
    entries.map { entry in
        let value = entry.value
        let needsQuotes = value.contains { $0.isWhitespace || "\"'\\#".contains($0) }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return entry.name + "=" + (needsQuotes ? "\"" + escaped + "\"" : value)
    }.joined(separator: "\n") + "\n"
}

func applyEnvironment(_ text: String, to original: Project) throws -> Project {
    guard text.utf8.count <= 1_048_576 else { throw AppError("配置超过 1 MB。") }
    let parsed = try parseEnv(text)
    var result = original
    result.entries = parsed.map { value in
        var entry = value
        if let prior = original.entries.first(where: { $0.name == value.name }) {
            entry.id = prior.id
            entry.note = prior.note
        }
        return entry
    }
    if !result.entries.contains(where: { $0.id == result.urlEntryID }) { result.urlEntryID = nil }
    if !result.entries.contains(where: { $0.id == result.keyEntryID }) { result.keyEntryID = nil }
    result.envSource = text
    return result
}

func saveDocument(_ vault: inout Vault, original: Project?, name: String, note: String, text: String) throws -> UUID {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains("\0"), !name.contains("\n") else { throw AppError("请输入服务名称。") }
    guard !vault.projects.contains(where: { $0.id != original?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw AppError("已存在同名服务配置。") }
    let index = original.flatMap { source in vault.projects.firstIndex { $0.id == source.id } }
    if original != nil && index == nil { throw AppError("服务配置已不存在。") }
    let base = index.map { vault.projects[$0] } ?? Project(name: name)
    var updated = try applyEnvironment(text, to: base)
    updated.name = name
    updated.note = note
    if let index = index { vault.projects[index] = updated } else { vault.projects.append(updated) }
    return updated.id
}

func resolveProject(_ identifier: String, in vault: Vault) throws -> Project {
    let matches = vault.projects.filter { $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame || $0.name == identifier }
    guard matches.count == 1, let project = matches.first else { throw AppError("无法唯一匹配服务配置；请先 list，再使用配置 ID。") }
    return project
}

func saveConnection(_ vault: inout Vault, original: Project?, name: String, note: String,
                    url: String, key: String, urlName: String, keyName: String) throws -> UUID {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains("\0"), !name.contains("\n") else { throw AppError("请输入有效的服务名称。") }
    guard !vault.projects.contains(where: { $0.id != original?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw AppError("已存在同名服务配置。") }
    guard validName(urlName), validName(keyName), urlName != keyName else { throw AppError("URL 和 Key 的变量名必须合法且不同。") }
    guard !key.contains("\0"), !url.contains("\0") else { throw AppError("配置中不能包含空字符。") }
    let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if !url.isEmpty {
        guard let parts = URLComponents(string: url), ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw AppError("API URL 请填写 http(s) 基础地址，不含用户名、密码、查询参数或片段。") }
    }
    let index = original.flatMap { old in vault.projects.firstIndex { $0.id == old.id } }
    if original != nil && index == nil { throw AppError("服务配置已不存在。") }
    var project = index.map { vault.projects[$0] } ?? Project(name: name)
    let urlID = project.urlEntry?.id ?? UUID()
    let keyID = project.keyEntry?.id ?? UUID()
    for entry in project.entries where entry.id != urlID && entry.id != keyID {
        guard entry.name != urlName && entry.name != keyName else { throw AppError("变量名与其他变量重复，请先修改变量名称。") }
    }
    project.name = name
    project.note = note
    project.urlEntryID = urlID
    project.keyEntryID = keyID
    let updated = [Entry(id: urlID, name: urlName, value: url, note: project.urlEntry?.note ?? ""),
                   Entry(id: keyID, name: keyName, value: key, note: project.keyEntry?.note ?? "")]
    for entry in updated {
        if let i = project.entries.firstIndex(where: { $0.id == entry.id }) { project.entries[i] = entry }
        else { project.entries.append(entry) }
    }
    if let i = index { vault.projects[i] = project } else { vault.projects.append(project) }
    return project.id
}

struct Vault: Codable, Equatable {
    var version = 2
    var projects: [Project] = []
}

struct AppError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct KeychainStore {
    var service = "local.jam.keypocket.vault.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "vault"]
    }
    func read() throws -> Vault {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return Vault() }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        let vault = try JSONDecoder().decode(Vault.self, from: data)
        guard [1, 2].contains(vault.version) else { throw AppError("此数据由更新版本创建，请更新 KeyPocket。") }
        return vault
    }
    func write(_ vault: Vault) throws {
        var current = vault
        current.version = 2
        let data = try JSONEncoder().encode(current)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = "KeyPocket · 项目密钥"
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    func removeTestVault() throws {
        guard service.hasPrefix("local.jam.keypocket.test.") else { throw AppError("只允许清除测试数据。") }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private func failure(_ status: OSStatus) -> AppError {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "错误码 \(status)"
        return AppError("无法访问系统钥匙串：\(detail)")
    }
}

func validName(_ name: String) -> Bool {
    name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
}

func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

// Deliberately parse a small, documented dotenv subset; never execute shell input.
func parseEnv(_ text: String) throws -> [Entry] {
    var entries: [Entry] = []
    var names = Set<String>()
    for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if index == 0 { line = line.replacingOccurrences(of: "\u{FEFF}", with: "") }
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        guard let separator = line.firstIndex(of: "=") else { throw AppError("第 \(index + 1) 行缺少 =。") }
        let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        guard validName(name) else { throw AppError("第 \(index + 1) 行的变量名不合法。") }
        guard names.insert(name).inserted else { throw AppError("第 \(index + 1) 行变量名重复：\(name)") }
        var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        if let quote = value.first, quote == "\"" || quote == "'" {
            let chars = Array(value)
            var decoded = ""
            var i = 1
            var closed = false
            while i < chars.count {
                let c = chars[i]
                if c == quote {
                    let tail = String(chars.dropFirst(i + 1)).trimmingCharacters(in: .whitespaces)
                    guard tail.isEmpty || tail.hasPrefix("#") else { throw AppError("第 \(index + 1) 行引号后有无效内容。") }
                    closed = true
                    break
                }
                if c == "\\" && quote == "\"" && i + 1 < chars.count {
                    i += 1
                    switch chars[i] {
                    case "n": decoded.append("\n")
                    case "r": decoded.append("\r")
                    case "t": decoded.append("\t")
                    case "\"": decoded.append("\"")
                    case "\\": decoded.append("\\")
                    default: decoded.append("\\"); decoded.append(chars[i])
                    }
                } else { decoded.append(c) }
                i += 1
            }
            guard closed else { throw AppError("第 \(index + 1) 行引号未闭合；请将多行值写成双引号中的 \\n。") }
            value = decoded
        } else if let comment = value.range(of: "[ \\t]+#", options: .regularExpression) {
            value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        guard !value.contains("\0") else { throw AppError("第 \(index + 1) 行包含不支持的空字符。") }
        entries.append(Entry(name: name, value: value))
    }
    guard !entries.isEmpty else { throw AppError("文件里没有可导入的变量。") }
    return entries
}
