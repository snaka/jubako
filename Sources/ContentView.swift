import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Jubako")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            Text("macOS disk analyzer — design draft")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    ContentView()
}
