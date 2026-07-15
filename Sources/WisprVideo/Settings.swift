import Foundation

/// Corner placement for the Loom webcam bubble.
enum BubbleCorner: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight

    var title: String {
        switch self {
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        }
    }
}

/// Lightweight persisted user settings.
enum Settings {
    private static let bubbleCornerKey = "bubbleCorner"

    static var bubbleCorner: BubbleCorner {
        get {
            let raw = UserDefaults.standard.string(forKey: bubbleCornerKey) ?? ""
            return BubbleCorner(rawValue: raw) ?? .bottomLeft
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: bubbleCornerKey) }
    }
}
