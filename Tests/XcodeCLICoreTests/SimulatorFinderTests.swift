import Testing
import Foundation
@testable import XcodeCLICore

@Suite("SimulatorFinder")
struct SimulatorFinderTests {

    // MARK: - Parsing simctl JSON

    @Test func parsesDeviceFromSimctlJSON() {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              {
                "udid": "AAA-BBB",
                "name": "iPhone 16",
                "state": "Booted",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
              }
            ]
          }
        }
        """
        let devices = SimulatorFinder.parseDevices(from: json)
        #expect(devices.count == 1)
        #expect(devices[0].udid == "AAA-BBB")
        #expect(devices[0].name == "iPhone 16")
        #expect(devices[0].state == "Booted")
        #expect(devices[0].isAvailable == true)
        #expect(devices[0].runtime == "com.apple.CoreSimulator.SimRuntime.iOS-18-2")
        #expect(devices[0].deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-16")
    }

    @Test func parsesMultipleRuntimesAndDevices() {
        let json = makeJSON(runtimes: [
            ("com.apple.CoreSimulator.SimRuntime.iOS-17-5", [
                device(udid: "A", name: "iPhone 15", state: "Shutdown"),
            ]),
            ("com.apple.CoreSimulator.SimRuntime.iOS-18-2", [
                device(udid: "B", name: "iPhone 16", state: "Booted"),
                device(udid: "C", name: "iPad Pro", state: "Shutdown",
                       type: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4"),
            ]),
        ])
        let devices = SimulatorFinder.parseDevices(from: json)
        #expect(devices.count == 3)
    }

    @Test func ignoresUnavailableDevices() {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
              {
                "udid": "A",
                "name": "iPhone 16",
                "state": "Shutdown",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
              },
              {
                "udid": "B",
                "name": "iPhone 16 (Unavailable)",
                "state": "Shutdown",
                "isAvailable": false,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
              }
            ]
          }
        }
        """
        let devices = SimulatorFinder.parseDevices(from: json)
        #expect(devices.count == 1)
        #expect(devices[0].udid == "A")
    }

    @Test func returnsEmptyForInvalidJSON() {
        #expect(SimulatorFinder.parseDevices(from: "not json").isEmpty)
        #expect(SimulatorFinder.parseDevices(from: "{}").isEmpty)
        #expect(SimulatorFinder.parseDevices(from: "").isEmpty)
    }

    // MARK: - Selection: iOS version

    @Test func picksHighestIOSVersion() {
        let devices = [
            sim(udid: "A", name: "iPhone 15", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-5"),
            sim(udid: "B", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
            sim(udid: "C", name: "iPhone 14", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-16-4"),
        ]
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "B")
    }

    @Test func handlesHighMajorVersions() {
        let devices = [
            sim(udid: "A", name: "iPhone 15", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-9-3"),
            sim(udid: "B", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-0"),
        ]
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "B")
    }

    // MARK: - Selection: prefer booted

    @Test func prefersBootedOverShutdown() {
        let devices = [
            sim(udid: "A", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2", state: "Shutdown"),
            sim(udid: "B", name: "iPhone 16 Pro", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2", state: "Booted"),
        ]
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "B")
    }

    // MARK: - Selection: prefer iPhone

    @Test func prefersIPhoneOverIPad() {
        let devices = [
            sim(udid: "A", name: "iPad Pro", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
                type: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4"),
            sim(udid: "B", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
                type: "com.apple.CoreSimulator.SimDeviceType.iPhone-16"),
        ]
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "B")
    }

    @Test func fallsBackToIPadIfNoIPhone() {
        let devices = [
            sim(udid: "A", name: "iPad Pro", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
                type: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4"),
        ]
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "A")
    }

    // MARK: - Selection: non-iOS runtimes

    @Test func ignoresNonIOSRuntimes() {
        let devices = [
            sim(udid: "A", name: "Apple Watch", runtime: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2",
                type: "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10"),
            sim(udid: "B", name: "Apple TV", runtime: "com.apple.CoreSimulator.SimRuntime.tvOS-18-2",
                type: "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K"),
            sim(udid: "C", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
        ]
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "C")
    }

    @Test func returnsNilWhenOnlyNonIOSAvailable() {
        let devices = [
            sim(udid: "A", name: "Apple Watch", runtime: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2",
                type: "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10"),
        ]
        #expect(SimulatorFinder.findBest(from: devices) == nil)
    }

    // MARK: - Selection: explicit override

    @Test func findsByExactName() {
        let devices = [
            sim(udid: "A", name: "iPhone 15", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-5"),
            sim(udid: "B", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
        ]
        let found = SimulatorFinder.findBest(from: devices, matching: "iPhone 15")
        #expect(found?.udid == "A")
    }

    @Test func findsByUDID() {
        let devices = [
            sim(udid: "AAAA-BBBB", name: "iPhone 15", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-5"),
            sim(udid: "CCCC-DDDD", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
        ]
        let found = SimulatorFinder.findBest(from: devices, matching: "AAAA-BBBB")
        #expect(found?.udid == "AAAA-BBBB")
    }

    @Test func matchingOverridesAutoSelection() {
        let devices = [
            sim(udid: "A", name: "iPhone 14", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-16-4"),
            sim(udid: "B", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
        ]
        // Explicit match picks iPhone 14 even though 16 is newer
        let found = SimulatorFinder.findBest(from: devices, matching: "iPhone 14")
        #expect(found?.udid == "A")
    }

    @Test func returnsNilWhenMatchNotFound() {
        let devices = [
            sim(udid: "A", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"),
        ]
        #expect(SimulatorFinder.findBest(from: devices, matching: "iPhone 99") == nil)
    }

    // MARK: - Edge cases

    @Test func returnsNilForEmptyList() {
        #expect(SimulatorFinder.findBest(from: []) == nil)
    }

    @Test func combinedPriority_versionThenBootedThenIPhone() {
        let devices = [
            sim(udid: "A", name: "iPad Air", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
                state: "Booted", type: "com.apple.CoreSimulator.SimDeviceType.iPad-Air"),
            sim(udid: "B", name: "iPhone 16", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-2",
                state: "Shutdown", type: "com.apple.CoreSimulator.SimDeviceType.iPhone-16"),
            sim(udid: "C", name: "iPhone 15", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-5",
                state: "Booted", type: "com.apple.CoreSimulator.SimDeviceType.iPhone-15"),
        ]
        // iOS 18.2 iPhone (even shutdown) beats iOS 18.2 iPad (booted) and iOS 17.5 iPhone (booted)
        let best = SimulatorFinder.findBest(from: devices)
        #expect(best?.udid == "B")
    }

    // MARK: - Version parsing

    @Test func parsesIOSVersionFromRuntime() {
        let v1 = SimulatorFinder.iosVersion(from: "com.apple.CoreSimulator.SimRuntime.iOS-18-2")
        #expect(v1?.major == 18 && v1?.minor == 2)

        let v2 = SimulatorFinder.iosVersion(from: "com.apple.CoreSimulator.SimRuntime.iOS-17-5")
        #expect(v2?.major == 17 && v2?.minor == 5)

        let v3 = SimulatorFinder.iosVersion(from: "com.apple.CoreSimulator.SimRuntime.iOS-9-3")
        #expect(v3?.major == 9 && v3?.minor == 3)

        #expect(SimulatorFinder.iosVersion(from: "com.apple.CoreSimulator.SimRuntime.watchOS-11-2") == nil)
        #expect(SimulatorFinder.iosVersion(from: "garbage") == nil)
    }

    // MARK: - Helpers

    private func sim(
        udid: String,
        name: String,
        runtime: String,
        state: String = "Shutdown",
        type: String = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
    ) -> SimulatorDevice {
        SimulatorDevice(udid: udid, name: name, state: state, isAvailable: true,
                        runtime: runtime, deviceTypeIdentifier: type)
    }

    private func device(
        udid: String,
        name: String,
        state: String,
        type: String = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
    ) -> (String, String, String, Bool, String) {
        (udid, name, state, true, type)
    }

    private func makeJSON(runtimes: [(String, [(String, String, String, Bool, String)])]) -> String {
        var deviceBlocks: [String] = []
        for (runtime, devs) in runtimes {
            let items = devs.map { (udid, name, state, available, type) in
                """
                    {"udid":"\(udid)","name":"\(name)","state":"\(state)","isAvailable":\(available),"deviceTypeIdentifier":"\(type)"}
                """
            }.joined(separator: ",\n")
            deviceBlocks.append("    \"\(runtime)\": [\n\(items)\n    ]")
        }
        return "{\n  \"devices\": {\n\(deviceBlocks.joined(separator: ",\n"))\n  }\n}"
    }
}
