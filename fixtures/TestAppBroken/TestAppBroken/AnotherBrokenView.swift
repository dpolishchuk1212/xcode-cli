import SwiftUI

#warning("This view needs a complete rewrite")

struct AnotherBrokenView: View {
    var body: some View {
        // Error: undefined symbol
        Text(missingTitle)
    }
}
