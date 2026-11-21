/// The 24 symbols of Arc's folder icon picker, in its order (three rows of eight).
public enum FolderSymbol: String, Codable, CaseIterable {
    case star, bookmark, heart, bolt, triangle, asterisk, bell, lightbulb
    case chat, people, tools, egg, circle, moon, planet, leaf
    case cloud, paw, cutlery, airplane, music, video, code, skull

    /// Its name in the picker (its tooltip and accessibility label).
    public var title: String {
        switch self {
        case .star: return "Star"
        case .bookmark: return "Bookmark"
        case .heart: return "Heart"
        case .bolt: return "Lightning"
        case .triangle: return "Triangle"
        case .asterisk: return "Asterisk"
        case .bell: return "Bell"
        case .lightbulb: return "Lightbulb"
        case .chat: return "Chat"
        case .people: return "People"
        case .tools: return "Tools"
        case .egg: return "Egg"
        case .circle: return "Circle"
        case .moon: return "Moon"
        case .planet: return "Planet"
        case .leaf: return "Leaf"
        case .cloud: return "Cloud"
        case .paw: return "Paw"
        case .cutlery: return "Cutlery"
        case .airplane: return "Airplane"
        case .music: return "Music"
        case .video: return "Video"
        case .code: return "Code"
        case .skull: return "Skull"
        }
    }
}
