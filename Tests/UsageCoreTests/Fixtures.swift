import Foundation

/// A temporary directory removed when the value is deallocated.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usagecore-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ name: String, _ contents: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }
}

/// Synthetic session registry file, same shape as Claude Code's (no real data).
func sessionJSON(pid: Int32, sessionId: String, cwd: String = "/tmp/demo/mi-api",
                 kind: String = "interactive", name: String? = nil) -> String {
    var fields = [
        "\"pid\": \(pid)",
        "\"sessionId\": \"\(sessionId)\"",
        "\"cwd\": \"\(cwd)\"",
        "\"kind\": \"\(kind)\"",
        "\"entrypoint\": \"cli\"",
        "\"version\": \"0.0.0\"",
    ]
    if let name { fields.append("\"name\": \"\(name)\"") }
    return "{" + fields.joined(separator: ", ") + "}"
}

/// Synthetic transcript lines.
func userLine(_ text: String = "hola") -> String {
    #"{"type":"user","isSidechain":false,"message":{"role":"user","content":"\#(text)"}}"#
}

func assistantLine(input: Int, cacheRead: Int, cacheCreation: Int,
                   model: String = "claude-opus-5-5", sidechain: Bool = false) -> String {
    #"{"type":"assistant","isSidechain":\#(sidechain),"message":{"model":"\#(model)","role":"assistant","usage":{"input_tokens":\#(input),"cache_read_input_tokens":\#(cacheRead),"cache_creation_input_tokens":\#(cacheCreation),"output_tokens":12}}}"#
}
