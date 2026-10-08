import Foundation
import AppKit
import Darwin

func launch(project: Project, command: [String]) throws -> Never {
    guard !command.isEmpty, !command[0].isEmpty else { throw AppError("请在 -- 后提供程序及参数。") }
    for entry in project.entries {
        guard validName(entry.name), !entry.value.contains("\0") else { throw AppError("项目包含无效变量：\(entry.name)") }
    }
    for entry in project.entries {
        guard setenv(entry.name, entry.value, 1) == 0 else { throw AppError("无法加载变量：\(entry.name)") }
    }
    let pointers = command.map { strdup($0) } + [nil]
    defer { pointers.forEach { free($0) } }
    pointers.withUnsafeBufferPointer { buffer in
        _ = execvp(command[0], UnsafeMutablePointer(mutating: buffer.baseAddress!))
    }
    let code = errno
    throw AppError("无法启动程序（\(String(cString: strerror(code)))）。请检查程序名称或路径。")
}

func runCLI(_ arguments: [String], store: KeychainStore = KeychainStore()) throws -> Never {
    guard arguments.count >= 4, arguments[0] == "run", arguments[2] == "--" else {
        throw AppError("用法：KeyPocket run '项目名称' -- 程序 [参数…]")
    }
    let vault = try store.read()
    let project = try resolveProject(arguments[1], in: vault)
    return try launch(project: project, command: Array(arguments.dropFirst(3)))
}

func selfTest() throws {
    try testAgentInterface()
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw AppError("测试失败：\(message)") }
    }
    let parsed = try parseEnv("# example\nexport FIRST='a=b#c'\nSECOND=\"line\\nnext\" # note\nEMPTY=\nLITERAL=$(touch /tmp/keypocket-must-not-execute)\nHASH=value#hash\nCOMMENT=value # note\n")
    try check(parsed.count == 6 && parsed[0].value == "a=b#c" && parsed[1].value == "line\nnext" && parsed[2].value.isEmpty && parsed[3].value.hasPrefix("$("), "dotenv values")
    try check(parsed[4].value == "value#hash" && parsed[5].value == "value", "dotenv comments")
    for invalid in ["BAD-NAME=x", "A=one\nA=two", "A='unterminated", "A=\"x\" trailing", "NO_EQUALS", "A=\0"] {
        do { _ = try parseEnv(invalid); throw AppError("测试未拒绝无效 dotenv") }
        catch let error as AppError { if error.message == "测试未拒绝无效 dotenv" { throw error } }
    }
    try check(validName("_TOKEN2") && !validName("2TOKEN"), "variable name validation")
    let store = KeychainStore(service: "local.jam.keypocket.test." + UUID().uuidString)
    defer { try? store.removeTestVault() }
    try check(tryReadEmpty(store), "empty vault")
    var vault = Vault(projects: [Project(name: "测试 project's keys", entries: [Entry(name: "KEYPOCKET_TEST_TOKEN", value: "a 'quoted' $value\nnext"), Entry(name: "KEYPOCKET_TEST_EMPTY", value: "")])])
    try store.write(vault)
    try check(try store.read() == vault, "keychain round trip")
    vault.projects[0].entries.append(Entry(name: "KEYPOCKET_TEST_UPDATED", value: "yes"))
    try store.write(vault)
    try check(try store.read() == vault, "keychain update")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = ["--test-run", store.service, "run", vault.projects[0].name, "--", "/bin/sh", "-c", "test \"$KEYPOCKET_TEST_UPDATED\" = yes && test \"${KEYPOCKET_TEST_EMPTY+x}\" = x && test \"$KEYPOCKET_TEST_EMPTY\" = '' && test \"$KEYPOCKET_TEST_TOKEN\" = " + shellQuote(vault.projects[0].entries[0].value) + " && exit 37"]
    var env = ProcessInfo.processInfo.environment
    env["KEYPOCKET_TEST_UPDATED"] = "old"
    process.environment = env
    try process.run()
    process.waitUntilExit()
    try check(process.terminationStatus == 37, "child injection and exit status")
    try check(ProcessInfo.processInfo.environment["KEYPOCKET_TEST_UPDATED"] == nil, "parent isolation")
    let mcp = Process()
    mcp.executableURL = process.executableURL
    mcp.arguments = ["--test-mcp", store.service]
    let input = Pipe(), output = Pipe()
    mcp.standardInput = input
    mcp.standardOutput = output
    try mcp.run()
    let requests: [[String: Any]] = [
        ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18", "clientInfo": ["name": "test", "version": "1"], "capabilities": [:]]],
        ["jsonrpc": "2.0", "method": "notifications/initialized"],
        ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
        ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "get_connection", "arguments": ["connection": vault.projects[0].id.uuidString]]]
    ]
    for request in requests { input.fileHandleForWriting.write(Data((try jsonString(request) + "\n").utf8)) }
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    mcp.waitUntilExit()
    let responses = try String(decoding: data, as: UTF8.self).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    try check(mcp.terminationStatus == 0 && responses.count == 3, "MCP stdio framing and clean exit")
    let body = (responses[2]["result"] as? [String: Any])?["content"] as? [[String: Any]]
    let credentials = try JSONSerialization.jsonObject(with: Data((body?.first?["text"] as? String ?? "{}").utf8)) as? [String: Any]
    try check((credentials?["environment"] as? [String: String])?["KEYPOCKET_TEST_TOKEN"] == vault.projects[0].entries[0].value, "MCP subprocess keychain read")
    let quoting = Process()
    quoting.executableURL = URL(fileURLWithPath: "/bin/sh")
    quoting.arguments = ["-c", "test " + shellQuote(vault.projects[0].name) + " = " + shellQuote(vault.projects[0].name)]
    try quoting.run(); quoting.waitUntilExit()
    try check(quoting.terminationStatus == 0, "shell quoting")
    try store.removeTestVault()
    try check(tryReadEmpty(store), "keychain deletion")
    print("PASS: dotenv parsing / invalid input / keychain create-update-delete / child-only injection / exit status / shell quoting / MCP stdio subprocess")
}

func tryReadEmpty(_ store: KeychainStore) -> Bool { (try? store.read().projects.isEmpty) == true }

@main struct Main {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args == ["--preview"] {
            NSApplication.shared.setActivationPolicy(.regular)
            KeyPocketApp.main()
            return
        }
        do {
            if args == ["--self-test"] { try selfTest(); return }
            if args.count == 2 && args[0] == "--test-mcp" && args[1].hasPrefix("local.jam.keypocket.test.") {
                MCPServer(readVault: { try KeychainStore(service: args[1]).read() }).run(); return
            }
            if args == ["mcp"] { MCPServer().run(); return }
            if args == ["list"] || args == ["list", "--json"] {
                print(try jsonString(["connections": KeychainStore().read().projects.map(\.summary)], pretty: true)); return
            }
            if args.count >= 2 && args[0] == "get" && (args.count == 2 || (args.count == 3 && args[2] == "--json")) {
                print(try jsonString(resolveProject(args[1], in: KeychainStore().read()).credentials, pretty: true)); return
            }
            if args == ["agent-instructions"] { print(agentInstructions(executable: Bundle.main.executablePath ?? CommandLine.arguments[0])); return }
            if args == ["mcp-config"] { print(try mcpConfig(executable: Bundle.main.executablePath ?? CommandLine.arguments[0])); return }
            if args.first == "--test-run", args.count > 2, args[1].hasPrefix("local.jam.keypocket.test.") {
                try runCLI(Array(args.dropFirst(2)), store: KeychainStore(service: args[1]))
            }
            if args == ["--help"] {
                print("KeyPocket — 本地 API 服务配置\n\n打开应用：KeyPocket\n列出配置（不含 Key）：KeyPocket list\n读取 URL / Key / 全部变量（含密钥）：KeyPocket get '配置 ID 或名称'\n注入变量运行程序：KeyPocket run '配置 ID 或名称' -- 程序 [参数…]\nMCP 服务：KeyPocket mcp\nMCP 连接配置：KeyPocket mcp-config\nAgent 使用说明：KeyPocket agent-instructions")
                return
            }
            try runCLI(args)
        } catch {
            FileHandle.standardError.write(Data(("KeyPocket: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
