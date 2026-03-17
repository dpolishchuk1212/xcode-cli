import SwiftUI
import os

private let logger = Logger(subsystem: "com.xcode-cli.TestApp", category: "UI")

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
                logger.info("Button tapped: count = \(tapCount)")
                logger.debug("Debug info: timestamp = \(Date())")
                print("print() output: tap #\(tapCount)")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            logger.info("ContentView appeared")
        }
    }
}

#Preview {
    ContentView()
}
