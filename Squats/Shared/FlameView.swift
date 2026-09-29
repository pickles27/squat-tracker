import SwiftUI

/// Animated streak flame; grey and still when the streak is zero.
/// PLACEHOLDER: owned by the Home & Programs workstream; also used by workout summary and sign-in.
struct FlameView: View {
    var isLit: Bool

    var body: some View {
        Image(systemName: "flame.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(isLit ? Color.orange : Color.gray)
    }
}
