import Foundation

func testAgentInterface() throws {
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw AppError("Agent 接口测试失败：" + message) }
    }
    var vault = Vault()
    let sampleEntries = [Entry(name: "URL", value: "https://example.com/v1?a=b"),
                         Entry(name: "API_KEY", value: "a 'quoted' \"key\"\\with\nlines\t #value"),
                         Entry(name: "EMPTY", value: ""), Entry(name: "LITERAL", value: "${OTHER}=$(nothing)")]
    let roundTrip = try parseEnv(formatEnv(sampleEntries))
    try check(roundTrip.map { [$0.name, $0.value] } == sampleEntries.map { [$0.name, $0.value] }, "dotenv editor exact round trip")
    let source = "# developer note\nURL=https://example.com\nAPI_KEY=demo-key\nMODEL=demo-model\n"
    var document = try applyEnvironment(source, to: Project(name: "Developer"))
    try check(document.urlEntry?.name == "URL" && document.keyEntry?.name == "API_KEY", "short URL alias")
    try check(document.developerText == source, "preserve comments and formatting")
    document.entries[1].note = "keep this note"
    let oldKeyID = document.entries[1].id
    let changed = try applyEnvironment("URL=https://example.com/v2\nAPI_KEY=new-key\nEXTRA=42\n", to: document)
    try check(changed.keyEntry?.id == oldKeyID && changed.keyEntry?.note == "keep this note", "developer save preserves key identity and notes")
    try check(!changed.entries.contains { $0.name == "MODEL" } && changed.entries.contains { $0.name == "EXTRA" }, "document replacement adds and removes variables")
    var pending = Vault(projects: [document])
    let beforeInvalid = pending
    do {
        _ = try saveDocument(&pending, original: document, name: "Developer", note: "", text: "URL=https://example.com\nAPI_KEY='unfinished")
    } catch {}
    try check(pending == beforeInvalid, "invalid text keeps stored data unchanged")
    document.entries[1].value = "updated-by-form"
    try check(document.developerText != source && (try parseEnv(document.developerText))[1].value == "updated-by-form", "form changes invalidate stale raw source")
    let id = try saveConnection(&vault, original: nil, name: "语音服务", note: "中文 TTS", url: "https://example.com/v1", key: "test-only-secret-alpha", urlName: "TTS_API_BASE", keyName: "TTS_API_KEY")
    vault.projects[0].entries.append(Entry(name: "EXTRA_TOKEN", value: "test-only-extra-secret"))
    let connection = try resolveProject(id.uuidString, in: vault)
    try check(connection.urlEntry?.value == "https://example.com/v1" && connection.keyEntry?.name == "TTS_API_KEY", "URL / Key roles")
    let listing = try jsonString(connection.summary)
    try check(!listing.contains("test-only-secret-alpha") && !listing.contains("test-only-extra-secret"), "listing must omit secret values")
    try check(connection.credentials["api_key"] as? String == "test-only-secret-alpha", "get returns selected key")
    let renamedID = try saveConnection(&vault, original: connection, name: "语音服务 V2", note: "更新", url: "https://example.com/v2", key: "test-only-secret-beta", urlName: "SPEECH_URL", keyName: "SPEECH_TOKEN")
    try check(renamedID == id && vault.projects[0].entries.count == 3 && vault.projects[0].entries.contains(where: { $0.name == "EXTRA_TOKEN" }), "editing keeps IDs and extra variables")
    try check(vault.projects[0].keyEntry?.name == "SPEECH_TOKEN", "explicit mapping survives nonstandard variable names")
    do {
        _ = try saveConnection(&vault, original: vault.projects[0], name: "语音服务 V2", note: "", url: "https://example.com", key: "value", urlName: "EXTRA_TOKEN", keyName: "API_KEY")
        throw AppError("collision was not rejected")
    } catch let error as AppError { try check(error.message != "collision was not rejected", "collision rejected") }
    for url in ["ftp://example.com", "https://user:pass@example.com", "https://example.com?token=secret", "https://example.com#fragment"] {
        do {
            _ = try saveConnection(&vault, original: nil, name: "bad", note: "", url: url, key: "", urlName: "URL", keyName: "KEY")
            throw AppError("invalid URL was accepted")
        } catch let error as AppError { try check(error.message != "invalid URL was accepted", "URL validation") }
    }
    let legacy: [String: Any] = ["version": 1, "projects": [["id": UUID().uuidString, "name": "旧项目", "entries": [
        ["id": UUID().uuidString, "name": "OLD_API_KEY", "value": "legacy-test-secret", "note": ""],
        ["id": UUID().uuidString, "name": "OLD_API_BASE", "value": "https://example.com", "note": ""]
    ]]]]
    let migrated = try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: legacy))
    try check(migrated.projects[0].keyEntry?.value == "legacy-test-secret" && migrated.projects[0].urlEntry?.value == "https://example.com", "v1 data decode and role inference")
    var ambiguous = migrated.projects[0]
    ambiguous.entries.append(Entry(name: "OTHER_API_KEY", value: "other"))
    try check(ambiguous.keyEntry == nil, "do not guess ambiguous keys")
    let server = MCPServer(readVault: { vault })
    func request(_ method: String, _ params: [String: Any] = [:]) -> [String: Any] {
        server.response(to: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]) ?? [:]
    }
    try check(request("tools/list")["error"] != nil, "require initialization")
    let initialized = request("initialize", ["protocolVersion": "future-version", "clientInfo": ["name": "test", "version": "1"], "capabilities": [:]])
    try check((initialized["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18", "negotiate supported version")
    _ = server.response(to: ["jsonrpc": "2.0", "method": "notifications/initialized"])
    let tools = (request("tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]]
    try check(tools?.count == 2, "two read-only tools")
    let mcpList = try jsonString(request("tools/call", ["name": "list_connections"]))
    try check(!mcpList.contains("test-only-secret") && !mcpList.contains("test-only-extra-secret"), "MCP listing redaction")
    let mcpGet = try jsonString(request("tools/call", ["name": "get_connection", "arguments": ["connection": id.uuidString]]))
    try check(mcpGet.contains("test-only-secret-beta"), "MCP get selected configuration")
    vault.projects[0].entries[1].value = "test-only-latest-value"
    let latest = try jsonString(request("tools/call", ["name": "get_connection", "arguments": ["connection": id.uuidString]]))
    try check(latest.contains("test-only-latest-value"), "reads fresh values on each request")
    let missing = request("tools/call", ["name": "get_connection", "arguments": ["connection": "missing"]])
    try check((missing["result"] as? [String: Any])?["isError"] as? Bool == true, "missing connection is a tool error")
    try check(request("tools/call", ["name": "get_connection", "arguments": ["connection": 42]])["error"] != nil, "validate tool arguments")
    try check(request("unknown-method")["error"] != nil, "reject unsupported methods")
    print("PASS: connection roles / v1 compatibility / edit preservation / metadata redaction / MCP lifecycle and tools / fresh reads")
}
