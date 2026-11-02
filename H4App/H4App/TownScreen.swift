import H4Kit
import SwiftUI

/// The seven resources of a player as a thin bar (shared by the map HUD and the town screen).
struct ResourceBar: View {
    let amounts: [Int]
    var background: Color = .black.opacity(0.35)

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(H4SessionResources.names.enumerated()), id: \.offset) { i, name in
                VStack(spacing: 0) {
                    Text(name.capitalized).font(.caption2).foregroundStyle(.white.opacity(0.65))
                    Text("\(amounts[i])").font(.callout.monospacedDigit().bold()).foregroundStyle(.white)
                }
            }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 4)
        .background(background)
    }
}

private enum Names {
    static let factions = H4GameIdentifiers.factionNames.map(\.capitalized)
}

/// Cost of something as text with the resources the player lacks in red.
private struct CostLine: View {
    let cost: [Int]
    let have: [Int]
    var times = 1

    var body: some View {
        let parts = cost.enumerated().filter { $0.element > 0 }
        if parts.isEmpty {
            Text("Free").font(.callout).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                ForEach(parts, id: \.offset) { i, v in
                    let need = v * times
                    Text("\(need) \(H4SessionResources.names[i].capitalized)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(need > have[i] ? Color.red : Color.white.opacity(0.9))
                }
            }
        }
    }
}

/// Shows the town screen over the map while a town is open.
struct TownHost: View {
    @ObservedObject var model: GameModel
    @ObservedObject var town: TownModel

    var body: some View {
        if town.current != nil {
            TownScreen(model: model, town: town).transition(.opacity)
        }
    }
}

/// Full-screen town: the scene on top (tap a building or the ground), garrison and visiting hero below.
struct TownScreen: View {
    @ObservedObject var model: GameModel
    @ObservedObject var town: TownModel

    private var state: H4TownState? { town.town }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                sceneArea
                bottomPanel
            }
            if let text = town.notice {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 250)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if let sheet = town.sheet {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { town.sheet = nil }
                switch sheet {
                case .build: BuildPanel(model: model, town: town)
                case .recruit(let b): RecruitPanel(model: model, town: town, building: b)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.default, value: town.notice)
        .animation(.easeOut(duration: 0.15), value: town.sheet)
    }

    // MARK: top bar

    private var title: String {
        guard let t = state else { return "" }
        let name = t.name.isEmpty ? "Town \(t.index)" : t.name
        return "\(name) — \(Names.factions[t.faction])"
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { town.close() } label: {
                Label("Exit", systemImage: "xmark.circle.fill").font(.headline).padding(.horizontal, 6).frame(minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            Text(title).font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
            Spacer()
            Button { town.sheet = .build } label: {
                Label("Build", systemImage: "hammer.fill").font(.headline).padding(.horizontal, 6).frame(minHeight: 36)
            }
            .buttonStyle(.bordered)
            HStack(spacing: 6) {
                Circle().fill(Self.colours[safe: model.player] ?? .gray).frame(width: 14, height: 14)
                Text("\(model.playerName) · Day \(model.day)").font(.subheadline.monospacedDigit()).foregroundStyle(.white)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.black.opacity(0.6))
    }

    static let colours: [Color] = [.red, .blue, .green, .orange, .purple, .teal]

    // MARK: scene

    private var sceneArea: some View {
        GeometryReader { geo in
            let scale = geo.size.width / CGFloat(H4TownRender.sceneWidth)
            ScrollView(.vertical, showsIndicators: false) {
                if let image = town.image {
                    Image(decorative: image, scale: 1)
                        .resizable().interpolation(.high)
                        .frame(width: geo.size.width, height: CGFloat(H4TownRender.sceneHeight) * scale)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { p in
                            town.tapScene(x: Int(p.x / scale), y: Int(p.y / scale))
                        }
                } else if let error = town.sceneError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text("The town scene cannot be drawn").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .foregroundStyle(.white)
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().tint(.white).frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .defaultScrollAnchor(.bottom)
        }
        .background(Color.black)
    }

    // MARK: bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            ResourceBar(amounts: model.resources, background: .black.opacity(0.0))
            VStack(spacing: 8) {
                let _ = town.revision
                SlotRow(title: "Garrison", model: model, town: town, army: nil, row: state?.garrison, enabled: true)
                if let v = state?.visitingArmy, let row = model.session.slots(army: v) {
                    SlotRow(title: "Visiting hero", model: model, town: town, army: v, row: row, enabled: true)
                } else {
                    SlotRow(title: "Visiting hero", model: model, town: town, army: nil, row: nil, enabled: false)
                }
            }
            .padding(.horizontal).padding(.bottom, 10)
        }
        .background(.regularMaterial)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Seven slots of the garrison or of the visiting army.
private struct SlotRow: View {
    let title: String
    @ObservedObject var model: GameModel
    @ObservedObject var town: TownModel
    let army: Int?
    let row: [H4SlotStack]?
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            ForEach(0..<7, id: \.self) { slot in
                SlotCell(model: model, town: town, army: army, slot: slot, stack: row.map { $0[slot] }, enabled: enabled)
            }
        }
    }
}

private struct SlotCell: View {
    let model: GameModel
    @ObservedObject var town: TownModel
    let army: Int?
    let slot: Int
    let stack: H4SlotStack?
    let enabled: Bool

    private var isPicked: Bool { enabled && town.picked?.army == army && town.picked?.slot == slot }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isPicked ? Color.accentColor.opacity(0.35) : Color.white.opacity(enabled ? 0.10 : 0.04))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isPicked ? Color.accentColor : Color.white.opacity(0.25),
                              style: StrokeStyle(lineWidth: isPicked ? 3 : 1, dash: (stack?.creature ?? -1) == -1 ? [4, 3] : []))
            content
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { town.tapSlot(army: army, slot: slot) } }
        .onLongPressGesture(minimumDuration: 0.45) { if enabled { town.longPressSlot(army: army, slot: slot) } }
        .accessibilityLabel(label)
    }

    private var label: String {
        guard let s = stack else { return "No slot" }
        if s.creature == -2 { return "Hero" }
        if s.creature == -1 { return "Empty slot" }
        return "\(s.count) \(model.session.creatureName(s.creature, plural: s.count != 1))"
    }

    @ViewBuilder private var content: some View {
        if let s = stack, s.creature == -2 {
            Label("Hero", systemImage: "person.fill").font(.callout.weight(.semibold)).foregroundStyle(.white)
        } else if let s = stack, s.creature >= 0 {
            VStack(spacing: 1) {
                Text("\(s.count)" + (isPicked && town.picked?.half == true ? "  (½)" : ""))
                    .font(.title3.monospacedDigit().bold()).foregroundStyle(.white)
                Text(model.session.creatureName(s.creature, plural: s.count != 1))
                    .font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Build panel

private struct BuildPanel: View {
    @ObservedObject var model: GameModel
    @ObservedObject var town: TownModel

    var body: some View {
        let _ = town.revision
        if let t = town.town {
            let session = model.session
            let ids = H4TownRules.gridBuildings(faction: t.faction)
            VStack(spacing: 0) {
                HStack {
                    Text("Build in \(t.name.isEmpty ? "Town \(t.index)" : t.name)").font(.title2.bold())
                    Spacer()
                    Button { town.sheet = nil } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 48, height: 48)
                }
                .padding(.horizontal, 20).padding(.top, 10)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(ids, id: \.self) { id in
                            card(t, id, session)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: 940, maxHeight: 720)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
    }

    private func card(_ t: H4TownState, _ id: Int, _ session: H4GameSession) -> some View {
        let status = session.buildStatus(town: t.index, building: id)
        let cost = session.buildingCost(faction: t.faction, building: id) ?? Array(repeating: 0, count: 7)
        let canBuild = status == nil
        return VStack(spacing: 8) {
            Group {
                if let img = town.thumbnail(faction: t.faction, building: id) {
                    Image(decorative: img, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "building.2").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 96).frame(maxWidth: .infinity)
            .opacity(status == "already-built" ? 0.55 : 1)
            Text(session.buildingName(faction: t.faction, building: id))
                .font(.headline).multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
            CostLine(cost: cost, have: model.resources)
            Button { town.build(id) } label: {
                Text(H4TownLabels.build(status)).font(.callout.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canBuild)
            #if DEBUG
            if let status { Text(status).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
            #endif
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Recruit panel

private struct RecruitPanel: View {
    @ObservedObject var model: GameModel
    @ObservedObject var town: TownModel
    let building: Int

    var body: some View {
        let _ = town.revision
        if let t = town.town, let p = model.session.recruitPreview(town: t.index, building: building) {
            let session = model.session
            let unit = session.creatureCost(p.creature) ?? Array(repeating: 0, count: 7)
            let count = min(max(town.recruitCount, 0), p.maxAffordable)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(session.creatureName(p.creature, plural: true)).font(.title2.bold())
                    Spacer()
                    Button { town.sheet = nil } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).frame(width: 48, height: 48)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Available").foregroundStyle(.secondary)
                    Text("\(p.available)").font(.title3.monospacedDigit().bold())
                    Spacer()
                    Text("Unit cost").foregroundStyle(.secondary)
                    CostLine(cost: unit, have: model.resources)
                }
                if p.maxAffordable > 0 {
                    HStack(spacing: 16) {
                        Stepper("", value: Binding(get: { count }, set: { town.recruitCount = $0 }), in: 0...p.maxAffordable)
                            .labelsHidden().scaleEffect(1.25).frame(width: 130)
                        Slider(value: Binding(get: { Double(count) }, set: { town.recruitCount = Int($0.rounded()) }),
                               in: 0...Double(p.maxAffordable), step: 1)
                        Text("\(count)").font(.title2.monospacedDigit().bold()).frame(minWidth: 56, alignment: .trailing)
                    }
                    HStack {
                        Text("Total").foregroundStyle(.secondary)
                        CostLine(cost: unit, have: model.resources, times: max(count, 1))
                        Spacer()
                        Button("Max") { town.recruitCount = p.maxAffordable }.buttonStyle(.bordered).controlSize(.large)
                    }
                } else {
                    Text(p.available == 0 ? "No creatures available" : "Cannot recruit any right now (resources or room)")
                        .foregroundStyle(.secondary)
                }
                Button { town.recruit(building: building, count: count) } label: {
                    Text(count > 0 ? "Recruit \(count)" : "Recruit").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).disabled(count < 1)
            }
            .padding(20)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
    }
}

// MARK: - Town list

/// The towns of the current player, opened from the HUD.
struct TownListSheet: View {
    @ObservedObject var model: GameModel
    let choose: (Int) -> Void

    var body: some View {
        NavigationStack {
            let towns = model.ownTowns
            Group {
                if towns.isEmpty {
                    ContentUnavailableView("No town", systemImage: "building.2", description: Text("\(model.playerName) owns no town."))
                } else {
                    List(towns, id: \.index) { t in
                        Button { choose(t.index) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.columns.fill").font(.title2).frame(width: 36)
                                VStack(alignment: .leading) {
                                    Text(t.name.isEmpty ? "Town \(t.index)" : t.name).font(.headline)
                                    Text("\(Names.factions[t.faction]) · \(H4GameIdentifiers.tierNames[H4TownRules.tier(mask: t.mask)])")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 52)
                        }
                    }
                }
            }
            .navigationTitle("Towns")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
