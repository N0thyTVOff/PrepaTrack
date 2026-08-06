import Capacitor
import Foundation

@objc(DurableStoragePlugin)
public final class DurableStoragePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DurableStoragePlugin"
    public let jsName = "DurableStorage"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "save", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "load", returnType: CAPPluginReturnPromise),
    ]

    private var backupURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("PrepaTrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("durable-backup.json")
    }

    @objc func save(_ call: CAPPluginCall) {
        guard let value = call.getString("data"), let data = value.data(using: .utf8) else {
            call.reject("Sauvegarde native invalide")
            return
        }
        do {
            try data.write(to: backupURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            call.resolve()
        } catch {
            call.reject("Impossible d’écrire la sauvegarde native", nil, error)
        }
    }

    @objc func load(_ call: CAPPluginCall) {
        guard let data = try? Data(contentsOf: backupURL),
              let value = String(data: data, encoding: .utf8) else {
            call.resolve(["data": NSNull()])
            return
        }
        call.resolve(["data": value])
    }
}
