import Foundation
import SceneKit
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import OCCTSwift

/// iOS 正式真 3D 建模页：OCCT B-Rep 实体、可编辑特征树、DXF/照片导入、STEP/STL 导出。
struct True3DModelScreen: View {
    @State private var params = True3DParams()
    @State private var scene = SCNScene()
    @State private var result: True3DResult?
    @State private var error: String?
    @State private var notice: String?
    @State private var message = "点“生成实体”创建 OCCT 实体"
    @State private var showWire = true
    @State private var stepURL: URL?
    @State private var stlURL: URL?
    @State private var isBuilding = false
    @State private var didInitialBuild = false
    @State private var selectedFeatureID: UUID?
    @State private var showImporter = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importBusy = false

    private var isDirty: Bool {
        guard let result else { return false }
        return result.params != params
    }

    private var dxfType: UTType {
        UTType(filenameExtension: "dxf") ?? .plainText
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
                if let notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                featureListArea

                Text("真 3D 页面使用 Open CASCADE Technology 8.0.1 的 B-Rep 实体和布尔运算；旧 2.5D 建模/工序入口已移除。")
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
        .navigationTitle(params.projectName.isEmpty ? "真 3D 建模" : params.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImporter = true } label: {
                        Label("导入 DXF 轮廓", systemImage: "doc.badge.plus")
                    }
                    Button { showPhotoPicker = true } label: {
                        Label("相册识别轮廓", systemImage: "photo")
                    }
                    Button { showCamera = true } label: {
                        Label("拍照识别轮廓", systemImage: "camera")
                    }
                    Divider()
                    Button { saveProject() } label: {
                        Label("保存工程", systemImage: "square.and.arrow.down")
                    }
                    Button { loadProject() } label: {
                        Label("载入工程", systemImage: "folder")
                    }
                    Divider()
                    Button { rebuild() } label: {
                        Label("重新生成", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isBuilding || importBusy)
            }
        }
        .task {
            if !didInitialBuild {
                didInitialBuild = true
                rebuild()
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [dxfType, .plainText],
            allowsMultipleSelection: true
        ) { outcome in
            switch outcome {
            case .success(let urls):
                if let url = urls.first { importDXF(url) }
            case .failure(let err):
                self.error = "打开 DXF 失败：\(err.localizedDescription)"
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _ in
            loadPhotoItem()
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                scanImage(image)
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
            Text("实体布尔 · 多孔/凸台/型腔/腰槽 · 特征树 · DXF/照片 · STEP/STL")
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
                HStack {
                    Text("外形 \(String(format: "%.1f", result.stats.sizeX)) × \(String(format: "%.1f", result.stats.sizeY)) × \(String(format: "%.1f", result.stats.sizeZ)) mm")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(result.stats.valid ? "实体有效" : "实体无效",
                          systemImage: result.stats.valid ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(result.stats.valid ? Color.green : Color.red)
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
                if isBuilding || importBusy { ProgressView() }
                Text(importBusy ? "正在识别轮廓…" : message)
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
            .disabled(isBuilding || importBusy)

            Button {
                params = True3DParams()
                selectedFeatureID = nil
                rebuild()
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isBuilding || importBusy)
        }
        .font(.system(size: 13, weight: .medium))
    }

    private func featureTree(_ features: [True3DFeature]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("生成结果")
            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    HStack(spacing: 10) {
                        Image(systemName: feature.ok ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(feature.ok ? Color.green : Color.secondary)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.name).font(.system(size: 13, weight: .semibold))
                            Text(feature.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("\(index + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    if index < features.count - 1 { Divider().padding(.leading, 24) }
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
                        Label("分享 STEP", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { exportSTEP() } label: {
                        Label("生成 STEP", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if let stlURL {
                    ShareLink(item: stlURL) {
                        Label("分享 STL", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { exportSTL() } label: {
                        Label("生成 STL", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private var parametersArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("基础形状")
            group("工程") {
                TextField("工程名", text: $params.projectName)
                    .textFieldStyle(.roundedBorder)
            }
            group("基础块") {
                Picker("形状", selection: $params.baseShape) {
                    ForEach(True3DBaseShape.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                if params.baseShape == .profile {
                    Text("轮廓点：\(params.profile.count) 个（由 DXF/照片导入）")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("清空轮廓，改回矩形") {
                        params.baseShape = .box
                        params.profile.removeAll()
                    }
                    .font(.system(size: 11))
                }
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
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var featureListArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("特征")
                Spacer()
                Menu {
                    Button("孔") { addFeature(.hole) }
                    Button("凸台") { addFeature(.boss) }
                    Button("圆腔") { addFeature(.circularPocket) }
                    Button("方腔") { addFeature(.rectPocket) }
                    Button("腰形槽") { addFeature(.slot) }
                } label: {
                    Label("添加", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(isBuilding || importBusy)
            }
            if params.features.isEmpty {
                Text("还没有特征；点“添加”创建孔、凸台或型腔。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(params.features) { feature in
                    featureRow(feature)
                    if selectedFeatureID == feature.id {
                        featureEditor(featureBinding(for: feature))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                    }
                    Divider().padding(.leading, 12)
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func featureRow(_ feature: True3DFeatureSpec) -> some View {
        HStack(spacing: 9) {
            Button {
                selectedFeatureID = selectedFeatureID == feature.id ? nil : feature.id
            } label: {
                Image(systemName: icon(for: feature.kind))
                    .font(.system(size: 16))
                    .foregroundStyle(feature.suppressed ? Color.secondary : Color(red: 0.10, green: 0.55, blue: 0.50))
                    .frame(width: 26)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(feature.suppressed ? .secondary : .primary)
                Text(feature.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Toggle("", isOn: featureBinding(for: feature).suppressed).labelsHidden().scaleEffect(0.8)
            Button(role: .destructive) {
                params.features.removeAll { $0.id == feature.id }
                if selectedFeatureID == feature.id { selectedFeatureID = nil }
            } label: {
                Image(systemName: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func featureBinding(for feature: True3DFeatureSpec) -> Binding<True3DFeatureSpec> {
        Binding(
            get: {
                params.features.first(where: { $0.id == feature.id }) ?? feature
            },
            set: { newValue in
                if let index = params.features.firstIndex(where: { $0.id == feature.id }) {
                    params.features[index] = newValue
                }
            }
        )
    }

    @ViewBuilder
    private func featureEditor(_ f: Binding<True3DFeatureSpec>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("特征名称", text: f.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            switch f.wrappedValue.kind {
            case .hole:
                numRow("直径 Ø", f.dia)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
                Picker("孔类型", selection: f.holeKind) {
                    ForEach(True3DHoleKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .font(.system(size: 12))
                if f.wrappedValue.holeKind == .blind || f.wrappedValue.holeKind == .thread {
                    numRow("深度", f.holeDepth)
                }
                if f.wrappedValue.holeKind == .counterbore {
                    optRow("沉头 Ø", f.cbDia, fallback: f.wrappedValue.dia + 2)
                    optRow("沉头深", f.cbDepth, fallback: 2)
                }
                if f.wrappedValue.holeKind == .countersink {
                    optRow("沉孔 Ø", f.csDia, fallback: f.wrappedValue.dia + 2)
                    optRow("沉孔角", f.csAngle, fallback: 90)
                }
            case .boss:
                numRow("直径 Ø", f.dia)
                numRow("高度 H", f.bossHeight)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            case .circularPocket:
                numRow("直径 Ø", f.dia)
                numRow("深度", f.depth)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            case .rectPocket:
                numRow("X 长", f.width)
                numRow("Y 宽", f.depthY)
                numRow("深度", f.depth)
                numRow("圆角 R", f.cornerRadius)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            case .slot:
                numRow("总长", f.width)
                numRow("槽宽", f.depthY)
                numRow("深度", f.depth)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            }
            topZEditor(f)
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func topZEditor(_ f: Binding<True3DFeatureSpec>) -> some View {
        Toggle("指定顶面 Z", isOn: Binding(
            get: { f.wrappedValue.topZ != nil },
            set: { on in f.wrappedValue.topZ = on ? params.height : nil }
        ))
        .font(.system(size: 12))
        if f.wrappedValue.topZ != nil {
            optRow("顶面 Z", f.topZ, fallback: params.height)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            content()
            Divider()
        }
    }

    private func numRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12))
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .textFieldStyle(.roundedBorder)
            Text("mm").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
        }
    }

    private func optRow(_ title: String, _ value: Binding<Double?>, fallback: Double) -> some View {
        numRow(title, Binding(
            get: { value.wrappedValue ?? fallback },
            set: { value.wrappedValue = $0 }
        ))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(red: 0.14, green: 0.17, blue: 0.22))
    }

    private func icon(for kind: True3DFeatureKind) -> String {
        switch kind {
        case .hole: return "circle.circle"
        case .boss: return "cylinder"
        case .circularPocket: return "circle.dashed"
        case .rectPocket: return "square.dashed"
        case .slot: return "capsule"
        }
    }

    private func addFeature(_ kind: True3DFeatureKind) {
        var f = True3DFeatureSpec(kind: kind)
        switch kind {
        case .hole:
            f.name = "新孔"; f.x = -params.width * 0.25; f.dia = 10
        case .boss:
            f.name = "新凸台"; f.x = params.width * 0.25; f.y = params.depth * 0.15; f.dia = 20; f.bossHeight = 6
        case .circularPocket:
            f.name = "新圆腔"; f.x = -params.width * 0.25; f.dia = 20; f.depth = 5
        case .rectPocket:
            f.name = "新方腔"; f.x = params.width * 0.25; f.y = -params.depth * 0.2; f.width = 24; f.depthY = 18
        case .slot:
            f.name = "新腰形槽"; f.x = 0; f.y = -params.depth * 0.25; f.width = 40; f.depthY = 12
        }
        params.features.append(f)
        selectedFeatureID = f.id
    }

    private func rebuild() {
        error = nil
        notice = nil
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
        let bossMax = model.bossFeatures.map(\.bossHeight).max() ?? 0
        let maxSize = max(model.width, model.depth, model.height + bossMax, 20)
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

    private func saveProject() {
        do {
            try True3DProjectStore.save(params)
            notice = "工程已保存到 Documents/MacroGen-3D-project.json"
        } catch {
            self.error = "保存工程失败：\(error.localizedDescription)"
        }
    }

    private func loadProject() {
        do {
            params = try True3DProjectStore.load()
            selectedFeatureID = nil
            rebuild()
            notice = "已载入上次保存的 3D 工程"
        } catch {
            self.error = "载入工程失败：\(error.localizedDescription)"
        }
    }

    private func importDXF(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = try DXFImporter.parse(text, name: url.deletingPathExtension().lastPathComponent)
            apply(spec: imported.spec, name: url.deletingPathExtension().lastPathComponent, note: imported.note)
        } catch {
            self.error = "DXF 导入失败：\(error.localizedDescription)"
        }
    }

    private func loadPhotoItem() {
        guard let item = photoItem else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await MainActor.run { scanImage(image) }
            } catch {
                await MainActor.run { self.error = "读取图片失败：\(error.localizedDescription)" }
            }
        }
    }

    private func scanImage(_ image: UIImage) {
        importBusy = true
        error = nil
        notice = nil
        Task {
            do {
                let scanned = try await DrawingScanner.scan(image)
                await MainActor.run {
                    apply(spec: scanned.spec, name: scanned.spec.projectName, note: scanned.scaleNote)
                    importBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = "照片识别失败：\(error.localizedDescription)"
                    importBusy = false
                }
            }
        }
    }

    private func apply(spec: PartSpec, name: String, note: String) {
        var p = True3DParams()
        p.projectName = name.isEmpty ? "导入工程" : name
        p.height = max(spec.height, 1)
        p.edgeMode = .none
        p.edgeSize = 0
        switch spec.template {
        case .free:
            let nodes = spec.nodes
            guard nodes.count >= 3 else {
                self.error = "导入的轮廓少于 3 个点，无法生成实体"
                return
            }
            p.baseShape = .profile
            p.profile = nodes.map { True3DPoint(x: $0.x, y: $0.y) }
            p.width = max((nodes.map(\.x).max() ?? 0) - (nodes.map(\.x).min() ?? 0), 1)
            p.depth = max((nodes.map(\.y).max() ?? 0) - (nodes.map(\.y).min() ?? 0), 1)
        case .circle:
            p.baseShape = .circle
            p.width = max(spec.circleD, 1)
            p.depth = max(spec.circleD, 1)
        case .slot:
            p.baseShape = .profile
            p.profile = stadiumPoints(length: max(spec.slotL, spec.slotW), width: max(spec.slotW, 1))
            p.width = max(spec.slotL, 1)
            p.depth = max(spec.slotW, 1)
        case .rect:
            p.baseShape = .box
            p.width = max(spec.rectL, 1)
            p.depth = max(spec.rectW, 1)
        }
        p.features = spec.feats.map(convert)
        params = p
        selectedFeatureID = nil
        rebuild()
        notice = note
    }

    private func convert(_ feature: PartFeat) -> True3DFeatureSpec {
        switch feature.kind {
        case .hole:
            var f = True3DFeatureSpec(kind: .hole, x: feature.x, y: feature.y)
            f.name = feature.name.isEmpty ? "导入孔" : feature.name
            f.dia = feature.dia
            f.holeKind = True3DHoleKind(rawValue: feature.resolvedHoleKind.rawValue) ?? .through
            f.holeDepth = feature.resolvedHoleDepth
            f.cbDia = feature.cbDia
            f.cbDepth = feature.cbDepth
            f.csDia = feature.csDia
            f.csAngle = feature.csAngle
            f.topZ = feature.placeZ
            return f
        case .pocket:
            var f = True3DFeatureSpec(kind: .circularPocket, x: feature.x, y: feature.y)
            f.name = feature.name.isEmpty ? "导入圆腔" : feature.name
            f.dia = feature.dia
            f.depth = feature.depth
            f.topZ = feature.placeZ
            return f
        case .rectPocket:
            var f = True3DFeatureSpec(kind: .rectPocket, x: feature.x, y: feature.y)
            f.name = feature.name.isEmpty ? "导入方腔" : feature.name
            f.width = feature.w
            f.depthY = feature.h
            f.depth = feature.depth
            f.topZ = feature.placeZ
            return f
        }
    }

    private func stadiumPoints(length: Double, width: Double) -> [True3DPoint] {
        let r = width / 2
        let half = max(length / 2 - r, 0)
        var pts: [True3DPoint] = []
        for i in 0...12 {
            let a = Double(i) / 12 * .pi - .pi / 2
            pts.append(True3DPoint(x: half + r * cos(a), y: r * sin(a)))
        }
        for i in 0...12 {
            let a = Double(i) / 12 * .pi + .pi / 2
            pts.append(True3DPoint(x: -half + r * cos(a), y: r * sin(a)))
        }
        return pts
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
