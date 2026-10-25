import CoreGraphics

/// Где поставить панель: под якорем (выделением или полем), а если снизу не помещается — над ним.
/// Панель всегда целиком остаётся внутри видимой области экрана.
enum PanelPlacement {
    static let gap: CGFloat = 8
    static let margin: CGFloat = 8

    static func frame(size: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let x = clamp(anchor.minX, visible.minX + margin, visible.maxX - size.width - margin)

        let below = anchor.minY - gap - size.height
        let above = anchor.maxY + gap
        let y: CGFloat
        if below >= visible.minY + margin {
            y = below
        } else if above + size.height <= visible.maxY - margin {
            y = above
        } else {
            y = clamp(below, visible.minY + margin, visible.maxY - size.height - margin)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        max(lower, min(value, max(lower, upper)))
    }
}
