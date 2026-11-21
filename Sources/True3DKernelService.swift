import Foundation
import OCCTSwift

/// 一次圆角预览的结果。`shape` 只在内核队列/MainActor 之间短暂传递，
/// 确认后才写入 `True3DHistoryOperation`。
struct True3DPreview: @unchecked Sendable {
    let shape: Shape
    let mesh: Mesh
    let stats: True3DStats
}

/// 3D 内核串行服务。
///
/// OCCT 的 Shape/BRep 操作不是并发安全的；这个 actor 保证同一时刻只有一个
/// 建模/导入任务。UI 通过 `Task` 调用，计算不在主线程执行。
actor True3DKernelService {
    /// 同步重建模型。调用方取消 Task 后，这里只能在进入/退出时检查取消，
    /// 单次 OCCT 调用内部不可中断。
    func build(_ document: True3DModelDocument) async throws -> True3DResult {
        try Task.checkCancellation()
        let result = try document.build()
        try Task.checkCancellation()
        return result
    }

    /// 导入 STEP。R1 只取第一个根；装配树放 R2。
    func importSTEP(
        from url: URL,
        name: String,
        progress: ImportProgress? = nil
    ) async throws -> True3DImportedPart {
        try Task.checkCancellation()
        do {
            let shape = try Shape.loadSTEP(from: url, progress: progress)
            try Task.checkCancellation()

            guard shape.isValid else {
                throw True3DModelError.importFailed("STEP 实体无效，可能包含开放壳体或坏面")
            }
            guard shape.faceCount > 0 else {
                throw True3DModelError.importFailed("STEP 里没有可用的面")
            }
            guard let mesh = shape.mesh(linearDeflection: 0.18, angularDeflection: 0.35) else {
                throw True3DModelError.importFailed("STEP 三角化失败")
            }
            try Task.checkCancellation()

            return True3DImportedPart(
                name: name,
                localURL: url,
                shape: shape,
                mesh: mesh
            )
        } catch let error as True3DModelError {
            throw error
        } catch {
            throw True3DModelError.importFailed("STEP 导入失败：\(error.localizedDescription)")
        }
    }

    /// 圆角预览。R1 只支持单边；多边/变半径放 R2。
    func previewFillet(
        on shape: Shape,
        edge: Edge,
        radius: Double
    ) async throws -> True3DPreview {
        try Task.checkCancellation()
        guard radius > 0 else {
            throw True3DModelError.invalidParameter("圆角半径必须大于 0")
        }
        guard let builder = FilletBuilder(shape: shape) else {
            throw True3DModelError.previewFailed("无法创建圆角构建器")
        }
        guard builder.addEdge(edge, radius: radius), builder.contour(for: edge) > 0 else {
            throw True3DModelError.previewFailed("这条边不能加 R\(fmt(radius)) 圆角")
        }
        guard builder.faultyContourCount == 0, builder.faultyVertexCount == 0,
              let result = builder.build(), result.isValid else {
            throw True3DModelError.previewFailed(
                "R\(fmt(radius)) 圆角失败：半径可能超过实体允许范围"
            )
        }
        try Task.checkCancellation()
        guard let mesh = result.mesh(linearDeflection: 0.18, angularDeflection: 0.35) else {
            throw True3DModelError.previewFailed("圆角预览三角化失败")
        }
        try Task.checkCancellation()
        return True3DPreview(
            shape: result,
            mesh: mesh,
            stats: True3DStats.measure(shape: result, mesh: mesh)
        )
    }

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".00", with: "")
    }
}
