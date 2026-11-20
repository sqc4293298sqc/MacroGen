import Foundation
import SceneKit
import SwiftUI
import OCCTSwift

/// OCCT B-Rep 真实内核验证页。
///
/// 这一页不是 2.5D 画布：基础板、圆角、通孔、凸台、方腔全部由 OCCT
/// 生成实体并做布尔运算，再三角化给 SceneKit 显示。
/// 先用它验证 iOS 上的内核、布尔和圆角是否可靠，再决定是否替换
/// `StudioScreen` 的建模层。
struct OCCTKernelSpikeScreen: View {
    @State private var scene = SCNScene()
    @State private var stats: KernelDemoStats?
    @State private var message = "正在构建 OCCT 实体…"
    @State private var error: String?
    @State private var showWire = true
    @State private var rebuiltCount = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                KernelSceneView(scene: scene, showWire: showWire)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                if let stats {
                    statsRow(stats)
                    operationRow
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("这是 OCCT 真 B-Rep 验证页，暂不替换现有建模/刀路页面。确认圆角、布尔和三角化稳定后，再把 PartSpec 的建模层切到内核。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("几何内核：Open CASCADE Technology 8.0.1 · Swift 封装 OCCTSwift 3.0.0 · LGPL-2.1")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .padding(16)
        }
        .navigationTitle("3D 内核验证")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    rebuild()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if stats == nil && error == nil && rebuiltCount == 0 {
                rebuild()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("真 3D · B-Rep 内核")
                .font(.system(size: 22, weight: .bold))
            Text("基础板 + R4 圆角 + Ø24 通孔 + Ø24 凸台 + 24×18 方腔")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func statsRow(_ stats: KernelDemoStats) -> some View {
        HStack(spacing: 0) {
            metric("体积", String(format: "%.0f mm³", stats.volume))
            Divider().frame(height: 30)
            metric("面", "\(stats.faces)")
            Divider().frame(height: 30)
            metric("边", "\(stats.edges)")
            Divider().frame(height: 30)
            metric("三角面", "\(stats.triangles)")
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var operationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(stats?.valid == true ? "实体有效" : "实体检查异常",
                      systemImage: stats?.valid == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(stats?.valid == true ? Color.green : Color.orange)

                Spacer()

                Toggle("线框", isOn: $showWire)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .fixedSize()
            }

            HStack(spacing: 10) {
                Button {
                    rebuild()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))

                Button {
                    showWire.toggle()
                } label: {
                    Label(showWire ? "隐藏线框" : "显示线框", systemImage: "square.dashed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private func rebuild() {
        error = nil
        stats = nil
        message = "正在构建 OCCT 实体…"
        rebuiltCount += 1

        guard let base = Shape.box(
            origin: SIMD3<Double>(-60, -40, 0),
            width: 120,
            height: 80,
            depth: 10
        ) else {
            error = "基础板创建失败"
            return
        }

        guard let rounded = base.filleted(radius: 4) else {
            error = "R4 圆角失败：内核拒绝了该半径"
            return
        }

        guard let hole = Shape.cylinder(
            at: SIMD2<Double>(0, 0),
            bottomZ: -1,
            radius: 12,
            height: 12
        ) else {
            error = "通孔圆柱创建失败"
            return
        }

        guard let withHole = rounded - hole else {
            error = "Ø24 通孔布尔失败"
            return
        }

        guard let boss = Shape.cylinder(
            at: SIMD2<Double>(35, 20),
            bottomZ: 10,
            radius: 12,
            height: 6
        ) else {
            error = "凸台圆柱创建失败"
            return
        }

        guard let withBoss = withHole + boss else {
            error = "凸台布尔失败"
            return
        }

        guard let pocket = Shape.box(
            origin: SIMD3<Double>(-42, -28, 6),
            width: 24,
            height: 18,
            depth: 5
        ) else {
            error = "方腔工具体创建失败"
            return
        }

        guard let finished = withBoss - pocket else {
            error = "方腔布尔失败"
            return
        }

        guard finished.isValid else {
            error = "OCCT 生成了实体，但 BRepCheck 判定无效"
            return
        }

        guard let mesh = finished.mesh(
            linearDeflection: 0.18,
            angularDeflection: 0.35
        ) else {
            error = "实体三角化失败"
            return
        }

        let demo = KernelDemoStats(
            volume: finished.volume ?? 0,
            faces: finished.faceCount,
            edges: finished.edgeCount,
            triangles: mesh.triangleCount,
            valid: finished.isValid
        )
        stats = demo
        message = "构建完成"

        buildScene(shape: finished, mesh: mesh)
    }

    private func buildScene(shape: OCCTSwift.Shape, mesh: OCCTSwift.Mesh) {
        let newScene = SCNScene()
        newScene.background.contents = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)

        let modelRoot = SCNNode()
        // OCCT / 机床坐标是 Z 向上，SceneKit 默认 Y 向上；把模型整体转 90°。
        modelRoot.eulerAngles.x = -Float.pi / 2
        newScene.rootNode.addChildNode(modelRoot)

        let geometry = mesh.sceneKitGeometry()
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.46, green: 0.58, blue: 0.70, alpha: 1)
        material.metalness.contents = 0.18
        material.roughness.contents = 0.48
        geometry.materials = [material]

        let solidNode = SCNNode(geometry: geometry)
        solidNode.name = "solid"
        modelRoot.addChildNode(solidNode)

        let wireMaterial = SCNMaterial()
        wireMaterial.lightingModel = .constant
        wireMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.15, blue: 0.20, alpha: 0.75)
        wireMaterial.fillMode = .lines
        wireMaterial.isDoubleSided = true
        let wireGeometry = mesh.sceneKitGeometry()
        wireGeometry.materials = [wireMaterial]
        let wireNode = SCNNode(geometry: wireGeometry)
        wireNode.name = "wireOverlay"
        wireNode.scale = SCNVector3(1.002, 1.002, 1.002)
        wireNode.isHidden = !showWire
        modelRoot.addChildNode(wireNode)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 10000
        camera.position = SCNVector3(160, 150, 180)
        let target = SCNNode()
        target.position = SCNVector3(0, 6, 0)
        newScene.rootNode.addChildNode(target)
        camera.constraints = [SCNLookAtConstraint(target: target)]
        newScene.rootNode.addChildNode(camera)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 1100
        light.light?.temperature = 6500
        light.position = SCNVector3(120, 220, 160)
        newScene.rootNode.addChildNode(light)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 350
        fill.light?.color = UIColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1)
        newScene.rootNode.addChildNode(fill)

        scene = newScene
    }
}

private struct KernelDemoStats {
    let volume: Double
    let faces: Int
    let edges: Int
    let triangles: Int
    let valid: Bool
}

private struct KernelSceneView: UIViewRepresentable {
    let scene: SCNScene
    let showWire: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        uiView.scene?.rootNode
            .childNode(withName: "wireOverlay", recursively: true)?
            .isHidden = !showWire
    }
}
