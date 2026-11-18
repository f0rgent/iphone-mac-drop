import SwiftUI
import AppKit

/// A photo in flight on the Mac screen.
struct Arrival: Identifiable {
    let id = UUID()
    let image: NSImage
    let side: PhoneSide
    let position: Double      // 0...1 down the edge
    let along: Double         // pt/s into the screen
    let lateral: Double       // pt/s along the edge (down = +)
}

final class ArrivalStore: ObservableObject {
    @Published var items: [Arrival] = []
}

/// Borderless, transparent, click-through panel over the whole main screen.
final class OverlayController {
    private var panel: NSPanel?
    let store = ArrivalStore()

    func show(model: MacModel) {
        guard panel == nil, let screen = NSScreen.main else { return }
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: OverlayView(model: model, store: store))
        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()
        panel = p
    }

    func arrive(_ msg: DropMessage, side: PhoneSide) {
        guard let image = NSImage(data: msg.data) else { return }
        // Speed into the Mac = velocity perpendicular to the edge the photo left the phone by.
        let along: Double, lateral: Double
        switch msg.edge {
        case .top: along = -msg.velocityY; lateral = msg.velocityX * (side == .right ? -1 : 1)
        case .left: along = -msg.velocityX; lateral = msg.velocityY
        case .right: along = msg.velocityX; lateral = msg.velocityY
        }
        let a = Arrival(image: image, side: side, position: msg.position,
                        along: max(abs(along), 400), lateral: lateral)
        store.items.append(a)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            self?.store.items.removeAll { $0.id == a.id }
        }
    }
}

struct OverlayView: View {
    @ObservedObject var model: MacModel
    @ObservedObject var store: ArrivalStore

    var body: some View {
        GeometryReader { geo in
            ZStack {
                EdgeGlow(side: model.phoneSide, intensity: glowIntensity)
                ForEach(store.items) { a in
                    FlyingPhoto(arrival: a, size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var glowIntensity: Double {
        if !store.items.isEmpty { return 1 }
        return model.scanner.touching ? 1 : model.scanner.nearness * 0.35
    }
}

/// Soft colored light hugging the edge the phone is on.
struct EdgeGlow: View {
    let side: PhoneSide
    let intensity: Double
    @State private var pulse = false

    var body: some View {
        let colors: [Color] = [Color(red: 0.35, green: 0.75, blue: 1).opacity(0.75),
                               Color(red: 0.65, green: 0.45, blue: 1).opacity(0.35), .clear]
        Rectangle()
            .fill(LinearGradient(colors: colors,
                                 startPoint: side == .left ? .leading : .trailing,
                                 endPoint: side == .left ? .trailing : .leading))
            .frame(width: 140)
            .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom))
            .blur(radius: 18)
            .opacity(intensity * (pulse ? 1 : 0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .left ? .leading : .trailing)
            .animation(.easeInOut(duration: 0.35), value: intensity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// Slides in from the phone edge with a spring tuned by flick speed, settles, then fades.
struct FlyingPhoto: View {
    let arrival: Arrival
    let size: CGSize
    @State private var landed = false
    @State private var gone = false

    private let thumb: CGFloat = 240

    var body: some View {
        let y0 = size.height * (0.15 + 0.7 * arrival.position)
        let fromLeft = arrival.side == .left
        let startX = fromLeft ? -thumb : size.width + thumb
        // Faster flick → lands farther in.
        let travel = min(max(arrival.along * 0.3, 260), size.width * 0.45)
        let endX = fromLeft ? travel : size.width - travel
        let endY = min(max(y0 + arrival.lateral * 0.12, thumb), size.height - thumb)
        let response = min(max(700 / arrival.along, 0.35), 0.9)

        Image(nsImage: arrival.image)
            .resizable()
            .scaledToFill()
            .frame(width: thumb, height: thumb)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .rotationEffect(.degrees(landed ? 0 : (fromLeft ? -8 : 8)))
            .scaleEffect(gone ? 0.6 : 1)
            .opacity(gone ? 0 : 1)
            .position(x: landed ? endX : startX, y: landed ? endY : y0)
            .onAppear {
                withAnimation(.spring(response: response, dampingFraction: 0.68)) { landed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                    withAnimation(.easeIn(duration: 0.6)) { gone = true }
                }
            }
    }
}
