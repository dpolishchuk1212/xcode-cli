import Foundation

public struct SimulatorDevice: Sendable, Equatable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool
    public let runtime: String
    public let deviceTypeIdentifier: String

    public var isBooted: Bool { state == "Booted" }
    public var isIPhone: Bool { deviceTypeIdentifier.contains("iPhone") }

    public init(udid: String, name: String, state: String, isAvailable: Bool,
                runtime: String, deviceTypeIdentifier: String) {
        self.udid = udid
        self.name = name
        self.state = state
        self.isAvailable = isAvailable
        self.runtime = runtime
        self.deviceTypeIdentifier = deviceTypeIdentifier
    }
}

public enum SimulatorFinder {

    /// Parse `xcrun simctl list devices -j` output into a flat device list.
    /// Only returns devices where `isAvailable == true`.
    public static func parseDevices(from json: String) -> [SimulatorDevice] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = root["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var result: [SimulatorDevice] = []
        for (runtime, devices) in devicesByRuntime {
            for d in devices {
                guard let available = d["isAvailable"] as? Bool, available,
                      let udid = d["udid"] as? String,
                      let name = d["name"] as? String,
                      let state = d["state"] as? String,
                      let typeId = d["deviceTypeIdentifier"] as? String
                else { continue }

                result.append(SimulatorDevice(
                    udid: udid, name: name, state: state,
                    isAvailable: true, runtime: runtime,
                    deviceTypeIdentifier: typeId
                ))
            }
        }
        return result
    }

    /// Find the best simulator for running an iOS app.
    ///
    /// If `matching` is provided, finds by name or UDID (exact match).
    /// Otherwise auto-selects with priority: iOS runtime → highest version → iPhone over iPad → booted over shutdown.
    public static func findBest(from devices: [SimulatorDevice], matching: String? = nil) -> SimulatorDevice? {
        if let query = matching {
            return devices.first { $0.name == query || $0.udid == query }
        }

        // Filter to iOS runtimes only
        let ios = devices.filter { iosVersion(from: $0.runtime) != nil }
        guard !ios.isEmpty else { return nil }

        return ios.sorted { a, b in
            let va = iosVersion(from: a.runtime)!
            let vb = iosVersion(from: b.runtime)!

            // 1. Higher iOS version first
            if va.major != vb.major { return va.major > vb.major }
            if va.minor != vb.minor { return va.minor > vb.minor }

            // 2. iPhone before non-iPhone
            if a.isIPhone != b.isIPhone { return a.isIPhone }

            // 3. Booted before shutdown
            if a.isBooted != b.isBooted { return a.isBooted }

            return false
        }.first
    }

    /// Parse iOS version from a runtime identifier string.
    /// e.g. `"com.apple.CoreSimulator.SimRuntime.iOS-18-2"` → `(18, 2)`
    /// Returns nil for non-iOS runtimes (watchOS, tvOS, xrOS).
    public static func iosVersion(from runtime: String) -> (major: Int, minor: Int)? {
        // Match "iOS-XX-Y" at the end of the runtime string
        guard let match = runtime.wholeMatch(of: /.*\.iOS-(\d+)-(\d+)$/),
              let major = Int(match.1),
              let minor = Int(match.2)
        else { return nil }
        return (major, minor)
    }
}
