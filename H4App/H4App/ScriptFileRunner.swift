#if DEBUG
import Foundation
import H4Kit
import os

/// DEBUG only, launch argument `-H4ScriptFile <name>`: reads `Documents/Scripts/<name>.json` (the command list of
/// `h4tool play`), runs every command in order through the same `GameModel` / `TownModel` methods the UI uses (the town
/// screen opens for a build / recruit / transfer on an own town and closes before the next map op; walks are waited for),
/// and writes the record of each command, unchanged, to `Documents/Logs/<name>.json` in the `h4tool play` log format.
/// `-H4ScriptPauseAt <n>` stops after command n (0-based) and keeps the screen; the records so far go to
/// `Documents/Logs/<name>.pause.json`. `-H4ScriptPauseSheet build|recruit:<building>` also opens that sheet at the pause.
@MainActor
enum ScriptFileRunner {
    private static let logger = Logger(subsystem: "fr.petrichorus.H4App", category: "script")

    private static func log(_ line: String) {
        print(line)
        logger.log("\(line, privacy: .public)")
    }

    static func runIfRequested(_ model: GameModel) async {
        guard let name = UserDefaults.standard.string(forKey: "H4ScriptFile") else { return }
        await run(model, name: name)
    }

    private static func run(_ model: GameModel, name: String) async {
        let docs = URL.documentsDirectory
        let pauseAt = UserDefaults.standard.object(forKey: "H4ScriptPauseAt") == nil ? nil : UserDefaults.standard.integer(forKey: "H4ScriptPauseAt")
        let list: [[String: Any]]
        do {
            let data = try Data(contentsOf: docs.appending(path: "Scripts/\(name).json"))
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                log("SCRIPT error \(name) not a JSON list of commands"); return
            }
            list = parsed
        } catch {
            log("SCRIPT error \(name) \(error)"); return
        }
        // wait until the map is on screen so that the walks are animated like a finger would
        for _ in 0..<100 where !model.hooks.isAttached { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .seconds(1))
        log("SCRIPT start \(name) commands=\(list.count)")
        var records: [String] = []
        for (index, command) in list.enumerated() {
            let op = command["op"] as? String ?? ""
            if ["select", "plan", "move", "endturn"].contains(op) { model.town.close() }
            do {
                records.append(try model.run(command).text)
            } catch {
                log("SCRIPT error \(name) command \(index): \(error)"); return
            }
            while model.isWalking { try? await Task.sleep(for: .milliseconds(50)) }
            await model.town.settle()
            if index == pauseAt {
                try? FileManager.default.createDirectory(at: docs.appending(path: "Logs"), withIntermediateDirectories: true)
                try? Data(("[" + records.joined(separator: ",") + "]").utf8).write(to: docs.appending(path: "Logs/\(name).pause.json"))
                if let sheet = UserDefaults.standard.string(forKey: "H4ScriptPauseSheet") {
                    if sheet == "build" { model.town.sheet = .build }
                    else if sheet.hasPrefix("recruit:"), let b = Int(sheet.dropFirst(8)) { model.town.openRecruit(b) }
                }
                try? await Task.sleep(for: .seconds(1))
                log("SCRIPT paused \(name) after command \(index)")
                return
            }
        }
        try? FileManager.default.createDirectory(at: docs.appending(path: "Logs"), withIntermediateDirectories: true)
        let text = "[" + records.joined(separator: ",") + "]"
        do { try Data(text.utf8).write(to: docs.appending(path: "Logs/\(name).json")) } catch { log("SCRIPT error \(name) write \(error)"); return }
        log("SCRIPT done \(name)")
    }
}
#endif
