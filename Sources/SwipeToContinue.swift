import SwiftUI

/// Slide-to-continue control in the style of the iOS call and alarm sliders.
struct SwipeToContinue: View {
    let onDone: () -> Void
    @State private var offset: CGFloat = 0
    private let knob: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let maxX = max(geo.size.width - knob - 8, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                    .glassEffect(.regular, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                Text("swipe to continue")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knob * 0.6)
                    .opacity(1 - Double(offset / maxX))
                Circle().fill(Color.white.opacity(0.92))
                    .frame(width: knob, height: knob)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .overlay(Image(systemName: "chevron.right").font(.title2.weight(.bold)).foregroundStyle(.black.opacity(0.8)))
                    .offset(x: 4 + offset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in offset = min(max(v.translation.width, 0), maxX) }
                            .onEnded { _ in
                                let done = offset > maxX * 0.85
                                withAnimation(.smooth) { offset = 0 }
                                if done { onDone() }
                            }
                    )
            }
        }
        .frame(height: knob + 8)
    }
}
