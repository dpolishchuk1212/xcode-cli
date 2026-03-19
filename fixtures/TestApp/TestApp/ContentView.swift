import SwiftUI
import os
import Foundation

private let logger = Logger(subsystem: "com.xcode-cli.TestApp", category: "UI")
private let osLog = OSLog(subsystem: "com.xcode-cli.TestApp", category: "Legacy")

struct ContentView: View {
    @State private var tapCount = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Button("Log to Console (\(tapCount))") {
                tapCount += 1

                // 1. Logger (modern os.Logger API)
                logger.info("Logger.info: tap #\(tapCount)")
                logger.debug("Logger.debug: tap #\(tapCount)")
                logger.error("Logger.error: tap #\(tapCount)")

                // 2. os_log (C-style os API)
                os_log(.info, log: osLog, "os_log info: tap #%d", tapCount)

                // 3. NSLog (Foundation)
                NSLog("NSLog: tap #%d", tapCount)

                // 4. print (stdout)
                print("print(): tap #\(tapCount)")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            logger.info("ContentView appeared")
            NSLog("NSLog: ContentView appeared")
            print("print(): ContentView appeared")
        }
    }
}

#Preview {
    ContentView()
}
