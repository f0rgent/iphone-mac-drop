import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PhotoItem: Identifiable {
    let id = UUID()
    let fileName: String
    let data: Data
    let image: UIImage
}

struct ContentView: View {
    @EnvironmentObject var link: PeerLink
    @EnvironmentObject var beacon: BLEBeacon

    @AppStorage("macEdge") private var macEdgeRaw = DropEdge.top.rawValue
    @State private var picks: [PhotosPickerItem] = []
    @State private var photos: [PhotoItem] = []

    // Drag state: the photo being dragged floats above everything.
    @State private var dragging: PhotoItem?
    @State private var dragPoint: CGPoint = .zero
    @State private var flying = false
    @State private var status = ""

    private var macEdge: DropEdge { DropEdge(rawValue: macEdgeRaw) ?? .top }
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    var body: some View {
        GeometryReader { geo in
            let screen = geo.frame(in: .global)
            ZStack {
                VStack(spacing: 12) {
                    header
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(photos) { item in
                                thumb(item)
                                    .opacity(dragging?.id == item.id ? 0 : 1)
                                    .gesture(drag(item, screen: screen))
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                edgeHint(screen: screen)
                if let item = dragging {
                    thumb(item)
                        .frame(width: 130, height: 130)
                        .shadow(radius: 12)
                        .scaleEffect(flying ? 0.8 : 1.1)
                        .position(x: dragPoint.x - screen.minX, y: dragPoint.y - screen.minY)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: picks) { _, newPicks in Task { await load(newPicks) } }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(link.connectedPeers.isEmpty ? .orange : .green).frame(width: 10, height: 10)
                Text(link.connectedPeers.first.map { "Connected: \($0)" } ?? "Looking for Mac…")
                    .font(.subheadline)
                Spacer()
                PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
            }
            Picker("Mac is on the", selection: $macEdgeRaw) {
                Text("Mac ↑ top").tag(DropEdge.top.rawValue)
                Text("← left").tag(DropEdge.left.rawValue)
                Text("right →").tag(DropEdge.right.rawValue)
            }
            .pickerStyle(.segmented)
            Text(status.isEmpty ? "Drag a photo and flick it toward the Mac · \(beacon.state)" : status)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Soft glow on the edge the Mac is on, so the user knows where to flick.
    private func edgeHint(screen: CGRect) -> some View {
        let glow = LinearGradient(colors: [.cyan.opacity(dragging == nil ? 0.15 : 0.55), .clear],
                                  startPoint: start, endPoint: end)
        return Rectangle().fill(glow)
            .frame(width: macEdge == .top ? nil : 40, height: macEdge == .top ? 40 : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.2), value: dragging?.id)
    }

    private var alignment: Alignment { macEdge == .top ? .top : macEdge == .left ? .leading : .trailing }
    private var start: UnitPoint { macEdge == .top ? .top : macEdge == .left ? .leading : .trailing }
    private var end: UnitPoint { macEdge == .top ? .bottom : macEdge == .left ? .trailing : .leading }

    private func thumb(_ item: PhotoItem) -> some View {
        Image(uiImage: item.image)
            .resizable()
            .scaledToFill()
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }

    private func drag(_ item: PhotoItem, screen: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                if dragging == nil { dragging = item; flying = false }
                dragPoint = v.location
            }
            .onEnded { v in
                let vel = v.velocity
                let predicted = v.predictedEndLocation
                let flicked: Bool
                switch macEdge {
                case .top: flicked = predicted.y < screen.minY && vel.height < -250
                case .left: flicked = predicted.x < screen.minX && vel.width < -250
                case .right: flicked = predicted.x > screen.maxX && vel.width > 250
                }
                if flicked {
                    send(item, release: v.location, velocity: vel, screen: screen)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragging = nil }
                }
            }
    }

    private func send(_ item: PhotoItem, release: CGPoint, velocity: CGSize, screen: CGRect) {
        // Where along the edge it left: project the release point onto the exit edge.
        let position: Double
        switch macEdge {
        case .top: position = Double((release.x - screen.minX) / screen.width)
        case .left, .right: position = Double((release.y - screen.minY) / screen.height)
        }
        let msg = DropMessage(fileName: item.fileName, data: item.data, edge: macEdge,
                              position: min(max(position, 0), 1),
                              velocityX: velocity.width, velocityY: velocity.height)
        do {
            try link.send(msg)
            status = "Sent \(item.fileName) at \(Int(msg.speed)) pt/s"
        } catch {
            status = "Not sent: \(error.localizedDescription)"
        }
        // Fly the photo off screen along the flick.
        let t = 0.35
        flying = true
        withAnimation(.easeIn(duration: t)) {
            dragPoint = CGPoint(x: release.x + velocity.width * t, y: release.y + velocity.height * t)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            dragging = nil
            flying = false
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [PhotoItem] = []
        for (i, pick) in items.enumerated() {
            guard let data = try? await pick.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let ext = pick.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let stamp = Int(Date().timeIntervalSince1970)
            loaded.append(PhotoItem(fileName: "f0drop-\(stamp)-\(i + 1).\(ext)", data: data,
                                    image: image.preparingThumbnail(of: CGSize(width: 400, height: 400)) ?? image))
        }
        await MainActor.run { photos = loaded }
    }
}
