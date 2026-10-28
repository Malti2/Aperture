import SwiftUI

/// Lets ContentView (Camera Control picks and presses) reach the Shop while it is on screen.
final class ShopCommands {
    var select: ((Int) -> Void)?
    var pressBegan: (() -> Void)?
    var pressEnded: (() -> Void)?
    var pressCancel: (() -> Void)?
}

/// Owned skins are stored as a comma separated list of indices.
func ownedSkins(_ raw: String) -> Set<Int> {
    Set(raw.split(separator: ",").compactMap { Int($0) })
}

struct ShopView: View {
    @Binding var bank: Int
    @Binding var ownedRaw: String
    @Binding var equipped: Int
    let haptics: Bool
    let commands: ShopCommands
    /// Demo only: skip the short delay after entering, and run the scripted motion test.
    let demoCycle: Bool
    let skipEntryDelay: Bool
    let onSelect: (Int) -> Void
    let onBack: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: Int
    @State private var dragY: CGFloat = 0
    @State private var holdProgress: CGFloat = 0
    @State private var entered: Date
    @State private var holdStart: Date? = nil
    @State private var holdToken = 0
    @State private var holdSource: HoldSource? = nil
    @State private var note = ""

    private enum HoldSource { case touch, cameraControl }
    private let holdTime = 0.9
    private let ballSpacing: CGFloat = 240
    private let ballBig: CGFloat = 170

    init(bank: Binding<Int>, ownedRaw: Binding<String>, equipped: Binding<Int>, haptics: Bool,
         initialSelection: Int, commands: ShopCommands, demoCycle: Bool, skipEntryDelay: Bool,
         onSelect: @escaping (Int) -> Void, onBack: @escaping () -> Void) {
        _bank = bank
        _ownedRaw = ownedRaw
        _equipped = equipped
        self.haptics = haptics
        self.commands = commands
        self.demoCycle = demoCycle
        self.skipEntryDelay = skipEntryDelay
        self.onSelect = onSelect
        self.onBack = onBack
        _selected = State(initialValue: min(max(initialSelection, 0), ballSkins.count - 1))
        _entered = State(initialValue: skipEntryDelay ? .distantPast : Date())
    }

    private func owned(_ i: Int) -> Bool { ownedSkins(ownedRaw).contains(i) }
    private var entryDelayPassed: Bool { Date().timeIntervalSince(entered) > 0.6 }

    // MARK: Actions

    /// Moves to a ball. One animation driver: the selected index and the drag offset settle together,
    /// and a new target simply retargets the running animation.
    private func select(_ i: Int) {
        let n = min(max(i, 0), ballSkins.count - 1)
        withAnimation(.smooth(duration: 0.38)) {
            selected = n
            dragY = 0
        }
    }

    private func equip(_ i: Int) {
        equipped = i
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func beginHold(source: HoldSource = .touch) {
        guard entryDelayPassed, !owned(selected), holdStart == nil,
              scenePhase == .active || (source == .cameraControl && scenePhase != .background) else { return }
        let cost = ballSkins[selected].cost
        if bank < cost {
            note = "Need \(cost - bank) more"
            if haptics { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            return
        }
        note = ""
        holdSource = source
        holdStart = Date()
        withAnimation(.linear(duration: holdTime)) { holdProgress = 1 }
        holdToken += 1
        let token = holdToken
        let item = selected
        if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) {
            guard holdToken == token, holdStart != nil else { return }
            guard selected == item,
                  scenePhase == .active || (source == .cameraControl && scenePhase != .background) else {
                cancelHold()
                return
            }
            purchase(item)
        }
    }

    private func cancelHold() {
        holdSource = nil
        holdStart = nil
        holdToken += 1
        if holdProgress != 0 { withAnimation(.easeOut(duration: 0.18)) { holdProgress = 0 } }
    }

    private func purchase(_ i: Int) {
        let cost = ballSkins[i].cost
        guard !owned(i), bank >= cost else { cancelHold(); return }
        bank -= cost
        ownedRaw += ",\(i)"
        equipped = i
        cancelHold()
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func pressEnded() {
        guard entryDelayPassed else { return }
        if owned(selected) {
            if equipped != selected { equip(selected) }
        } else {
            cancelHold()
        }
    }

    private func register() {
        commands.select = { select($0) }
        commands.pressBegan = { beginHold(source: .cameraControl) }
        commands.pressEnded = { pressEnded() }
        commands.pressCancel = { cancelHold() }
    }

    /// Simulator-only motion test: slow steps, fast steps, a drag-like jump, then a hold.
    private func runDemoCycle() {
        let steps: [(Double, Int)] = [(2.0, 3), (3.0, 4), (3.9, 5), (4.1, 4), (4.3, 3), (4.5, 2), (4.7, 1), (4.9, 0), (6.0, 5), (7.5, 2)]
        for (t, i) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t) { select(i) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) { beginHold() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) { cancelHold() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { beginHold() }
    }

    // MARK: Layout

    /// The ball nearest to the centre while dragging. Equals `selected` at rest.
    private var focus: Int {
        let steps = Int((-dragY / ballSpacing).rounded())
        return min(max(selected + steps, 0), ballSkins.count - 1)
    }

    /// Resists dragging past the first and last ball.
    private func band(_ t: CGFloat) -> CGFloat {
        let up = -CGFloat(ballSkins.count - 1 - selected) * ballSpacing
        let down = CGFloat(selected) * ballSpacing
        if t < up { return up + (t - up) * 0.3 }
        if t > down { return down + (t - down) * 0.3 }
        return t
    }

    private var shopDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if holdStart != nil { cancelHold() }
                dragY = band(v.translation.height)
            }
            .onEnded { v in
                let t = v.translation.height * 0.5 + v.predictedEndTranslation.height * 0.5
                select(selected + Int((-t / ballSpacing).rounded()))
            }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            GeometryReader { geo in
                let cx = geo.size.width / 2
                let cy = geo.size.height * 0.34
                GlassEffectContainer(spacing: 24) {
                    ZStack {
                        ForEach(0..<ballSkins.count, id: \.self) { i in
                            let pos = CGFloat(i - selected) * ballSpacing + dragY
                            let d = abs(pos) / ballSpacing
                            let scale = 1 - 0.58 * min(d, 1)
                            let alpha = max(0, 1 - 0.62 * min(d, 1) - 0.4 * max(0, d - 1))
                            Circle()
                                .fill(.clear)
                                .frame(width: ballBig, height: ballBig)
                                .glassEffect(.regular.tint(ballSkins[i].color.opacity(owned(i) ? 0.9 : 0.55)).interactive(), in: .circle)
                                .overlay(Circle().fill(Color.black.opacity(0.4 * min(d, 1))).allowsHitTesting(false))
                                .scaleEffect(scale)
                                .opacity(alpha)
                                .offset(y: pos)
                                .onTapGesture { if i != selected { select(i) } }
                        }
                    }
                    .frame(width: geo.size.width, height: 0)
                    .position(x: cx, y: cy)
                }
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ballBig + 26, height: ballBig + 26)
                    .position(x: cx, y: cy)
                    .allowsHitTesting(false)
                VStack(spacing: 6) {
                    Text(ballSkins[focus].name)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .id(focus)
                        .transition(.opacity)
                    HStack(spacing: 6) {
                        if owned(focus) {
                            Text(equipped == focus ? "Equipped" : "Owned")
                        } else {
                            Image(systemName: "bolt.fill")
                            Text("\(ballSkins[focus].cost)").monospacedDigit()
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                }
                .animation(.smooth(duration: 0.25), value: focus)
                .position(x: cx, y: cy + ballBig / 2 + 62)
                .allowsHitTesting(false)
                VStack(spacing: 8) {
                    ForEach(0..<ballSkins.count, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(i == focus ? 0.95 : 0.22))
                            .frame(width: 6, height: i == focus ? 18 : 6)
                    }
                }
                .animation(.smooth(duration: 0.25), value: focus)
                .position(x: geo.size.width - 34, y: cy)
            }
            .contentShape(Rectangle())
            .gesture(shopDrag)
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    action
                    Spacer()
                    Button("Back") {
                        cancelHold()
                        onBack()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 54)
            }
        }
        .onAppear {
            register()
            onSelect(selected)
            if demoCycle { runDemoCycle() }
        }
        .onDisappear {
            cancelHold()
            commands.select = nil
            commands.pressBegan = nil
            commands.pressEnded = nil
            commands.pressCancel = nil
        }
        .onChange(of: haptics) { _, _ in register() }
        .onChange(of: focus) { _, _ in
            if haptics { UISelectionFeedbackGenerator().selectionChanged() }
        }
        .onChange(of: selected) { _, new in
            cancelHold()
            note = ""
            onSelect(new)
        }
        .onChange(of: scenePhase) { _, new in
            // Only Camera Control may continue across its transient inactive overlay.
            if new == .background || (new != .active && holdSource != .cameraControl) { cancelHold() }
        }
    }

    private var action: some View {
        let isOwned = owned(selected)
        return VStack(alignment: .leading, spacing: 10) {
            if isOwned {
                Text(equipped == selected ? "Equipped" : "Click to equip")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .onTapGesture { if equipped != selected { equip(selected) } }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("\(ballSkins[selected].cost)").monospacedDigit()
                    Text("Hold to unlock")
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .onLongPressGesture(minimumDuration: 10, pressing: { down in
                    if down { beginHold() } else { cancelHold() }
                }, perform: {})
                if !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
