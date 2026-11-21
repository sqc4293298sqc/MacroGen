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
            guard xs.min()! >= -70, xs.max()! <= 70, ys.min()! >= -70, ys.max()! <= 70 else {
                fail("\(name): toolpath outside stock bounds (xs=\(xs.min()!)...\(xs.max()!) ys=\(ys.min()!)...\(ys.max()!))")
            }
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
base.features = []
cam.doFaceBaseTop = false
cam.doFaceBossTop = false
cam.doFacePocketBottom = false
cam.doClearInner = false
cam.doRoughing = false
verifyCase("simple-base-outline", model: base, cam: cam)

base = True3DParams()
cam = True3DCAMParams()
verifyCase("default-boss-hole-pocket", model: base, cam: cam)

base.features = True3DParams.defaultFeatures.filter { $0.kind == .rectPocket }
base.edgeMode = .chamfer
verifyCase("chamfer-pocket-only", model: base, cam: cam)

base.features = True3DParams.defaultFeatures.filter { $0.kind == .hole || $0.kind == .boss }
base.edgeMode = .none
cam.stepDown = 2.5
cam.stepOver = 5
verifyCase("no-fillet-hole-boss", model: base, cam: cam)

base = True3DParams()
var extraHole = True3DFeatureSpec(kind: .hole, x: -30, y: 0)
extraHole.name = "第二孔"; extraHole.dia = 10; extraHole.holeKind = .through
var extraPocket = True3DFeatureSpec(kind: .rectPocket, x: 30, y: -20)
extraPocket.name = "第二方腔"; extraPocket.width = 16; extraPocket.depthY = 12; extraPocket.depth = 4; extraPocket.cornerRadius = 2
base.features.append(extraHole)
base.features.append(extraPocket)
verifyCase("multi-feature", model: base, cam: cam)

cam.toolDia = 10
base = True3DParams()
verifyCase("large-tool-default", model: base, cam: cam)

do {
    let document = True3DModelDocument(params: True3DParams())
    let built = try document.build()
    guard built.documentID == document.id else {
        fail("document: result lost document id")
    }
    guard built.nodes.count >= 2 else {
        fail("document: expected root + feature nodes, got \(built.nodes.count)")
    }
    guard built.stats.valid, built.stats.faces > 0 else {
        fail("document: invalid B-Rep")
    }
    print("PASS document: nodes=\(built.nodes.count) faces=\(built.stats.faces)")
} catch {
    fail("document: \(error.localizedDescription)")
}

do {
    var params = True3DParams()
    params.edgeMode = .none
    params.features = []
    let document = True3DModelDocument(params: params)
    let built = try document.build()
    guard let edge = built.shape.edge(at: 0) else {
        fail("history: box has no edge 0")
    }
    let ref = True3DEdgeRef.make(edge: edge, in: built.shape)
    var edited = document
    edited.append(True3DHistoryOperation(kind: .fillet(edge: ref, radius: 2)))
    let filleted = try edited.build()
    guard filleted.stats.valid, filleted.nodes.count == 2 else {
        fail("history: fillet did not produce a valid node")
    }
    print("PASS history: nodes=\(filleted.nodes.count) faces=\(filleted.stats.faces)")

    let suppressedOperation = True3DHistoryOperation(
        kind: .fillet(edge: ref, radius: 3),
        suppressed: true
    )
    var suppressedDocument = document
    suppressedDocument.append(suppressedOperation)
    let suppressed = try suppressedDocument.build()
    guard suppressed.stats.valid, suppressed.nodes.count == 2,
          suppressed.nodes[1].operationID == suppressedOperation.id,
          suppressed.nodes[1].status == .suppressed else {
        fail("history: suppressed operation did not stay suppressed")
    }
    print("PASS history: suppressed operation node retained")
} catch {
    fail("history: \(error.localizedDescription)")
}

do {
    let params = True3DParams()
    let edge = True3DEdgeRef(
        edgeIndex: 0,
        midpoint: True3DPoint3(x: 1, y: 2, z: 3),
        length: 10,
        adjacentFaceIndices: [0, 1]
    )
    let operation = True3DHistoryOperation(kind: .fillet(edge: edge, radius: 2))
    let stored = True3DStoredProject(
        id: UUID(),
        name: "roundtrip",
        sourceKind: .parametric,
        params: params,
        operations: [operation]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(stored)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(True3DStoredProject.self, from: data)
    guard decoded.id == stored.id,
          decoded.sourceKind == .parametric,
          decoded.params?.width == params.width,
          decoded.operations.count == 1 else {
        fail("project: stored project round-trip mismatch")
    }
    if case .fillet(let decodedEdge, let decodedRadius) = decoded.operations[0].kind {
        guard decodedRadius == 2, decodedEdge.edgeIndex == 0, decodedEdge.length == 10 else {
            fail("project: fillet operation round-trip mismatch")
        }
    } else {
        fail("project: operation kind changed")
    }
    print("PASS project: operations=\(decoded.operations.count)")
} catch {
    fail("project: \(error.localizedDescription)")
}

do {
    let stored = True3DStoredProject(
        id: UUID(),
        name: "imported-roundtrip",
        sourceKind: .importedStep,
        importedName: "bracket",
        importedFileName: "bracket.step",
        importedUnitInMeters: 0.001,
        importedAt: Date(timeIntervalSince1970: 1_700_000_000),
        operations: []
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(stored)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(True3DStoredProject.self, from: data)
    guard decoded.sourceKind == .importedStep,
          decoded.importedFileName == "bracket.step",
          abs((decoded.importedUnitInMeters ?? 0) - 0.001) < 1e-9 else {
        fail("project: imported project round-trip mismatch")
    }
    print("PASS project: imported source persisted")
} catch {
    fail("project-imported: \(error.localizedDescription)")
}

print("ALL CAM CHECKS PASSED")
