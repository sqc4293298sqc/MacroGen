import Foundation
import Darwin
import OCCTSwift

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}

func verifyCase(_ name: String, model: True3DParams, cam: True3DCAMParams) {
    do {
        let built = try True3DKernel.build(model)
        guard built.stats.valid else { fail("\(name): B-Rep invalid") }
        guard built.stats.volume > 0, built.stats.faces > 0 else {
            fail("\(name): empty B-Rep")
        }

        let path = try True3DCAM.generate(result: built, model: model, cam: cam)
        guard path.stats.pathCount > 0 else { fail("\(name): no paths") }
        guard path.stats.cutLength > 1 else { fail("\(name): cut length too small") }
        guard path.gcode.contains("G1") else { fail("\(name): G-code has no G1") }
        guard !path.gcode.contains("nan"), !path.gcode.contains("inf") else {
            fail("\(name): non-finite coordinate")
        }
        guard path.gcode.contains("M30") else { fail("\(name): missing M30") }

        print(
            "PASS \(name): volume=\(String(format: "%.1f", built.stats.volume)) " +
            "faces=\(built.stats.faces) paths=\(path.stats.pathCount) " +
            "layers=\(path.stats.layerCount) cut=\(String(format: "%.1f", path.stats.cutLength))mm " +
            "gcode=\(path.gcode.count) chars"
        )
        let longest = path.segments.sorted { $0.len > $1.len }.prefix(5)
        print("  longest:", longest.map { "z=\(String(format: "%.1f", $0.z)) pts=\($0.pts.count) len=\(String(format: "%.1f", $0.len))" }.joined(separator: " | "))
        let maxPoints = path.segments.map(\.pts.count).max() ?? 0
        print("  maxPointsPerPath=\(maxPoints)")
        if let seg = longest.first {
            let xs = seg.pts.map(\.x), ys = seg.pts.map(\.y)
            let gaps = (1..<seg.pts.count).map { hypot(seg.pts[$0].x - seg.pts[$0-1].x, seg.pts[$0].y - seg.pts[$0-1].y) }.sorted(by: >)
            print(String(format: "  bbox x[%.1f..%.1f] y[%.1f..%.1f] maxGap=%.1f gaps=%@",
                         xs.min()!, xs.max()!, ys.min()!, ys.max()!, gaps.first ?? 0,
                         gaps.prefix(5).map { String(format: "%.1f", $0) }.joined(separator: ",")))
            print("  first=", seg.pts.prefix(3).map { String(format: "(%.1f,%.1f)", $0.x, $0.y) }.joined(separator: " "),
                  "last=", seg.pts.suffix(3).map { String(format: "(%.1f,%.1f)", $0.x, $0.y) }.joined(separator: " "))
        }
    } catch {
        fail("\(name): \(error.localizedDescription)")
    }
}

var base = True3DParams()
var cam = True3DCAMParams()
// Debug: isolate the base outer contour and avoid inner clearing / face rows.
base.bossEnabled = false
base.holeEnabled = false
base.pocketEnabled = false
cam.doFaceBaseTop = false
cam.doFaceBossTop = false
cam.doFacePocketBottom = false
cam.doClearInner = false
cam.doRoughing = false
verifyCase("simple-base-outline", model: base, cam: cam)

base = True3DParams()
cam = True3DCAMParams()
verifyCase("default-boss-hole-pocket", model: base, cam: cam)

base.bossEnabled = false
base.holeEnabled = false
base.pocketEnabled = true
base.edgeMode = .chamfer
verifyCase("chamfer-pocket-only", model: base, cam: cam)

base.bossEnabled = true
base.holeEnabled = true
base.pocketEnabled = false
base.edgeMode = .none
cam.stepDown = 2.5
cam.stepOver = 5
verifyCase("no-fillet-hole-boss", model: base, cam: cam)

cam.toolDia = 10
base = True3DParams()
verifyCase("large-tool-default", model: base, cam: cam)

print("ALL CAM CHECKS PASSED")
