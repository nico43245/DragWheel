import AppKit
import Combine

/// Live state of the radial wheel: which page, which petal is under the cursor, what's being dragged.
@MainActor
final class WheelState: ObservableObject {
    static let shared = WheelState()

    static let size: CGFloat = 440
    static let innerRadius: CGFloat = 72
    static let outerRadius: CGFloat = 168
    static let centerRadius: CGFloat = 62
    static let petalCount = 8
    static let centerIndex = 8

    @Published var pageIndex = 0
    /// 0..<8 for petals, 8 for the center button.
    @Published var hovered: Int?
    @Published var files: [URL] = []
    @Published var thumbnail: NSImage?

    private var lastPageSwitch = Date.distantPast
    private var scrollAccumulator: CGFloat = 0

    var page: WheelPage { Catalog.pages[pageIndex] }

    var hoveredAction: WheelAction? {
        guard let hovered else { return nil }
        return hovered == Self.centerIndex ? page.center : page.petals[hovered]
    }

    func setFiles(_ urls: [URL]) {
        guard urls != files else { return }
        files = urls
        thumbnail = urls.first.map(Self.thumbnail(for:))
    }

    // MARK: Hit testing

    /// `point` is in wheel coordinates with the origin top-left (SwiftUI space).
    func updateHover(at point: CGPoint) {
        let dx = point.x - Self.size / 2
        let dy = point.y - Self.size / 2
        let distance = hypot(dx, dy)
        let newValue: Int?
        if distance <= Self.centerRadius {
            newValue = Self.centerIndex
        } else if distance >= Self.innerRadius - 6 && distance <= Self.outerRadius + 28 {
            newValue = Self.petalIndex(dx: dx, dy: dy)
        } else {
            newValue = nil
        }
        if newValue != hovered { hovered = newValue }
    }

    /// Petal 0 sits at 12 o'clock, then clockwise.
    static func petalIndex(dx: CGFloat, dy: CGFloat) -> Int {
        var degrees = atan2(dy, dx) * 180 / .pi + 90 + 22.5
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return Int(degrees / 45) % petalCount
    }

    static func centerAngle(of index: Int) -> Double { -90 + Double(index) * 45 }

    // MARK: Paging

    func nextPage() { switchPage(by: 1) }
    func previousPage() { switchPage(by: -1) }

    func switchPage(by step: Int) {
        let count = Catalog.pages.count
        pageIndex = ((pageIndex + step) % count + count) % count
        lastPageSwitch = Date()
    }

    /// Mouse wheel or two-finger swipe; debounced so one flick moves one page.
    func handleScroll(delta: CGFloat) {
        guard Date().timeIntervalSince(lastPageSwitch) > 0.35 else { scrollAccumulator = 0; return }
        scrollAccumulator += delta
        if abs(scrollAccumulator) > 6 {
            switchPage(by: scrollAccumulator > 0 ? -1 : 1)
            scrollAccumulator = 0
        }
    }

    // MARK: Thumbnails

    private static func thumbnail(for url: URL) -> NSImage {
        if FileKind(url) == .image || FileKind(url) == .pdf,
           let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0 {
            return image
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
