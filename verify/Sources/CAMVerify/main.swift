import Foundation
import Darwin
import OCCTSwift

// CAMVerify 只编译 CAM 引擎，不带 PostProcessor.swift；这里补上同一枚举签名。
enum ProgramFormat: String, Codable { case macro, gcode }

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

let only3D = CommandLine.arguments.contains("--3d-only")
if !only3D {
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

// 多工序：按序程序、宏变量、冷却/余量/方向、整圆弧。
func runMultiOpChecks() {
do {
    let base = True3DParams()
    let built = try True3DKernel.build(base)
    var cam = True3DCAMParams()
    cam.operations = [
        True3DOperation(kind: .rough),
        True3DOperation(kind: .hole)
    ]
    let multi = try True3DCAM.generate(result: built, model: base, cam: cam)
    guard !multi.runs.isEmpty, multi.runCodes.count == multi.runs.count else {
        fail("multi-op: runCodes count \(multi.runCodes.count) != runs \(multi.runs.count)")
    }
    guard multi.runCodes.allSatisfy({ $0.contains("M30") }) else {
        fail("multi-op: a per-operation program has no M30")
    }
    guard multi.gcode.contains("M08") else {
        fail("multi-op: missing flood coolant M08")
    }
    print("PASS multi-op: runs=\(multi.runs.count) perOpPrograms=\(multi.runCodes.count) chars=\(multi.gcode.count)")

    var macroCam = cam
    macroCam.programFormat = .macro
    let macro = try True3DCAM.generate(result: built, model: base, cam: macroCam)
    guard macro.gcode.contains("#100"), macro.gcode.contains("#101"), macro.gcode.contains("#102") else {
        fail("multi-op-macro: missing per-operation #100/#101/#102")
    }
    guard macro.runCodes.contains(where: { $0.contains("#100") }) else {
        fail("multi-op-macro: per-operation program is not macro-style")
    }
    print("PASS multi-op-macro: chars=\(macro.gcode.count)")

    var rough = True3DOperation(kind: .rough)
    rough.coolant = .mist
    rough.stockLeft = 2
    rough.climb = false
    var finish = True3DOperation(kind: .finish)
    finish.coolant = .off
    var paramCam = True3DCAMParams()
    paramCam.operations = [rough, finish]
    let paramsResult = try True3DCAM.generate(result: built, model: base, cam: paramCam)
    guard paramsResult.gcode.contains("M07") else {
        fail("op-params: mist M07 was not emitted")
    }
    guard !paramsResult.gcode.contains("M08") else {
        fail("op-params: flood M08 leaked from an off operation")
    }
    print("PASS op-params: coolant/stock/climb pipeline ran")

    var roundModel = True3DParams()
    var roundPocket = True3DFeatureSpec(kind: .circularPocket, x: 38, y: -28)
    roundPocket.name = "圆腔验证"; roundPocket.dia = 20; roundPocket.depth = 5
    roundModel.features.append(roundPocket)
    let roundBuilt = try True3DKernel.build(roundModel)
    var roundOp = True3DOperation(kind: .pocketRound)
    roundOp.targetFeatureIndex = roundModel.features.count - 1
    roundOp.toolDia = 6
    roundOp.stepDown = 2
    roundOp.stepOver = 3
    var roundCam = True3DCAMParams()
    roundCam.operations = [roundOp]
    let roundResult = try True3DCAM.generate(result: roundBuilt, model: roundModel, cam: roundCam)
    guard roundResult.gcode.contains("G2 ") || roundResult.gcode.contains("G3 ") else {
        fail("arc-output: no G2/G3 in circular pocket program")
    }
    print("PASS arc-output: G2/G3 emitted for a closed circular pocket")

    var slotArcOp = True3DOperation(kind: .slotArc)
    slotArcOp.toolDia = 6
    slotArcOp.slotArcR = 30
    slotArcOp.slotArcStart = -60
    slotArcOp.slotArcEnd = 60
    slotArcOp.slotWidth = 8
    slotArcOp.slotDepth = 3
    slotArcOp.stepDown = 1.5
    slotArcOp.stepOver = 3
    var slotArcCam = True3DCAMParams()
    slotArcCam.operations = [slotArcOp]
    let slotArcResult = try True3DCAM.generate(result: built, model: base, cam: slotArcCam)
    guard slotArcResult.gcode.contains("G2 ") || slotArcResult.gcode.contains("G3 ") else {
        fail("partial-arc: slotArc output still has no G2/G3")
    }
    print("PASS partial-arc: slotArc uses G2/G3 for a 120° circular slot")

    let flatR = true3DEffectiveToolRadius(diameter: 10, type: .flat, cornerRadius: 2, depth: 2)
    let ballR = true3DEffectiveToolRadius(diameter: 10, type: .ball, cornerRadius: 2, depth: 2)
    let bullR = true3DEffectiveToolRadius(diameter: 10, type: .bull, cornerRadius: 2, depth: 1)
    guard abs(flatR - 5) < 0.001, abs(ballR - 4) < 0.001,
          abs(bullR - (3 + sqrt(3))) < 0.01 else {
        fail("tool-shape: effective radius calculation wrong flat=\(flatR) ball=\(ballR) bull=\(bullR)")
    }
    print("PASS tool-shape: flat=\(flatR) ball=\(ballR) bull@1mm=\(bullR)")

    var loopOp = True3DOperation(kind: .rough)
    loopOp.toolDia = 6
    loopOp.stepDown = 2
    loopOp.stepOver = 4
    loopOp.toolType = .flat
    loopOp.cornerRadius = 1
    var loopCam = True3DCAMParams()
    loopCam.operations = [loopOp]
    loopCam.programFormat = .macro
    let loopResult = try True3DCAM.generate(result: built, model: base, cam: loopCam)
    guard loopResult.gcode.contains("WHILE["),
          loopResult.gcode.contains("END1"),
          loopResult.gcode.contains("IF[#100LE0]GOTO"),
          loopResult.gcode.contains("N9000") else {
        fail("macro-depth: missing WHILE/IF/N label")
    }
    print("PASS macro-depth: WHILE/IF/GOTO emitted, chars=\(loopResult.gcode.count)")
} catch {
    fail("multi-op: \(error.localizedDescription)")
}
}
runMultiOpChecks()

}

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
    var sketchFeature = True3DFeatureSpec(kind: .profileBoss)
    sketchFeature.name = "草图凸台验证"
    sketchFeature.profile = [
        True3DPoint(x: -20, y: -10),
        True3DPoint(x: 20, y: -10),
        True3DPoint(x: 20, y: 10),
        True3DPoint(x: -20, y: 10)
    ]
    sketchFeature.depth = 6
    sketchFeature.bossHeight = 6
    params.features = [sketchFeature]
    let sketchDocument = True3DModelDocument(params: params)
    let sketchBuilt = try sketchDocument.build()
    guard sketchBuilt.stats.valid, sketchBuilt.stats.faces >= 6,
          sketchBuilt.nodes.count >= 2 else {
        fail("sketch-profile: extrusion did not produce a valid solid")
    }
    print("PASS sketch-profile: faces=\(sketchBuilt.stats.faces) nodes=\(sketchBuilt.nodes.count)")

    var offsetFeature = sketchFeature
    offsetFeature.profileStartOffset = 4
    offsetFeature.profileEndOffset = 14
    params.features = [offsetFeature]
    let offsetBuilt = try True3DModelDocument(params: params).build()
    guard offsetBuilt.stats.valid,
          let offsetBounds = offsetBuilt.shape.bounds,
          abs(offsetBounds.max.z - (params.height + 14)) < 0.5,
          offsetBuilt.stats.volume > sketchBuilt.stats.volume else {
        fail("sketch-profile-offset: start/end offsets did not apply")
    }
    print("PASS sketch-profile-offset: topZ=\(String(format: "%.1f", offsetBounds.max.z))")
} catch {
    fail("sketch-profile: \(error.localizedDescription)")
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

    var chamferDocument = document
    chamferDocument.append(True3DHistoryOperation(kind: .chamfer(edge: ref, distance: 2)))
    let chamfered = try chamferDocument.build()
    guard chamfered.stats.valid, chamfered.nodes.count == 2,
          chamfered.nodes[1].kind == .chamfer else {
        fail("history: chamfer did not produce a valid node")
    }
    print("PASS history-chamfer: nodes=\(chamfered.nodes.count) faces=\(chamfered.stats.faces)")

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

    var variableDocument = document
    variableDocument.append(True3DHistoryOperation(kind: .variableFillet(
        edge: ref, radius1: 1.2, radius2: 2.4
    )))
    let variable = try variableDocument.build()
    guard variable.stats.valid, variable.nodes.count == 2,
          variable.nodes[1].kind == .fillet,
          variable.nodes[1].name == "变半径圆角" else {
        fail("history-variable-fillet: variable radius did not build")
    }
    print("PASS history-variable-fillet: faces=\(variable.stats.faces)")

    let allEdgeRefs = built.shape.edges().map { True3DEdgeRef.make(edge: $0, in: built.shape) }
    var multiDocument = document
    multiDocument.append(True3DHistoryOperation(kind: .multiFillet(edges: allEdgeRefs, radius: 1)))
    let multiFilleted = try multiDocument.build()
    guard multiFilleted.stats.valid, multiFilleted.nodes.count == 2,
          multiFilleted.nodes[1].name.hasPrefix("多边圆角") else {
        fail("history-multi-fillet: multi edge fillet did not build")
    }
    print("PASS history-multi-fillet: edges=\(allEdgeRefs.count) faces=\(multiFilleted.stats.faces)")

    var moveDocument = document
    moveDocument.append(True3DHistoryOperation(kind: .translate(dx: 20, dy: 0, dz: 0, copy: false)))
    let moved = try moveDocument.build()
    guard moved.stats.valid, moved.nodes.count == 2,
          moved.nodes[1].name == "移动体",
          abs(moved.stats.volume - built.stats.volume) < 50,
          let baseBounds = built.shape.bounds, let movedBounds = moved.shape.bounds,
          abs((movedBounds.min.x - baseBounds.min.x) - 20) < 0.5 else {
        fail("history-translate: body did not move by 20 mm")
    }
    print("PASS history-translate: ΔX=\(String(format: "%.1f", movedBounds.min.x - baseBounds.min.x))")

    var copyDocument = document
    copyDocument.append(True3DHistoryOperation(kind: .translate(dx: 120, dy: 0, dz: 0, copy: true)))
    let copied = try copyDocument.build()
    guard copied.stats.valid, copied.nodes.count == 2,
          copied.nodes[1].name == "移动拷贝",
          copied.stats.volume > built.stats.volume * 1.8 else {
        fail("history-translate-copy: copy did not keep original body")
    }
    print("PASS history-translate-copy: volume=\(String(format: "%.1f", copied.stats.volume))")

    let topFaceProfile = [
        True3DPoint3D(x: -60, y: -40, z: 10),
        True3DPoint3D(x: 60, y: -40, z: 10),
        True3DPoint3D(x: 60, y: 40, z: 10),
        True3DPoint3D(x: -60, y: 40, z: 10)
    ]
    var faceMoveDocument = document
    faceMoveDocument.append(True3DHistoryOperation(kind: .moveFace(
        points: topFaceProfile,
        normal: True3DPoint3D(x: 0, y: 0, z: 1),
        distance: 5
    )))
    let faceMoved = try faceMoveDocument.build()
    guard faceMoved.stats.valid, faceMoved.nodes.count == 2,
          abs(faceMoved.stats.volume - 144000) < 50 else {
        fail("history-move-face: outward move did not extend adjacent faces")
    }
    print("PASS history-move-face: volume=\(String(format: "%.1f", faceMoved.stats.volume))")

    var faceCutDocument = document
    faceCutDocument.append(True3DHistoryOperation(kind: .moveFace(
        points: topFaceProfile,
        normal: True3DPoint3D(x: 0, y: 0, z: 1),
        distance: -3
    )))
    let faceCut = try faceCutDocument.build()
    guard faceCut.stats.valid, abs(faceCut.stats.volume - 67200) < 50 else {
        fail("history-move-face-inward: inward move did not cut adjacent faces")
    }
    print("PASS history-move-face-inward: volume=\(String(format: "%.1f", faceCut.stats.volume))")

    var rotateDocument = document
    rotateDocument.append(True3DHistoryOperation(kind: .rotate(axis: "Z", angle: 90, copy: false)))
    let rotated = try rotateDocument.build()
    guard rotated.stats.valid, rotated.nodes.count == 2,
          rotated.nodes[1].name == "旋转体",
          abs(rotated.stats.volume - 96000) < 50,
          let rotatedBounds = rotated.shape.bounds,
          abs((rotatedBounds.max.x - rotatedBounds.min.x) - 80) < 0.5,
          abs((rotatedBounds.max.y - rotatedBounds.min.y) - 120) < 0.5 else {
        fail("history-rotate: body did not rotate around its center")
    }
    print("PASS history-rotate: size=\(String(format: "%.1f", rotatedBounds.max.x - rotatedBounds.min.x))×\(String(format: "%.1f", rotatedBounds.max.y - rotatedBounds.min.y))")
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

do {
    var params = True3DParams()
    params.edgeMode = .none
    params.features = [True3DFeatureSpec(kind: .revolveBoss)]
    let built = try True3DKernel.build(params)
    guard built.stats.valid, built.stats.faces > 0 else {
        fail("revolve-default: invalid B-Rep")
    }
    print("PASS revolve-default: faces=\(built.stats.faces)")
} catch {
    fail("revolve-default: \(error.localizedDescription)")
}

do {
    var params = True3DParams()
    params.edgeMode = .none
    params.height = 5
    params.baseShape = .profile
    params.profile = (0..<48).map { i in
        let a = Double(i) / 48.0 * 2 * Double.pi
        return True3DPoint(x: 32 * cos(a), y: 32 * sin(a))
    }
    params.features = [True3DFeatureSpec(kind: .revolveBoss)]
    let built = try True3DKernel.build(params)
    guard built.stats.valid, built.stats.faces > 0 else {
        fail("revolve-profile-base: invalid B-Rep")
    }
    print("PASS revolve-profile-base: faces=\(built.stats.faces)")
} catch {
    fail("revolve-profile-base: \(error.localizedDescription)")
}


do {
    var baseParams = True3DParams()
    baseParams.edgeMode = .none
    baseParams.features = []
    let base = try True3DKernel.build(baseParams)
    guard base.stats.valid else { fail("face-extrude: base invalid") }

    for (label, wantedZ) in [("top", 1.0), ("side", 0.0)] {
        guard let face = base.shape.faces().first(where: { f in
            guard f.isPlanar, let n = f.normal else { return false }
            return wantedZ > 0.5 ? n.z > 0.9 : abs(n.y) > 0.9
        }), let wire = face.outerWire, let curve = WireCurve(wire) else {
            fail("face-extrude-\(label): no planar face/wire")
        }
        var pts = curve.points(count: 48).map { True3DPoint3D(x: $0.x, y: $0.y, z: $0.z) }
        if let first = pts.first, let last = pts.last,
           hypot(hypot(first.x - last.x, first.y - last.y), first.z - last.z) < 1e-4 {
            pts.removeLast()
        }
        guard let n = face.normal, pts.count >= 3 else { fail("face-extrude-\(label): no outline") }
        var f = True3DFeatureSpec(kind: .faceBoss)
        f.name = "面拉伸-\(label)"
        f.bossHeight = 5
        f.faceProfile = pts
        f.faceNormal = True3DPoint3D(x: n.x, y: n.y, z: n.z)
        f.faceIndex = face.index
        var params = baseParams
        params.features = [f]
        let built = try True3DKernel.build(params)
        guard built.stats.valid, built.stats.volume > base.stats.volume + 100 else {
            fail("face-extrude-\(label): volume did not grow (base=\(base.stats.volume) new=\(built.stats.volume))")
        }
        print("PASS face-extrude-\(label): faces=\(built.stats.faces) volume=\(String(format: "%.1f", built.stats.volume))")
    }
} catch {
    fail("face-extrude: \(error.localizedDescription)")
}


// 全特征矩阵：每个参数化特征单独构建一次，检查 B-Rep 是否有效、体积是否为正。
var featureCases: [(String, True3DFeatureSpec)] = []
@MainActor func addFeatureCase(_ name: String, _ kind: True3DFeatureKind, _ mutate: (inout True3DFeatureSpec) -> Void = { _ in }) {
    var f = True3DFeatureSpec(kind: kind)
    mutate(&f)
    featureCases.append((name, f))
}

for kind in [True3DHoleKind.through, .blind, .counterbore, .countersink, .thread] {
    addFeatureCase("hole-\(kind.rawValue)", .hole, { f in
        f.x = 20; f.y = 0; f.dia = 10; f.holeKind = kind; f.holeDepth = 5
    })
}
addFeatureCase("boss", .boss) { f in f.x = 20; f.y = 0; f.dia = 20 }
addFeatureCase("rect-boss", .rectBoss) { f in f.x = 20; f.y = 0; f.width = 20; f.depthY = 14 }
addFeatureCase("cone-boss", .coneBoss) { f in f.x = 20; f.y = 0 }
addFeatureCase("loft-boss", .loftBoss) { f in f.x = 0; f.y = 0 }
addFeatureCase("sweep-helix", .sweepBoss) { f in f.sweepPathKind = .helix }
addFeatureCase("sweep-circle", .sweepBoss) { f in f.sweepPathKind = .circle }
addFeatureCase("sweep-line", .sweepBoss) { f in f.sweepPathKind = .line }
addFeatureCase("draft", .draft)
addFeatureCase("edge-fillet-all", .edgeFillet) { f in f.edgeSelection = .all; f.depth = 1 }
addFeatureCase("edge-fillet-convex", .edgeFillet) { f in f.edgeSelection = .convex; f.depth = 1 }
addFeatureCase("edge-chamfer-symmetric", .edgeChamfer) { f in f.edgeSelection = .convex; f.chamferMode = .symmetric; f.depth = 1 }
addFeatureCase("edge-chamfer-two", .edgeChamfer) { f in f.edgeSelection = .convex; f.chamferMode = .twoDistance; f.depth = 1; f.chamferSecondDistance = 1 }
addFeatureCase("edge-chamfer-angle", .edgeChamfer) { f in f.edgeSelection = .convex; f.chamferMode = .distanceAngle; f.depth = 1; f.chamferAngle = 45 }
addFeatureCase("shell", .shell) { f in f.depth = 2 }
addFeatureCase("revolve-boss-z-xz", .revolveBoss) { f in f.revolveAxis = .z; f.revolvePlane = .xz }
addFeatureCase("revolve-boss-z-yz", .revolveBoss) { f in f.revolveAxis = .z; f.revolvePlane = .yz }
addFeatureCase("revolve-boss-x-xz", .revolveBoss) { f in f.revolveAxis = .x; f.revolvePlane = .xz }
addFeatureCase("revolve-boss-x-xy", .revolveBoss) { f in f.revolveAxis = .x; f.revolvePlane = .xy }
addFeatureCase("revolve-boss-y-xy", .revolveBoss) { f in f.revolveAxis = .y; f.revolvePlane = .xy }
addFeatureCase("revolve-boss-y-yz", .revolveBoss) { f in f.revolveAxis = .y; f.revolvePlane = .yz }
addFeatureCase("revolve-cut-z-xz", .revolveCut) { f in f.revolveAxis = .z; f.revolvePlane = .xz }
addFeatureCase("circular-pocket", .circularPocket) { f in f.x = 20; f.y = 0; f.dia = 20 }
addFeatureCase("rect-pocket", .rectPocket) { f in f.x = -20; f.y = -10; f.width = 18; f.depthY = 12; f.cornerRadius = 2 }
addFeatureCase("slot", .slot) { f in f.x = 0; f.y = -20; f.width = 40; f.depthY = 10 }
addFeatureCase("profile-boss", .profileBoss) { f in
    f.profile = [True3DPoint(x: -20, y: -10), True3DPoint(x: 20, y: -10), True3DPoint(x: 20, y: 10), True3DPoint(x: -20, y: 10)]
}
addFeatureCase("profile-cut", .profileCut) { f in
    f.profile = [True3DPoint(x: -20, y: -10), True3DPoint(x: 20, y: -10), True3DPoint(x: 20, y: 10), True3DPoint(x: -20, y: 10)]
}
addFeatureCase("face-boss-top", .faceBoss) { f in
    f.faceProfile = [True3DPoint3D(x: -50, y: -30, z: 10), True3DPoint3D(x: 50, y: -30, z: 10), True3DPoint3D(x: 50, y: 30, z: 10), True3DPoint3D(x: -50, y: 30, z: 10)]
    f.faceNormal = True3DPoint3D(x: 0, y: 0, z: 1)
}
addFeatureCase("face-boss-side", .faceBoss) { f in
    f.faceProfile = [True3DPoint3D(x: 60, y: -30, z: 0), True3DPoint3D(x: 60, y: 30, z: 0), True3DPoint3D(x: 60, y: 30, z: 10), True3DPoint3D(x: 60, y: -30, z: 10)]
    f.faceNormal = True3DPoint3D(x: 1, y: 0, z: 0)
}
addFeatureCase("face-cut-top", .faceBoss) { f in
    f.name = "面切除"
    f.faceProfile = [True3DPoint3D(x: -25, y: -18, z: 10), True3DPoint3D(x: 25, y: -18, z: 10), True3DPoint3D(x: 25, y: 18, z: 10), True3DPoint3D(x: -25, y: 18, z: 10)]
    f.faceNormal = True3DPoint3D(x: 0, y: 0, z: 1)
    f.bossHeight = 5
    f.faceCut = true
}

var featureFailures = 0
for (name, f) in featureCases {
    var p = True3DParams()
    p.edgeMode = .none
    p.features = [f]
    do {
        let built = try True3DKernel.build(p)
        guard built.stats.valid, built.stats.volume > 0 else {
            print("FAIL X \(name): invalid/empty")
            featureFailures += 1
            continue
        }
        print("PASS X \(name): faces=\(built.stats.faces) volume=\(String(format: "%.1f", built.stats.volume))")
    } catch {
        print("FAIL X \(name): \(error.localizedDescription)")
        featureFailures += 1
    }
}

// 多特征组合：默认孔+凸台+方腔，以及孔/腔/圆角/抽壳串联。
var comboCases: [(String, [True3DFeatureSpec])] = []
comboCases.append(("default-three", True3DParams.defaultFeatures))
var combo: [True3DFeatureSpec] = []
var hole = True3DFeatureSpec(kind: .hole); hole.x = -20; hole.y = 0; hole.dia = 10
var boss = True3DFeatureSpec(kind: .boss); boss.x = 20; boss.y = 0; boss.dia = 16; boss.bossHeight = 6
var pocket = True3DFeatureSpec(kind: .rectPocket); pocket.x = 0; pocket.y = -20; pocket.width = 18; pocket.depthY = 12; pocket.depth = 4
combo = [hole, boss, pocket]
comboCases.append(("hole+boss+pocket", combo))
var combo2: [True3DFeatureSpec] = []
var pocket2 = True3DFeatureSpec(kind: .rectPocket); pocket2.x = 0; pocket2.y = 0; pocket2.width = 30; pocket2.depthY = 20; pocket2.depth = 3
var shell = True3DFeatureSpec(kind: .shell); shell.depth = 1.5
var shellFirst = shell
var pocketAfter = pocket2
combo2 = [shellFirst, pocketAfter]
comboCases.append(("shell+pocket", combo2))
// 抽壳在界面中自动插到孔/腔之前，因此组合用例按“shell+pocket”验证；
// 手工把抽壳放到型腔之后属于 OCCT 不支持的操作顺序，不再作为功能矩阵用例。
for (name, features) in comboCases {
    var p = True3DParams()
    p.edgeMode = .none
    p.features = features
    do {
        let built = try True3DKernel.build(p)
        guard built.stats.valid, built.stats.volume > 0 else {
            print("FAIL C \(name): invalid/empty")
            featureFailures += 1
            continue
        }
        print("PASS C \(name): faces=\(built.stats.faces) volume=\(String(format: "%.1f", built.stats.volume))")
    } catch {
        print("FAIL C \(name): \(error.localizedDescription)")
        featureFailures += 1
    }
}
if featureFailures > 0 {
    fail("feature matrix: \(featureFailures) cases failed")
}

print("ALL CAM CHECKS PASSED")
