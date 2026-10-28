import CoreGraphics
import Foundation

public enum NoteColor: String, Codable, CaseIterable {
    case yellow, orange, pink, purple, blue, green, gray
}

public struct Note: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var body: String
    public var color: NoteColor
    public var opacity: Double
    public var pinned: Bool
    public var collapsed: Bool
    /// Window frame in screen coordinates (only the header's height while collapsed).
    public var frame: CGRect
    /// Height to restore when a collapsed note is expanded again.
    public var expandedHeight: Double?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        color: NoteColor = .yellow,
        opacity: Double = 1,
        pinned: Bool = false,
        collapsed: Bool = false,
        frame: CGRect,
        expandedHeight: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.color = color
        self.opacity = opacity
        self.pinned = pinned
        self.collapsed = collapsed
        self.frame = frame
        self.expandedHeight = expandedHeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Lenient decoding so notes saved by older versions keep opening when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        color = (try? c.decodeIfPresent(NoteColor.self, forKey: .color)) ?? .yellow
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        frame = try c.decodeIfPresent(CGRect.self, forKey: .frame) ?? CGRect(x: 200, y: 200, width: 260, height: 240)
        expandedHeight = try c.decodeIfPresent(Double.self, forKey: .expandedHeight)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
