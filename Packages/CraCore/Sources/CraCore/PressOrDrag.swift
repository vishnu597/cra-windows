import Foundation

/// A press on a Library row or Media tile that a click opens and a drag hands out as the file
/// (the Mac's MediaTile and LibraryItemCell: mouseDragged past a few points starts the drag,
/// mouseUp before that is the click). Windows follows the press by sampling the mouse, so the
/// decision is made per sample here.
public enum PressOrDrag: Equatable, Sendable {
    /// Still held, still within the slop.
    case waiting
    /// Let go before it moved far: the row's click.
    case click
    /// Moved past the slop while held: the file goes out as a drag.
    case drag

    /// `dx`, `dy`: how far the pointer is from where it was pressed; `slopX`, `slopY`: how far it
    /// may go before it is a drag (Windows' SM_CXDRAG and SM_CYDRAG, halved either side).
    public static func classify(dx: Double, dy: Double, buttonDown: Bool, slopX: Double, slopY: Double) -> PressOrDrag {
        guard buttonDown else { return .click }
        return abs(dx) > slopX || abs(dy) > slopY ? .drag : .waiting
    }
}
