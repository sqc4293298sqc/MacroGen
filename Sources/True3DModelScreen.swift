import Foundation
import SceneKit
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import OCCTSwift

enum True3DWorkbenchStage: String, CaseIterable, Identifiable {
    case sketch = "草图"
    case model = "建模"
    case assembly = "装配"
    case operation = "工序"
    case machine = "加工"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sketch: return "pencil.tip.crop.circle"
        case .model: return "cube.transparent.2"
        case .assembly: return "square.stack.3d.up.fill"
        case .operation: return "square.stack.3d.up"
        case .machine: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// 真 3D 工作台：草图 → 建模 → 工序 → 加工 一条线完成。
struct True3DAssemblyComponent: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var rotationZ: Double = 0
}

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
    @State private var stage: True3DWorkbenchStage = .model
    @State private var cam = True3DCAMParams()
    @State private var operations: [True3DOperation] = True3DModelScreen.defaultOperations()
    @State private var camResult: True3DCAMResult?
    @State private var simulationMode = 0
    @State private var showModelDrawer = false
    @State private var patternRows = 3
    @State private var patternCols = 3
    @State private var patternPitchX: Double = 20
    @State private var patternPitchY: Double = 16
    @State private var patternHoleDia: Double = 6
    @State private var circularCount = 6
    @State private var circularRadius: Double = 32
    @State private var isGeneratingCAM = false
    @State private var gcodeURL: URL?
    @State private var showImporter = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importBusy = false
    @State private var assemblyComponents: [True3DAssemblyComponent] = []
    @State private var assemblyScene = SCNScene()
    @State private var assemblyX: Double = 0
    @State private var assemblyY: Double = 0
    @State private var assemblyZ: Double = 0
    @State private var assemblyRotation: Double = 0

    private var isDirty: Bool {
        guard let result else { return false }
        return result.params != params
    }

    private var dxfType: UTType {
        UTType(filenameExtension: "dxf") ?? .plainText
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                stageBar
                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showModelDrawer, stage == .model {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showModelDrawer = false } }
                modelDrawer
                    .frame(width: min(330, UIScreen.main.bounds.width * 0.82))
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle(params.projectName.isEmpty ? "真 3D 工作台" : params.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if stage == .model {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showModelDrawer.toggle() }
                    } label: {
                        Label("特征面板", systemImage: "sidebar.right")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if stage == .model {
                        Button { stage = .sketch } label: {
                            Label("回到草图", systemImage: "pencil.tip.crop.circle")
                        }
                        Button { newBlankProject() } label: {
                            Label("新建空白工程", systemImage: "doc.badge.plus")
                        }
                        Divider()
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
                    } else if stage == .operation || stage == .machine {
                        Button { generateCAM() } label: {
                            Label("重新生成刀路", systemImage: "arrow.clockwise")
                        }
                        .disabled(result == nil || isGeneratingCAM)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isBuilding || importBusy || isGeneratingCAM)
            }
        }
        .onChange(of: stage) { newStage in
            if newStage == .assembly {
                if assemblyComponents.isEmpty, result != nil {
                    assemblyComponents = [True3DAssemblyComponent(name: "零件 1")]
                }
                rebuildAssemblyScene()
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

    private var stageBar: some View {
        HStack(spacing: 0) {
            ForEach(True3DWorkbenchStage.allCases) { item in
                Button {
                    stage = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(stage == item ? Color(red: 1.0, green: 0.42, blue: 0.10) : Color.primary.opacity(0.62))
                    .background(
                        stage == item
                            ? Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.10)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .sketch:
            sketchStage
        case .model:
            modelingStage
        case .assembly:
            assemblyStage
        case .operation:
            operationStage
        case .machine:
            machineStage
        }
    }

    private var sketchStage: some View {
        True3DSketchScreen(
            width: params.width,
            depth: params.depth,
            embedded: true,
            onBaseChange: { w, d in
                params.width = max(w, 1)
                params.depth = max(d, 1)
            }
        ) { output in
            applySketch(output)
            stage = .model
        }
    }

    private var modelingStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                modelToolBar

                True3DSceneView(scene: scene, showWire: showWire)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                statusArea
                if !params.features.isEmpty {
                    inlineFeatureStrip
                }
                if let notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buildButton

                if let result {
                    featureTree(result.features)
                    Button {
                        stage = .operation
                    } label: {
                        HStack {
                            Label("进入工序", systemImage: "square.stack.3d.up")
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

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showModelDrawer = true }
                } label: {
                    Label("打开特征 / 参数抽屉", systemImage: "sidebar.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("草图 → 建模 → 装配 → 工序 → 加工 · OCCT 8.0.1 B-Rep 内核")
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
    }

    private var modelDrawer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("建模面板")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showModelDrawer = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                parametersArea
                featureListArea
                patternArea
            }
            .padding(14)
            .padding(.bottom, 30)
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 0.5)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var assemblyStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("装配")
                        .font(.system(size: 22, weight: .bold))
                    Text("多实例")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.10, green: 0.55, blue: 0.50).opacity(0.12))
                        .foregroundStyle(Color(red: 0.08, green: 0.42, blue: 0.38))
                        .clipShape(Capsule())
                    Spacer()
                }

                if result == nil {
                    Text("先在“建模”页生成实体，再回到装配添加实例。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("回到建模页") { stage = .model }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                } else {
                    True3DSceneView(scene: assemblyScene, showWire: showWire)
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    Text("实例偏移（基础块坐标，mm）")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 6) {
                        assemblyField("X", value: $assemblyX)
                        assemblyField("Y", value: $assemblyY)
                        assemblyField("Z", value: $assemblyZ)
                        assemblyField("Rz°", value: $assemblyRotation)
                    }
                    Button {
                        let name = "零件 \(assemblyComponents.count + 1)"
                        assemblyComponents.append(True3DAssemblyComponent(
                            name: name, x: assemblyX, y: assemblyY,
                            z: assemblyZ, rotationZ: assemblyRotation
                        ))
                        rebuildAssemblyScene()
                    } label: {
                        Label("添加当前实体副本", systemImage: "plus.square.on.square")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1.0, green: 0.42, blue: 0.10))

                    ForEach($assemblyComponents) { $component in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "cube")
                                TextField("名称", text: $component.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button {
                                    assemblyComponents.removeAll { $0.id == component.id }
                                    rebuildAssemblyScene()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red.opacity(0.7))
                            }
                            HStack(spacing: 6) {
                                assemblyField("X", value: $component.x)
                                assemblyField("Y", value: $component.y)
                                assemblyField("Z", value: $component.z)
                                assemblyField("Rz°", value: $component.rotationZ)
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Button("刷新装配视图") { rebuildAssemblyScene() }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .onChange(of: assemblyComponents) { _ in rebuildAssemblyScene() }
    }

    private func assemblyField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11))
                .textFieldStyle(.roundedBorder)
                .frame(width: 62)
        }
    }

    private func rebuildAssemblyScene() {
        guard let result else { assemblyScene = SCNScene(); return }
        let newScene = SCNScene()
        newScene.background.contents = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        let root = SCNNode()
        root.eulerAngles.x = -Float.pi / 2
        newScene.rootNode.addChildNode(root)
        for comp in assemblyComponents {
            let holder = SCNNode()
            holder.position = SCNVector3(Float(comp.x), Float(comp.y), Float(comp.z))
            holder.eulerAngles.z = Float(comp.rotationZ * .pi / 180)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(red: 0.46, green: 0.58, blue: 0.70, alpha: 1)
            material.metalness.contents = 0.18
            material.roughness.contents = 0.48
            let geometry = result.mesh.sceneKitGeometry()
            geometry.materials = [material]
            holder.addChildNode(SCNNode(geometry: geometry))
            let wireMaterial = SCNMaterial()
            wireMaterial.lightingModel = .constant
            wireMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.15, blue: 0.20, alpha: 0.72)
            wireMaterial.fillMode = .lines
            wireMaterial.isDoubleSided = true
            let wire = result.mesh.sceneKitGeometry()
            wire.materials = [wireMaterial]
            let wireNode = SCNNode(geometry: wire)
            wireNode.name = "wireOverlay"
            wireNode.scale = SCNVector3(1.002, 1.002, 1.002)
            wireNode.isHidden = !showWire
            holder.addChildNode(wireNode)
            root.addChildNode(holder)
        }
        let model = result.params
        let maxSize = max(model.width, model.depth, model.height + (model.bossFeatures.map(\.bossHeight).max() ?? 0), 20)
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
        assemblyScene = newScene
    }

    private var operationStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("工序")
                        .font(.system(size: 22, weight: .bold))
                    Text("CAM")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.12))
                        .foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.05))
                        .clipShape(Capsule())
                    Spacer()
                    Text(result == nil ? "先建模" : "实体就绪")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(result == nil ? .orange : .green)
                }

                Text("选择加工策略和刀具参数。工序按当前 3D 实体截面生成，预览在“加工”页。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                HStack {
                    Label("工序树", systemImage: "list.number")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Menu {
                        ForEach(True3DOperationKind.allCases) { kind in
                            Button(kind.rawValue) { appendOperation(kind) }
                        }
                    } label: {
                        Label("添加工序", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                VStack(spacing: 10) {
                    ForEach(operations.indices, id: \.self) { index in
                        operationCard(Binding(
                            get: { operations[index] },
                            set: { operations[index] = $0 }
                        ))
                    }
                }

                if operations.filter(\.enabled).isEmpty {
                    Label("至少启用一道工序才能生成刀路", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                group("安全 / 坐标 / 毛坯") {
                    numRow("安全高度 Z", $cam.safeZ)
                    numRow("XY 单边余量", $cam.stockMarginXY)
                    numRow("底面余量", $cam.stockExtraBottom)
                    Picker("工件坐标系", selection: $cam.coord) {
                        ForEach([54, 55, 56, 57, 58, 59], id: \.self) { c in
                            Text("G\(c)").tag(c)
                        }
                    }
                    numRow("零点偏移 X", $cam.originX)
                    numRow("零点偏移 Y", $cam.originY)
                    intRow("程序号 O", $cam.programNo)
                }
                group("毛坯 / 坐标") {
                    numRow("XY 单边余量", $cam.stockMarginXY)
                    numRow("底面余量", $cam.stockExtraBottom)
                    Picker("工件坐标系", selection: $cam.coord) {
                        ForEach([54, 55, 56, 57, 58, 59], id: \.self) { c in
                            Text("G\(c)").tag(c)
                        }
                    }
                    numRow("零点偏移 X", $cam.originX)
                    numRow("零点偏移 Y", $cam.originY)
                    intRow("程序号 O", $cam.programNo)
                }

                Button {
                    generateCAM(switchToMachine: true)
                } label: {
                    Label(isGeneratingCAM ? "正在生成刀路…" : "生成刀路并进入加工",
                          systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                .disabled(result == nil || isGeneratingCAM)

                if result == nil {
                    Button("回到建模页生成实体") { stage = .model }
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private var machineStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("加工")
                        .font(.system(size: 22, weight: .bold))
                    Text("3D 刀路")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.12))
                        .foregroundStyle(Color(red: 0.75, green: 0.26, blue: 0.05))
                        .clipShape(Capsule())
                    Spacer()
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let camResult {
                    Picker("模拟视图", selection: $simulationMode) {
                        Text("刀路轨迹").tag(0)
                        Text("材料去除").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if simulationMode == 0 {
                        True3DPathSimulation(segments: camResult.segments)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    } else {
                        True3DStockSimulation(
                            segments: camResult.segments,
                            model: result?.params ?? params,
                            toolRadius: (camResult.runs.map { $0.operation.toolDia }.max() ?? cam.toolDia) / 2
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 0) {
                        camMetric("切削", String(format: "%.0f mm", camResult.stats.cutLength))
                        Divider().frame(height: 28)
                        camMetric("层数", "\(camResult.stats.layerCount)")
                        Divider().frame(height: 28)
                        camMetric("路径", "\(camResult.stats.pathCount)")
                        Divider().frame(height: 28)
                        camMetric("Z", String(format: "%.1f~%.1f", camResult.stats.zMin, camResult.stats.zMax))
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    if !camResult.runs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("工序执行结果")
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(Array(camResult.runs.enumerated()), id: \.offset) { index, run in
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 18, height: 18)
                                        .background(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.14), in: Circle())
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(run.operation.kind.rawValue)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("T\(run.operation.toolNo) Ø\(fmt(run.operation.toolDia)) · \(run.segments.count) 段 · \(String(format: "%.0f", run.stats.cutLength)) mm")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !camResult.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(camResult.warnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(spacing: 10) {
                        Button {
                            generateCAM(switchToMachine: true)
                        } label: {
                            Label("重新生成", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingCAM)

                        if let gcodeURL {
                            ShareLink(item: gcodeURL) {
                                Label("分享 G 代码", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))

                    if let gcodeURL {
                        NavigationLink {
                            True3DGCodeScreen(code: camResult.gcode, fileURL: gcodeURL)
                        } label: {
                            HStack {
                                Label("查看完整 G 代码", systemImage: "text.alignleft")
                                Spacer()
                                Text("\(camResult.gcode.count) 字符")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("刀路还没生成", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .semibold))
                        Text("先在“工序”页选策略和刀具，再生成 3D 刀路。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button {
                            generateCAM(switchToMachine: true)
                        } label: {
                            Label("立即生成刀路", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                        .disabled(result == nil || isGeneratingCAM)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    stage = .operation
                } label: {
                    Label("查看 / 修改工序参数", systemImage: "square.stack.3d.up")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    private func camMetric(_ title: String, _ value: String) -> some View {
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

    private func opToggle(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func appendOperation(_ kind: True3DOperationKind) {
        var op = True3DOperation(kind: kind)
        switch kind {
        case .faceBase:
            op.toolDia = 16; op.toolNo = 1; op.stepDown = 2; op.stepOver = 12
            op.spindle = 3000; op.feed = 800; op.plungeFeed = 250
        case .rough:
            op.toolDia = 8; op.toolNo = 2; op.stepDown = 3; op.stepOver = 5
            op.spindle = 2500; op.feed = 600; op.plungeFeed = 180
        case .finish:
            op.toolDia = 4; op.toolNo = 3; op.stepDown = 1; op.stepOver = 2
            op.spindle = 4000; op.feed = 500; op.plungeFeed = 150
        case .clearInner:
            op.toolDia = 3; op.toolNo = 4; op.stepDown = 2; op.stepOver = 2
            op.spindle = 4500; op.feed = 400; op.plungeFeed = 120
        case .faceBoss:
            op.toolDia = 10; op.toolNo = 5; op.stepDown = 2; op.stepOver = 8
            op.spindle = 3000; op.feed = 700; op.plungeFeed = 200
        case .facePocket:
            op.toolDia = 3; op.toolNo = 4; op.stepDown = 2; op.stepOver = 2
            op.spindle = 4500; op.feed = 400; op.plungeFeed = 120
        }
        operations.append(op)
    }

    private func moveOperation(_ id: UUID, by delta: Int) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard target >= 0, target < operations.count else { return }
        operations.swapAt(index, target)
    }

    private func operationCard(_ operation: Binding<True3DOperation>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Toggle(isOn: operation.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(operation.wrappedValue.kind.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                        Text("T\(operation.wrappedValue.toolNo) · Ø\(fmt(operation.wrappedValue.toolDia)) · AP\(fmt(operation.wrappedValue.stepDown)) · AE\(fmt(operation.wrappedValue.stepOver))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Spacer()
                HStack(spacing: 3) {
                    Button { moveOperation(operation.wrappedValue.id, by: -1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    Button { moveOperation(operation.wrappedValue.id, by: 1) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    Button {
                        let id = operation.wrappedValue.id
                        operations.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            DisclosureGroup("刀具 / 切削参数") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        numRow("刀径 Ø", operation.toolDia)
                        intRow("T", operation.toolNo)
                    }
                    HStack(spacing: 8) {
                        intRow("H", operation.hNo)
                        intRow("转速 S", operation.spindle)
                    }
                    HStack(spacing: 8) {
                        numRow("切深 AP", operation.stepDown)
                        numRow("行距 AE", operation.stepOver)
                    }
                    HStack(spacing: 8) {
                        intRow("进给 F", operation.feed)
                        intRow("下刀 F", operation.plungeFeed)
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func generateCAM(switchToMachine: Bool = true) {
        guard let result else {
            error = "请先在建模页生成有效实体"
            stage = .model
            return
        }
        let enabled = operations.filter(\.enabled)
        guard !enabled.isEmpty else {
            error = "至少启用一道工序"
            stage = .operation
            return
        }
        guard !isGeneratingCAM else { return }
        error = nil
        notice = nil
        isGeneratingCAM = true
        var parameters = cam
        parameters.operations = enabled
        let modelResult = result
        let programNo = cam.programNo
        Task {
            do {
                let generated = try await Task.detached(priority: .userInitiated) {
                    try True3DCAM.generate(result: modelResult, model: modelResult.params, cam: parameters)
                }.value
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = dir.appendingPathComponent("MacroGen-3D-\(programNo).nc")
                try generated.gcode.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.camResult = generated
                    self.gcodeURL = url
                    self.isGeneratingCAM = false
                    if switchToMachine { self.stage = .machine }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.camResult = nil
                    self.gcodeURL = nil
                    self.isGeneratingCAM = false
                }
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
            Text("草图拉伸/切除 · 实体布尔 · 多孔/凸台/型腔/腰槽 · DXF/照片 · STEP/STL")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var modelToolBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    modelTool("草图", "pencil.tip.crop.circle") { stage = .sketch }
                    modelTool("孔", "circle.dashed") { addFeature(.hole) }
                    modelTool("凸台", "arrow.up.circle") { addFeature(.boss) }
                    modelTool("矩形凸台", "rectangle") { addFeature(.rectBoss) }
                    modelTool("锥形凸台", "triangle") { addFeature(.coneBoss) }
                    modelTool("放样凸台", "square.stack.3d.up") { addFeature(.loftBoss) }
                    modelTool("螺旋扫掠", "point.3.connected.trianglepath.dotted") { addFeature(.sweepBoss) }
                    modelTool("拔模", "square.on.square.dashed") { addFeature(.draft) }
                    modelTool("全边圆角", "circle.dashed") { addFeature(.edgeFillet) }
                    modelTool("全边倒角", "square.dashed") { addFeature(.edgeChamfer) }
                    modelTool("抽壳", "cube.transparent") { addFeature(.shell) }
                    modelTool("旋转凸台", "rotate.3d") { addFeature(.revolveBoss) }
                    modelTool("旋转切除", "rotate.3d.fill") { addFeature(.revolveCut) }
                    modelTool("圆腔", "circle.bottomhalf.filled") { addFeature(.circularPocket) }
                    modelTool("方腔", "rectangle.inset.filled") { addFeature(.rectPocket) }
                    modelTool("腰槽", "capsule") { addFeature(.slot) }
                    modelTool("矩形孔阵", "square.grid.3x3") { addHolePattern() }
                    modelTool("圆周孔阵", "circle.grid.3x3") { addCircularHolePattern() }
                    modelTool("特征面板", "sidebar.right") { showModelDrawer = true }
                }
            }
            .disabled(isBuilding || importBusy)
            Text("先选草图轮廓或直接加特征，再点“生成实体”；所有参数在抽屉里精调。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func modelTool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.10), in: Capsule())
                .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.05))
        }
        .buttonStyle(.plain)
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

    private var inlineFeatureStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("当前特征 \(params.features.count)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("编辑全部") { showModelDrawer = true }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(params.features) { feature in
                        HStack(spacing: 5) {
                            Image(systemName: icon(for: feature.kind))
                                .font(.system(size: 10))
                            Text(feature.name)
                                .font(.system(size: 10, weight: .semibold))
                            Text(feature.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .onTapGesture {
                            selectedFeatureID = feature.id
                            showModelDrawer = true
                        }
                    }
                }
            }
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
                    Button { stage = .sketch } label: {
                        Label("回到草图", systemImage: "pencil.tip.crop.circle")
                    }
                    Divider()
                    Button("孔") { addFeature(.hole) }
                    Button("凸台") { addFeature(.boss) }
                    Button("矩形凸台") { addFeature(.rectBoss) }
                    Button("锥形凸台") { addFeature(.coneBoss) }
                    Button("放样凸台") { addFeature(.loftBoss) }
                    Button("螺旋扫掠") { addFeature(.sweepBoss) }
                    Button("拔模") { addFeature(.draft) }
                    Button("全边圆角") { addFeature(.edgeFillet) }
                    Button("全边倒角") { addFeature(.edgeChamfer) }
                    Button("抽壳") { addFeature(.shell) }
                    Button("旋转凸台") { addFeature(.revolveBoss) }
                    Button("旋转切除") { addFeature(.revolveCut) }
                    Button("圆腔") { addFeature(.circularPocket) }
                    Button("方腔") { addFeature(.rectPocket) }
                    Button("腰形槽") { addFeature(.slot) }
                    Divider()
                    Button("3×3 孔阵列") { addHolePattern() }
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

    private var patternArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("阵列 / 镜像")
            HStack(spacing: 8) {
                Stepper("行 \(patternRows)", value: $patternRows, in: 1...8)
                    .font(.system(size: 11))
                Stepper("列 \(patternCols)", value: $patternCols, in: 1...8)
                    .font(.system(size: 11))
            }
            numRow("X 孔距", $patternPitchX)
            numRow("Y 孔距", $patternPitchY)
            numRow("阵列孔径", $patternHoleDia)
            Button {
                addHolePattern()
            } label: {
                Label("生成矩形孔阵", systemImage: "square.grid.3x3")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 1.0, green: 0.42, blue: 0.10))

            Divider()
            HStack {
                Stepper("圆周 \(circularCount)", value: $circularCount, in: 3...24)
                    .font(.system(size: 11))
                Spacer()
                Text("Ø\(fmt(patternHoleDia))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            numRow("圆周半径", $circularRadius)
            Button {
                addCircularHolePattern()
            } label: {
                Label("生成圆周孔阵", systemImage: "circle.grid.3x3")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let selectedFeatureID,
               let feature = params.features.first(where: { $0.id == selectedFeatureID }) {
                Divider()
                Text("选中：\(feature.name)")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 6) {
                    Button("复制") { duplicateFeature(feature.id) }.buttonStyle(.bordered)
                    Button("镜像 X") { mirrorFeature(feature.id) }.buttonStyle(.bordered)
                    Button("上移") { moveFeature(feature.id, by: -1) }.buttonStyle(.bordered)
                    Button("下移") { moveFeature(feature.id, by: 1) }.buttonStyle(.bordered)
                }
                .font(.system(size: 10))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
            case .rectBoss:
                numRow("X 长", f.width)
                numRow("Y 宽", f.depthY)
                numRow("高度 H", f.bossHeight)
                numRow("圆角 R", f.cornerRadius)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            case .coneBoss:
                numRow("底直径", f.dia)
                numRow("顶直径", f.topDia)
                numRow("高度 H", f.bossHeight)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            case .loftBoss:
                Picker("底截面", selection: f.loftBottomShape) {
                    ForEach(True3DLoftShape.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .font(.system(size: 12))
                if f.wrappedValue.loftBottomShape == .circle {
                    numRow("底直径", f.dia)
                } else {
                    numRow("底 X", f.width)
                    numRow("底 Y", f.depthY)
                }
                Picker("顶截面", selection: f.loftTopShape) {
                    ForEach(True3DLoftShape.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .font(.system(size: 12))
                if f.wrappedValue.loftTopShape == .circle {
                    numRow("顶直径", f.topDia)
                } else {
                    numRow("顶 X", f.topWidth)
                    numRow("顶 Y", f.topDepthY)
                }
                numRow("高度 H", f.bossHeight)
                numRow("中心 X", f.x)
                numRow("中心 Y", f.y)
            case .sweepBoss:
                numRow("截面 Ø", f.dia)
                numRow("路径 R", f.sweepPathRadius)
                numRow("螺距", f.sweepPitch)
                numRow("圈数", f.sweepTurns)
            case .draft:
                numRow("拔模角 °", f.angle)
                Text("拔模面：当前实体所有竖直面，中性面 Z=0")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            case .edgeFillet:
                Picker("边选择", selection: f.edgeSelection) {
                    ForEach(True3DEdgeSelection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .font(.system(size: 12))
                numRow("圆角 R", f.depth)
            case .edgeChamfer:
                Picker("边选择", selection: f.edgeSelection) {
                    ForEach(True3DEdgeSelection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .font(.system(size: 12))
                numRow("倒角 C", f.depth)
            case .shell:
                numRow("壁厚", f.depth)
                Text("开口面：当前实体所有朝上的面")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            case .revolveBoss, .revolveCut:
                Picker("基准面", selection: f.revolvePlane) {
                    ForEach(True3DRevolvePlane.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .font(.system(size: 12))
                Picker("旋转轴", selection: f.revolveAxis) {
                    ForEach(True3DRevolveAxis.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .font(.system(size: 12))
                Text("旋转轮廓：\(f.wrappedValue.profile.count) 点；基准面决定 2D 坐标映射，旋转轴可独立选 X/Y/Z")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                numRow("角度 °", f.angle)
                if f.wrappedValue.kind == .revolveBoss {
                    numRow("高度 H", f.bossHeight)
                } else {
                    numRow("切除深度", f.depth)
                }
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
            case .profileBoss:
                Text("草图轮廓：\(f.wrappedValue.profile.count) 个点")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                numRow("拉伸高度", f.bossHeight)
            case .profileCut:
                Text("草图轮廓：\(f.wrappedValue.profile.count) 个点")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                numRow("切除深度", f.depth)
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

    private func intRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12))
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 82)
                .textFieldStyle(.roundedBorder)
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
        case .rectBoss: return "rectangle"
        case .coneBoss: return "triangle"
        case .loftBoss: return "square.stack.3d.up"
        case .sweepBoss: return "point.3.connected.trianglepath.dotted"
        case .draft: return "square.on.square.dashed"
        case .edgeFillet: return "circle.dashed"
        case .edgeChamfer: return "square.dashed"
        case .shell: return "cube.transparent"
        case .revolveBoss: return "rotate.3d"
        case .revolveCut: return "rotate.3d.fill"
        case .circularPocket: return "circle.dashed"
        case .rectPocket: return "square.dashed"
        case .slot: return "capsule"
        case .profileBoss: return "square.3.layers.3d"
        case .profileCut: return "square.3.layers.3d.down.right"
        }
    }

    private func addFeature(_ kind: True3DFeatureKind) {
        var f = True3DFeatureSpec(kind: kind)
        switch kind {
        case .hole:
            f.name = "新孔"; f.x = -params.width * 0.25; f.dia = 10
        case .boss:
            f.name = "新凸台"; f.x = params.width * 0.25; f.y = params.depth * 0.15; f.dia = 20; f.bossHeight = 6
        case .rectBoss:
            f.name = "新矩形凸台"; f.x = params.width * 0.25; f.y = params.depth * 0.15
            f.width = 30; f.depthY = 20; f.bossHeight = 6
        case .coneBoss:
            f.name = "锥形凸台"; f.x = params.width * 0.25; f.y = params.depth * 0.15
            f.dia = 24; f.topDia = 12; f.bossHeight = 8
        case .loftBoss:
            f.name = "放样凸台"; f.x = 0; f.y = 0
            f.bossHeight = 10
        case .sweepBoss:
            f.name = "螺旋扫掠"; f.x = 0; f.y = 0
            f.dia = 8; f.sweepPathRadius = 25; f.sweepPitch = 12; f.sweepTurns = 2
        case .draft:
            f.name = "拔模"; f.angle = 3
        case .edgeFillet:
            f.name = "全边圆角"; f.depth = 1.5
        case .edgeChamfer:
            f.name = "全边倒角"; f.depth = 1
        case .shell:
            f.name = "抽壳"; f.depth = min(2, min(params.width, params.depth, params.height) / 4)
        case .revolveBoss:
            f = True3DFeatureSpec(kind: .revolveBoss)
            f.name = "旋转凸台"
        case .revolveCut:
            f = True3DFeatureSpec(kind: .revolveCut)
            f.name = "旋转切除"
        case .circularPocket:
            f.name = "新圆腔"; f.x = -params.width * 0.25; f.dia = 20; f.depth = 5
        case .rectPocket:
            f.name = "新方腔"; f.x = params.width * 0.25; f.y = -params.depth * 0.2; f.width = 24; f.depthY = 18
        case .slot:
            f.name = "新腰形槽"; f.x = 0; f.y = -params.depth * 0.25; f.width = 40; f.depthY = 12
        case .profileBoss, .profileCut:
            return
        }
        params.features.append(f)
        selectedFeatureID = f.id
        rebuild()
        notice = "已添加 \(f.name)，可在特征面板里改尺寸"
    }

    private func addHolePattern() {
        let rows = max(1, min(patternRows, 8))
        let cols = max(1, min(patternCols, 8))
        let dia = max(patternHoleDia, 0.5)
        let maxPitchX = max((params.width - dia - 2) / Double(max(cols - 1, 1)), 1)
        let maxPitchY = max((params.depth - dia - 2) / Double(max(rows - 1, 1)), 1)
        let pitchX = min(max(patternPitchX, dia + 0.5), maxPitchX)
        let pitchY = min(max(patternPitchY, dia + 0.5), maxPitchY)
        let startX = -pitchX * Double(cols - 1) / 2
        let startY = -pitchY * Double(rows - 1) / 2
        for r in 0..<rows {
            for c in 0..<cols {
                var f = True3DFeatureSpec(kind: .hole)
                f.name = "阵列孔 \(r + 1)-\(c + 1)"
                f.x = startX + Double(c) * pitchX
                f.y = startY + Double(r) * pitchY
                f.dia = dia
                f.holeKind = .through
                params.features.append(f)
            }
        }
        selectedFeatureID = params.features.last?.id
        rebuild()
        notice = "已添加 \(rows)×\(cols) 孔阵列，间距 \(fmt(pitchX))×\(fmt(pitchY)) mm"
    }

    private func addCircularHolePattern() {
        let count = max(3, min(circularCount, 24))
        let dia = max(patternHoleDia, 0.5)
        let maxR = min(params.width, params.depth) / 2 - dia - 1
        guard maxR > 2 else {
            error = "基础块太小，放不下圆周阵列"
            return
        }
        let radius = min(max(circularRadius, 2), maxR)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            var f = True3DFeatureSpec(kind: .hole)
            f.name = "圆周孔 \(i + 1)"
            f.x = radius * cos(angle)
            f.y = radius * sin(angle)
            f.dia = dia
            f.holeKind = .through
            params.features.append(f)
        }
        selectedFeatureID = params.features.last?.id
        rebuild()
        notice = "已添加 \(count) 孔圆周阵列，R\(fmt(radius))"
    }

    private func duplicateFeature(_ id: UUID) {
        guard var feature = params.features.first(where: { $0.id == id }) else { return }
        feature.id = UUID()
        feature.name += " 副本"
        feature.x += min(max(feature.width, feature.dia) / 2 + 2, 20)
        params.features.append(feature)
        selectedFeatureID = feature.id
        rebuild()
        notice = "已复制 \(feature.name)"
    }

    private func mirrorFeature(_ id: UUID) {
        guard var feature = params.features.first(where: { $0.id == id }) else { return }
        feature.id = UUID()
        feature.name += " 镜像"
        feature.x = -feature.x
        feature.profile = feature.profile.map { True3DPoint(x: -$0.x, y: $0.y) }
        params.features.append(feature)
        selectedFeatureID = feature.id
        rebuild()
        notice = "已沿 X=0 镜像 \(feature.name)"
    }

    private func moveFeature(_ id: UUID, by delta: Int) {
        guard let index = params.features.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard target >= 0, target < params.features.count else { return }
        params.features.swapAt(index, target)
        rebuild()
        notice = "已\(delta < 0 ? "上移" : "下移")特征"
    }

    private func profileArea(_ points: [True3DPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum / 2)
    }

    private func profileBox(_ points: [True3DPoint]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return (minX, maxX, minY, maxY)
    }

    private func applySketch(_ output: True3DSketchOutput) {
        if params.features.count == 3,
           params.features.contains(where: { $0.name == "通孔" }),
           params.features.contains(where: { $0.name == "凸台" }),
           params.features.contains(where: { $0.name == "方腔" }) {
            params.features = []
        }
        var message = ""
        switch output {
        case .base(let points):
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            params.baseShape = .profile
            params.profile = points
            params.edgeMode = .none
            params.edgeSize = 0
            if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                params.width = max(maxX - minX, 1)
                params.depth = max(maxY - minY, 1)
            }
            message = "已用草图轮廓替换基础形状；Z 高在建模页设置"
        case .feature(let feature):
            params.features.append(feature)
            selectedFeatureID = feature.id
            message = "已添加 \(feature.name)，正在重建实体"
        case .features(let features):
            var additions = features
            if let outer = features.max(by: { profileArea($0.profile) < profileArea($1.profile) }),
               !features.contains(where: { $0.kind == .profileCut }) {
                let outerBox = profileBox(outer.profile)
                additions = [outer]
                for feature in features where feature.id != outer.id {
                    let box = profileBox(feature.profile)
                    if let outerBox, let box,
                       box.minX >= outerBox.minX - 0.01, box.maxX <= outerBox.maxX + 0.01,
                       box.minY >= outerBox.minY - 0.01, box.maxY <= outerBox.maxY + 0.01,
                       profileArea(feature.profile) < profileArea(outer.profile) {
                        var cut = feature
                        cut.kind = .profileCut
                        cut.name = "草图内孔"
                        cut.depth = feature.bossHeight
                        cut.topZ = params.height + feature.bossHeight
                        additions.append(cut)
                    } else {
                        additions.append(feature)
                    }
                }
            }
            params.features.append(contentsOf: additions)
            selectedFeatureID = additions.last?.id
            message = "已添加 \(additions.count) 个草图轮廓特征，正在重建实体"
        }
        rebuild()
        notice = message
    }

    private func newBlankProject() {
        params = True3DParams()
        params.projectName = "未命名工程"
        params.features = []
        selectedFeatureID = nil
        notice = "已新建空白工程：先画草图，或直接添加孔/凸台/型腔"
        stage = .sketch
        rebuild()
    }

    private func rebuild() {
        error = nil
        notice = nil
        result = nil
        scene = SCNScene()
        camResult = nil
        gcodeURL = nil
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
    private func fmt(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private static func defaultOperations() -> [True3DOperation] {
        var ops: [True3DOperation] = []
        for kind in True3DOperationKind.allCases {
            var op = True3DOperation(kind: kind)
            switch kind {
            case .faceBase:
                op.toolDia = 16; op.toolNo = 1; op.stepDown = 2; op.stepOver = 12
                op.spindle = 3000; op.feed = 800; op.plungeFeed = 250
            case .rough:
                op.toolDia = 8; op.toolNo = 2; op.stepDown = 3; op.stepOver = 5
                op.spindle = 2500; op.feed = 600; op.plungeFeed = 180
            case .finish:
                op.toolDia = 4; op.toolNo = 3; op.stepDown = 1; op.stepOver = 2
                op.spindle = 4000; op.feed = 500; op.plungeFeed = 150
            case .clearInner:
                op.toolDia = 3; op.toolNo = 4; op.stepDown = 2; op.stepOver = 2
                op.spindle = 4500; op.feed = 400; op.plungeFeed = 120
            case .faceBoss:
                op.toolDia = 10; op.toolNo = 5; op.stepDown = 2; op.stepOver = 8
                op.spindle = 3000; op.feed = 700; op.plungeFeed = 200
            case .facePocket:
                op.toolDia = 3; op.toolNo = 4; op.stepDown = 2; op.stepOver = 2
                op.spindle = 4500; op.feed = 400; op.plungeFeed = 120
            }
            ops.append(op)
        }
        return ops
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
