import SwiftUI

/// An annular sector with rounded-looking gaps between neighbours.
struct PetalShape: Shape {
    var centerAngle: Double
    var span: Double = 45
    var gap: Double = 2.6
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle(degrees: centerAngle - span / 2 + gap)
        let end = Angle(degrees: centerAngle + span / 2 - gap)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Real behind-window blur for the glass disc.
struct GlassBlur: NSViewRepresentable {
    var dark: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = .hudWindow
        v.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
    }
}

struct WheelView: View {
    @ObservedObject var state: WheelState
    @ObservedObject var settings = Settings.shared
    /// Off only for offline snapshots, which can't draw the live blur.
    var showsBlur = true

    private let size = WheelState.size
    private let inner = WheelState.innerRadius
    private let outer = WheelState.outerRadius

    var body: some View {
        let theme = settings.theme
        ZStack {
            // Glass disc
            if showsBlur {
                GlassBlur(dark: theme.isDark)
                    .frame(width: outer * 2 + 24, height: outer * 2 + 24)
                    .clipShape(Circle())
            }
            Circle()
                .fill(theme.glass)
                .frame(width: outer * 2 + 24, height: outer * 2 + 24)
                .overlay(Circle().stroke(theme.accent.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

            ForEach(0..<WheelState.petalCount, id: \.self) { index in
                petal(index, theme: theme)
            }

            centerButton(theme: theme)

            // Page title and dots
            VStack {
                Text(state.page.title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(theme.isDark ? Color.white : theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(theme.petal))
                    .overlay(Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Catalog.pages) { page in
                        Capsule()
                            .fill(page.id == state.pageIndex ? theme.accent : Color.gray.opacity(0.45))
                            .frame(width: page.id == state.pageIndex ? 18 : 6, height: 6)
                    }
                }
                .padding(6)
                .background(Capsule().fill(theme.petal))
            }
            .padding(.vertical, 6)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: state.hovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.pageIndex)
    }

    @ViewBuilder
    private func petal(_ index: Int, theme: Theme) -> some View {
        let action = state.page.petals[index]
        let isHovered = state.hovered == index
        let angle = WheelState.centerAngle(of: index)
        let mid = (inner + outer) / 2
        let radians = angle * .pi / 180

        ZStack {
            PetalShape(centerAngle: angle, inner: inner, outer: outer)
                .fill(isHovered ? theme.accent : theme.petal)
                .shadow(color: isHovered ? theme.accent.opacity(0.6) : .clear, radius: 12)
            PetalShape(centerAngle: angle, inner: inner, outer: outer)
                .stroke(theme.accent.opacity(isHovered ? 0 : 0.18), lineWidth: 1)

            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 74)
            .foregroundStyle(isHovered ? theme.textOnAccent : theme.text)
            .offset(x: cos(radians) * mid, y: sin(radians) * mid)
        }
        .frame(width: size, height: size)
        .scaleEffect(isHovered ? 1.07 : 1)
    }

    @ViewBuilder
    private func centerButton(theme: Theme) -> some View {
        let isHovered = state.hovered == WheelState.centerIndex
        let r = WheelState.centerRadius
        ZStack {
            Circle()
                .fill(isHovered ? theme.accent : theme.petal)
                .overlay(Circle().stroke(theme.accent.opacity(0.5), lineWidth: 1.5))
                .shadow(color: isHovered ? theme.accent.opacity(0.6) : .black.opacity(0.12), radius: isHovered ? 14 : 6)

            if let hint = state.hoveredAction, !isHovered {
                // Hovering a petal: the hub explains it.
                VStack(spacing: 3) {
                    Text(hint.title).font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.accent)
                    Text(hint.hint).font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.text)
                }
                .frame(width: r * 1.7)
            } else if isHovered {
                VStack(spacing: 3) {
                    Image(systemName: state.page.center.symbol).font(.system(size: 18, weight: .semibold))
                    Text(state.page.center.title).font(.system(size: 12, weight: .heavy, design: .rounded))
                    Text(state.page.center.hint).font(.system(size: 9, weight: .medium)).multilineTextAlignment(.center)
                }
                .foregroundStyle(theme.textOnAccent)
                .frame(width: r * 1.7)
            } else {
                VStack(spacing: 4) {
                    if let thumb = state.thumbnail {
                        Image(nsImage: thumb)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    Text(state.files.count > 1 ? "\(state.files.count) files · \(state.page.center.title)" : state.page.center.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: r * 1.7)
            }
        }
        .frame(width: r * 2, height: r * 2)
        .scaleEffect(isHovered ? 1.06 : 1)
    }
}
