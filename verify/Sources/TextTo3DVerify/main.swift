import Foundation
import OCCTSwift

// True3DModel.swift 的轻量验证副本只需要这个节点类型；完整定义在 App 的
// True3DModelDocument.swift 里，这里不引入文档/工程依赖。
struct True3DTreeNode: Identifiable, Equatable, Sendable {
    var id = UUID()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}

struct Case {
    let name: String
    let prompt: String
    let expectedFeatures: Int
    let expectedShape: True3DBaseShape
}

let cases: [Case] = [
    Case(
        name: "stepped-slot",
        prompt: "120×80×30，18宽三级阶梯槽，深6/12/18",
        expectedFeatures: 3,
        expectedShape: .box
    ),
    Case(
        name: "stepped-slot-fillet",
        prompt: "120×80×30，18宽三级阶梯槽，深6/12/18，R2.5",
        expectedFeatures: 3,
        expectedShape: .box
    ),
    Case(
        name: "flange",
        prompt: "80×80×10，中心Ø30，6个Ø6孔，分布圆Ø60，R1.5",
        expectedFeatures: 7,
        expectedShape: .box
    ),
    Case(
        name: "rect-pocket",
        prompt: "100×60×20，中间40×30方腔深10，R3",
        expectedFeatures: 1,
        expectedShape: .box
    ),
    Case(
        name: "round-block-hole",
        prompt: "Ø80×20 圆块，中心Ø30通孔",
        expectedFeatures: 1,
        expectedShape: .circle
    ),
    Case(
        name: "boss",
        prompt: "120×80×30，Ø30凸台高8",
        expectedFeatures: 1,
        expectedShape: .box
    )
]

for item in cases {
    let result = LocalTextTo3DParser.parse(item.prompt)
    let parsed: TextTo3DParseResult
    switch result {
    case .success(let value):
        parsed = value
    case .failure(let error):
        fail("\(item.name): parse failed: \(error.localizedDescription)")
    }

    guard parsed.params.baseShape == item.expectedShape else {
        fail("\(item.name): base shape \(parsed.params.baseShape) != \(item.expectedShape)")
    }
    guard parsed.params.features.count == item.expectedFeatures else {
        fail("\(item.name): features \(parsed.params.features.count) != \(item.expectedFeatures)")
    }

    do {
        let built = try True3DKernel.build(parsed.params)
        guard built.stats.valid else { fail("\(item.name): invalid B-Rep") }
        guard built.stats.volume > 0, built.stats.faces > 0, built.stats.triangles > 0 else {
            fail("\(item.name): empty B-Rep")
        }
        guard built.params.width > 0, built.params.depth > 0, built.params.height > 0 else {
            fail("\(item.name): invalid stock size")
        }

        print(
            "PASS \(item.name): features=\(parsed.params.features.count) " +
            "volume=\(String(format: "%.1f", built.stats.volume)) " +
            "faces=\(built.stats.faces) triangles=\(built.stats.triangles)"
        )
        print("  summary: \(parsed.summary.joined(separator: " | "))")
        if !parsed.warnings.isEmpty {
            print("  warnings: \(parsed.warnings.joined(separator: " | "))")
        }
    } catch {
        fail("\(item.name): build failed: \(error.localizedDescription)")
    }
}

print("PASS all text-to-3D parser cases")
