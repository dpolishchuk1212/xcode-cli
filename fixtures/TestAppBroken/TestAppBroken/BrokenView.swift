import SwiftUI

struct BrokenView: View {
    // Error: wrong type assignment
    let count: Int = "not a number"

    var body: some View {
        Text("Count: \(count)")
    }
}
