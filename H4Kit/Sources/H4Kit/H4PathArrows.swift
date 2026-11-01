import Foundation

// Slice 7d-L — names of the path arrow sprites (rule 6 of the frozen reference `session_ref.py`).
//
// For a path [path0 = start, ..., pathN] (N >= 1) there is one arrow per cell k = 1...N (none on the start cell).
// Directions use the movement numbering (0 NE, 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, clockwise); a turn is
// (out - in) mod 8: 1 right, 7 left, anything else straight; the suffix is the OUTGOING direction. The last cell is `dest`.
// The colour is green when the step that ARRIVES on the cell is on day 0 (`dayOf[k - 1] == 0`), red otherwise.
// Name = adv_object model `internal.<colour>_arrow.<kind>.<dir>` or `internal.<colour>_arrow.dest` [I].
public enum H4PathArrows {
    static let directionNames = ["ne", "e", "se", "s", "sw", "w", "nw", "n"]

    /// Direction index (movement numbering) of the step between two adjacent cells, nil when not adjacent.
    public static func direction(from a: H4MoveCell, to b: H4MoveCell) -> Int? {
        H4MoveWorld.dirs.firstIndex { $0.dr == b.r - a.r && $0.dc == b.c - a.c }
    }

    /// Arrow model names of a path, in path order (k = 1...N). Empty for a path of fewer than two cells; nil if a step
    /// is not between adjacent cells or `dayOf` has fewer entries than steps.
    public static func names(path: [H4MoveCell], dayOf: [Int]) -> [String]? {
        let n = path.count - 1
        guard n >= 1 else { return [] }
        guard dayOf.count >= n else { return nil }
        var out: [String] = []
        for k in 1...n {
            let colour = dayOf[k - 1] == 0 ? "green" : "red"
            if k == n { out.append("internal.\(colour)_arrow.dest"); continue }
            guard let din = direction(from: path[k - 1], to: path[k]), let dout = direction(from: path[k], to: path[k + 1]) else { return nil }
            let turn = (dout - din + 8) % 8
            let kind = turn == 1 ? "right" : turn == 7 ? "left" : "straight"
            out.append("internal.\(colour)_arrow.\(kind).\(directionNames[dout])")
        }
        return out
    }

    /// Every arrow model name that exists (green and red: 8 directions x {straight, right, left}, plus dest).
    public static var allNames: [String] {
        ["green", "red"].flatMap { c in
            ["internal.\(c)_arrow.dest"] + ["straight", "right", "left"].flatMap { k in directionNames.map { "internal.\(c)_arrow.\(k).\($0)" } }
        }
    }
}
