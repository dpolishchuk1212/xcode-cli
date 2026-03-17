import SwiftUI

#warning("TODO: fix all the broken things")

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello")
            BrokenView()
            AnotherBrokenView()
        }
        .padding()
    }
}
