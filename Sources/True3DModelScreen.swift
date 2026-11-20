import Foundation
import SceneKit
import SwiftUI
import OCCTSwift

/// iOS 正式真 3D 建模页：所有几何都由 OCCT B-Rep 生成。
/// 当前覆盖基础块、圆角/倒角、通孔、凸台、方腔和 STEP/STL 导出。
struct True3DModelScreen: View {
    @State private var params = True3DParams()
    @State private var scene = SCNScene()
    @State private var result: True3DResult?
    @State private var error: String?
    @State private var message = "点“生成实体”创建 OCCT 实体"
    @State private var showWire = true
    @State private var stepURL: URL?
    @State private var stlURL: URL?
    @State private var isBuilding = false
    @State private var didInitialBuild = false

    private var isDirty: Bool {
        guard let result else { return false }
        return result.params != params
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                True3DSceneView(scene: scene, showWire: showWire)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                statusArea
                buildButton

                if let result {
                    featureTree(result.features)
                    NavigationLink {
                        True3DCAMScreen(result: result, model: result.params)
                    } label: {
                        HStack {
                            Label("进入 3D 刀路", systemImage: "point.3.connected.trianglepath.dotted")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 13)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 1.0, green: 0.42, blue: 0.10))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    exportArea
                }

                parametersArea

                Text("真 3D 页面使用 Open CASCADE Technology 8.0.1 的 B-Rep 实体和布尔运算；旧 2.5D 建模/工序入口已移除，仅保留 2D 单工序快捷编程。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("内核授权：OCCT 8.0.1 / OCCTSwift 3.0.0 · LGPL-2.1")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .navigationTitle("真 3D 建模")
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
            if !didInitialBuild {
                didInitialBuild = true
                rebuild()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("真 3D · B-Rep")
                    .font(.system(size: 22, weight: .bold))
                Text("OCCT")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.10, green: 0.55, blue: 0.50).opacity(0.12))
                    .foregroundStyle(Color(red: 0.08, green: 0.42, blue: 0.38))
                    .clipShape(Capsule())
            }
            Text("实体布尔 · 圆角/倒角 · 通孔 · 凸台 · 方腔 · STEP/STL")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let result {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    metric("体积", String(format: "%.0f mm³", result.stats.volume))
                    Divider().frame(height: 30)
                    metric("面", "\(result.stats.faces)")
                    Divider().frame(height: 30)
                    metric("边", "\(result.stats.edges)")
                    Divider().frame(height: 30)
                    metric("三角面", "\(result.stats.triangles)")
                }
                HStack(spacing: 8) {
                    Label(result.stats.valid ? "实体有效" : "实体无效",
                          systemImage: result.stats.valid ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(result.stats.valid ? Color.green : Color.red)
                    Spacer()
                    Toggle("线框", isOn: $showWire)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .fixedSize()
                }
                if isDirty {
                    Label("参数已修改，当前显示仍是上次生成的实体；请点“生成实体”更新", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else {
            HStack(spacing: 8) {
                if isBuilding { ProgressView() }
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var buildButton: some View {
        HStack(spacing: 10) {
            Button {
                rebuild()
            } label: {
                Label(isBuilding ? "生成中…" : "生成实体", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
            .disabled(isBuilding)

            Button {
                params = True3DParams()
                rebuild()
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isBuilding)
        }
        .font(.system(size: 13, weight: .medium))
    }

    private func featureTree(_ features: [True3DFeature]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("特征树")
            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    HStack(spacing: 10) {
                        Image(systemName: feature.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(feature.ok ? Color.green : Color.red)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(feature.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(index + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    if index < features.count - 1 {
                        Divider().padding(.leading, 24)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var exportArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("导出")
            HStack(spacing: 10) {
                if let stepURL {
                    ShareLink(item: stepURL) {
                        Label("分享 STEP", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        exportSTEP()
                    } label: {
                        Label("生成 STEP", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let stlURL {
                    ShareLink(item: stlURL) {
                        Label("分享 STL", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        exportSTL()
                    } label: {
                        Label("生成 STL", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private var parametersArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("参数")

            group("基础块") {
                numRow("X 长", $params.width)
                numRow("Y 宽", $params.depth)
                numRow("Z 高", $params.height)
            }

            group("边缘处理") {
                Picker("方式", selection: $params.edgeMode) {
                    ForEach(True3DEdgeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if params.edgeMode != .none {
                    numRow(params.edgeMode == .fillet ? "圆角 R" : "倒角 C", $params.edgeSize)
                }
            }

            group("通孔") {
                Toggle("启用通孔", isOn: $params.holeEnabled)
                if params.holeEnabled {
                    numRow("孔径 Ø", $params.holeDiameter)
                    numRow("中心 X", $params.holeX)
                    numRow("中心 Y", $params.holeY)
                }
            }

            group("凸台") {
                Toggle("启用凸台", isOn: $params.bossEnabled)
                if params.bossEnabled {
                    numRow("直径 Ø", $params.bossDiameter)
                    numRow("高度 H", $params.bossHeight)
                    numRow("中心 X", $params.bossX)
                    numRow("中心 Y", $params.bossY)
                }
            }

            group("方腔") {
                Toggle("启用方腔", isOn: $params.pocketEnabled)
                if params.pocketEnabled {
                    numRow("X 宽", $params.pocketWidth)
                    numRow("Y 宽", $params.pocketDepthXY)
                    numRow("深度 Z", $params.pocketZ)
                    numRow("中心 X", $params.pocketX)
                    numRow("中心 Y", $params.pocketY)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
            Divider()
        }
    }

    private func numRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
                .textFieldStyle(.roundedBorder)
            Text("mm")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(red: 0.14, green: 0.17, blue: 0.22))
    }

    private func rebuild() {
        error = nil
        result = nil
        scene = SCNScene()
        stepURL = nil
        stlURL = nil
        isBuilding = true
        message = "正在构建 OCCT 实体…"

        do {
            let newResult = try True3DKernel.build(params)
            result = newResult
            message = "构建完成"
            scene = makeScene(result: newResult)
        } catch {
            self.error = error.localizedDescription
            message = "构建失败"
        }
        isBuilding = false
    }

    private func makeScene(result: True3DResult) -> SCNScene {
        let newScene = SCNScene()
        newScene.background.contents = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)

        let modelRoot = SCNNode()
        modelRoot.eulerAngles.x = -Float.pi / 2
        newScene.rootNode.addChildNode(modelRoot)

        let geometry = result.mesh.sceneKitGeometry()
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
        wireMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.15, blue: 0.20, alpha: 0.72)
        wireMaterial.fillMode = .lines
        wireMaterial.isDoubleSided = true
        let wireGeometry = result.mesh.sceneKitGeometry()
        wireGeometry.materials = [wireMaterial]
        let wireNode = SCNNode(geometry: wireGeometry)
        wireNode.name = "wireOverlay"
        wireNode.scale = SCNVector3(1.002, 1.002, 1.002)
        wireNode.isHidden = !showWire
        modelRoot.addChildNode(wireNode)

        let model = result.params
        let maxSize = max(model.width, model.depth, model.height, 20)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 10000
        camera.position = SCNVector3(Float(maxSize * 1.55), Float(maxSize * 1.35), Float(maxSize * 1.55))
        let target = SCNNode()
        target.position = SCNVector3(0, Float(model.height / 2), 0)
        newScene.rootNode.addChildNode(target)
        camera.constraints = [SCNLookAtConstraint(target: target)]
        newScene.rootNode.addChildNode(camera)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 1100
        light.light?.temperature = 6500
        light.position = SCNVector3(Float(maxSize * 1.2), Float(maxSize * 1.8), Float(maxSize * 1.2))
        newScene.rootNode.addChildNode(light)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 350
        fill.light?.color = UIColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1)
        newScene.rootNode.addChildNode(fill)

        return newScene
    }

    private func exportSTEP() {
        guard let result else { return }
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent("MacroGen-True3D.step")
            try result.shape.writeSTEP(to: url, name: "MacroGenTrue3D")
            stepURL = url
        } catch {
            self.error = "STEP 导出失败：\(error.localizedDescription)"
        }
    }

    private func exportSTL() {
        guard let result else { return }
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent("MacroGen-True3D.stl")
            try result.shape.writeSTL(to: url, deflection: 0.1)
            stlURL = url
        } catch {
            self.error = "STL 导出失败：\(error.localizedDescription)"
        }
    }
}

private struct True3DSceneView: UIViewRepresentable {
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
