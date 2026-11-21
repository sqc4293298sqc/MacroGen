import Foundation
import QuartzCore
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

private enum True3DViewOrientation {
    case iso
    case top
    case front
    case right
    case back
}

private enum True3DImportMode {
    case step
    case dxf
}

private enum True3DPickMode {
    case edge
    case face
}

private struct True3DFaceSelection {
    var faceIndex: Int
    var point: SIMD3<Double>
    var normal: SIMD3<Double>
    var sizeX: Double
    var sizeY: Double
}

/// 真 3D 工作台：草图 → 建模 → 工序 → 加工 一条线完成。
struct True3DAssemblyComponent: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var rotationZ: Double = 0
    var colorIndex: Int = 0
    var part: True3DParams = True3DParams()

    var summary: String {
        "\(part.features.count) 特征 · \(String(format: "%.0f", part.width))×\(String(format: "%.0f", part.depth))×\(String(format: "%.0f", part.height))"
    }
}

struct True3DModelScreen: View {
    @State private var params = True3DParams()
    @State private var modelDocumentID = UUID()
    @State private var importedPart: True3DImportedPart?
    @State private var modelOperations: [True3DHistoryOperation] = []
    @State private var selectedEdge: True3DEdgeRef?
    @State private var selectedFace: True3DFaceSelection?
    @State private var pickMode: True3DPickMode = .edge
    @State private var pendingFaceExtrude = false
    @State private var draftFeature: True3DFeatureSpec?
    @State private var showFeatureDrawer = false
    @State private var filletRadius: Double = 2
    @State private var filletPreview: True3DPreview?
    @State private var filletPreviewRadius: Double?
    @State private var edgeFeatureIsChamfer = false
    @State private var viewOrientation: True3DViewOrientation = .iso
    @State private var orbitYaw: Double = 45
    @State private var orbitPitch: Double = 29
    @State private var orbitDistance: Double?
    @State private var cubeDragActive = false
    @State private var cubeDragStartYaw: Double = 45
    @State private var cubeDragStartPitch: Double = 29
    @State private var isPreviewingFillet = false
    @State private var filletPreviewTask: Task<Void, Never>?
    @State private var filletPreviewGeneration = 0
    @State private var importMode: True3DImportMode = .dxf
    @State private var scene = SCNScene()
    @State private var result: True3DResult?
    @State private var error: String?
    @State private var notice: String?
    @State private var message = "点“生成实体”创建 OCCT 实体"
    @State private var showWire = true
    @State private var showDatumPlane = false
    @State private var renderDark = false
    @State private var stepURL: URL?
    @State private var stlURL: URL?
    @State private var isBuilding = false
    @State private var buildTask: Task<Void, Never>?
    @State private var buildGeneration = 0
    @State private var kernelService = True3DKernelService()
    @State private var assemblyBuildTask: Task<Void, Never>?
    @State private var assemblyGeneration = 0
    @State private var didInitialBuild = false
    @State private var selectedFeatureID: UUID?
    @State private var pendingFeatureID: UUID?
    @State private var stage: True3DWorkbenchStage = .model
    @State private var sketchProfile: [True3DPoint] = []
    @State private var sketchClosed = false
    @State private var sketchTool: True3DSketchTool = .polyline
    @State private var sketchSavedProfiles: [[True3DPoint]] = []
    @State private var showProgramSheet = false
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
    @State private var showTreePanel = false
    @State private var showToolbox = false
    @State private var edgeFilterLabel = "单条边"
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
    @State private var assemblyEditingID: UUID?
    @State private var assemblyError: String?

    private var isDirty: Bool {
        guard let result else { return false }
        let builtOperationIDs = result.nodes.compactMap { $0.operationID }
        let currentOperationIDs = modelOperations.map { $0.id }
        if importedPart != nil {
            return result.documentID != modelDocumentID || builtOperationIDs != currentOperationIDs
        }
        return result.params != params
            || result.documentID != modelDocumentID
            || builtOperationIDs != currentOperationIDs
    }

    private var dxfType: UTType {
        UTType(filenameExtension: "dxf") ?? .plainText
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                workbenchTopTabs
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
        .navigationTitle(params.projectName.isEmpty ? "3D绘图建模" : params.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(stage == .model || stage == .sketch ? .hidden : .visible, for: .navigationBar)
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
                        Button {
                            importMode = .step
                            showImporter = true
                        } label: {
                            Label("导入 STEP 模型", systemImage: "cube.transparent")
                        }
                        Button {
                            importMode = .dxf
                            showImporter = true
                        } label: {
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
            if importedPart != nil, newStage == .operation || newStage == .machine {
                self.error = "STEP 模型暂不支持 CAM 工序；请先导出 STEP/STL，或退出 STEP"
                stage = .model
                return
            }
            if newStage == .assembly {
                if importedPart != nil {
                    assemblyError = "STEP 零件暂不支持装配快照；请先“退出 STEP”"
                    return
                }
                if assemblyComponents.isEmpty, result != nil {
                    assemblyComponents = [True3DAssemblyComponent(name: "零件 1", colorIndex: 0, part: params)]
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
        .sheet(isPresented: $showImporter) {
            True3DDocumentPicker(isPresented: $showImporter) { url in
                handlePickedFile(url)
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
        .sheet(isPresented: $showProgramSheet) {
            True3DProgramSheet(
                projectName: params.projectName.isEmpty ? "未命名工程" : params.projectName,
                profile: sketchProfile,
                width: params.width,
                depth: params.depth,
                height: params.height,
                scene: scene,
                cam: cam,
                operations: cam.operations,
                stats: result?.stats
            )
        }
        .onDisappear {
            buildTask?.cancel()
            assemblyBuildTask?.cancel()
            filletPreviewTask?.cancel()
            buildGeneration += 1
            assemblyGeneration += 1
            filletPreviewGeneration += 1
            isBuilding = false
            isPreviewingFillet = false
        }
    }

    private var workbenchTopTabs: some View {
        HStack(spacing: 2) {
            ForEach([True3DWorkbenchStage.sketch, .model, .operation, .machine], id: \.id) { item in
                Button {
                    stage = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(stage == item ? SwiftUI.Color(red: 0.10, green: 0.42, blue: 0.90) : SwiftUI.Color.primary.opacity(0.58))
                        .background(
                            stage == item
                                ? SwiftUI.Color(red: 0.10, green: 0.42, blue: 0.90).opacity(0.10)
                                : SwiftUI.Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 22)
            Button {
                showProgramSheet = true
            } label: {
                Label("程序单", systemImage: "doc.text")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .foregroundStyle(SwiftUI.Color.primary.opacity(0.72))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SwiftUI.Color.black.opacity(0.06)).frame(height: 0.5)
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
    private var stageContent: AnyView {
        switch stage {
        case .sketch:
            return AnyView(sketchStage)
        case .model:
            return AnyView(digit3DModelingStage)
        case .assembly:
            return AnyView(assemblyStage)
        case .operation:
            return AnyView(operationStage)
        case .machine:
            return AnyView(machineStage)
        }
    }

    private var sketchStage: some View {
        True3DSketchScreen(
            width: params.width,
            depth: params.depth,
            embedded: true,
            initialProfile: sketchProfile,
            initialClosed: sketchClosed,
            initialTool: sketchTool,
            initialSavedProfiles: sketchSavedProfiles,
            onBaseChange: { w, d in
                params.width = max(w, 1)
                params.depth = max(d, 1)
            },
            onBack: { stage = .model },
            onDraftChange: { points, closed, tool, saved in
                sketchProfile = points
                sketchClosed = closed
                sketchTool = tool
                sketchSavedProfiles = saved
            }
        ) { output in
            applySketch(output)
            stage = .model
        }
    }


    private var digit3DModelingStage: AnyView {
        AnyView(ZStack {
            True3DSceneView(scene: scene, showWire: showWire, onPickEdge: { view, point, size in
                pickEdge(in: view, at: point, viewSize: size)
            })
            .ignoresSafeArea()

            VStack(spacing: 8) {
                AnyView(digit3DTopBar)
                AnyView(digit3DSelectionBar)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            HStack(alignment: .top, spacing: 0) {
                AnyView(digit3DLeftRail)
                Spacer(minLength: 0)
                AnyView(digit3DRightRail)
            }
            .padding(.horizontal, 10)
            .padding(.top, 215)
            .padding(.bottom, 90)

            if showFeatureDrawer, let draft = draftFeature {
                VStack {
                    Spacer(minLength: 0)
                    AnyView(featureDrawer(draft))
                        .transition(.move(edge: .bottom))
                }
                .zIndex(20)
            }

            VStack {
                Spacer()
                Text(bottomHint)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 28)
            }

            VStack {
                HStack {
                    Spacer()
                    AnyView(viewCube)
                }
                .padding(.trailing, 14)
                .padding(.top, 112)
                Spacer()
            }

            if showTreePanel {
                Color.black.opacity(0.10).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showTreePanel = false } }
                HStack {
                    Spacer()
                    AnyView(digit3DTreePanel)
                }
                .padding(.trailing, 10)
                .padding(.top, 132)
                .padding(.bottom, 70)
                .transition(.move(edge: .trailing))
            }

            if showToolbox {
                Color.black.opacity(0.10).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showToolbox = false } }
                HStack {
                    AnyView(digit3DToolbox)
                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.top, 132)
                .padding(.bottom, 70)
                .transition(.move(edge: .leading))
            }

            if let toast = error ?? notice {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(error == nil ? SwiftUI.Color.primary.opacity(0.72) : SwiftUI.Color(red: 0.82, green: 0.20, blue: 0.16))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.horizontal, 30)
                        .padding(.bottom, 58)
                        .onTapGesture { error = nil; notice = nil }
                }
                .transition(.opacity)
            }

            if isBuilding {
                VStack {
                    Spacer()
                    HStack(spacing: 7) {
                        ProgressView().scaleEffect(0.7)
                        Text(message ?? "正在构建…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 28)
                }
            }
        }
        .background(SwiftUI.Color(red: 0.95, green: 0.96, blue: 0.98))
        .onChange(of: filletRadius) { _ in
            if filletPreview != nil || isPreviewingFillet {
                clearFilletPreview(restoreScene: true)
            }
        })
    }

    private var workbenchTitle: String {
        if let importedPart, !importedPart.name.isEmpty { return importedPart.name }
        return params.projectName.isEmpty ? "未命名工程" : params.projectName
    }

    private var bottomHint: String {
        if let face = selectedFace {
            return "已选面 #\(face.faceIndex) · 点左侧命令设置参数"
        }
        if let edge = selectedEdge {
            return "已选边 #\(edge.edgeIndex) · 点左侧圆角/倒角设置参数"
        }
        if pendingFaceExtrude {
            return "先轻点一个朝上的面，再设置拉伸参数"
        }
        return pickMode == .edge ? "轻点边线选择，点左侧命令打开参数框" : "轻点面选择，点左侧命令打开参数框"
    }

    private var digit3DTopBar: some View {
        HStack(spacing: 8) {
            Button {
                stage = .sketch
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Menu {
                Button { rebuild() } label: { Label("重新构建模型", systemImage: "arrow.clockwise") }
                Button { importMode = .step; showImporter = true } label: {
                    Label("导入 STEP", systemImage: "cube.transparent")
                }
                Button { saveProject() } label: { Label("保存工程", systemImage: "square.and.arrow.down") }
                Divider()
                Button { exportSTEP() } label: { Label("导出 STEP", systemImage: "square.and.arrow.up") }
                Button { exportSTL() } label: { Label("导出 STL", systemImage: "square.and.arrow.up") }
            } label: {
                HStack(spacing: 8) {
                    Text(workbenchTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            workbenchIconButton("square.stack.3d.up", active: showTreePanel) {
                withAnimation(.easeOut(duration: 0.2)) { showTreePanel.toggle() }
            }
            workbenchIconButton("square.and.arrow.down") { saveProject() }
            Menu {
                Button { importMode = .step; showImporter = true } label: {
                    Label("导入 STEP", systemImage: "cube.transparent")
                }
                Button { stage = .operation } label: { Label("进入工序", systemImage: "square.stack.3d.up") }
                Button { stage = .assembly } label: { Label("进入装配", systemImage: "square.stack.3d.up.fill") }
                Divider()
                Button { newBlankProject() } label: { Label("新建空白工程", systemImage: "doc.badge.plus") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var digit3DSelectionBar: some View {
        HStack(spacing: 6) {
            Button {
                pickMode = .edge
                notice = "选择模式：边"
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.diagonal").font(.system(size: 11, weight: .semibold))
                    Text("边").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(pickMode == .edge ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85) : SwiftUI.Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(pickMode == .edge ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.12) : SwiftUI.Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                pickMode = .face
                notice = "选择模式：面"
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.dashed").font(.system(size: 11, weight: .semibold))
                    Text("面").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(pickMode == .face ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85) : SwiftUI.Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(pickMode == .face ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.12) : SwiftUI.Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)

            if let face = selectedFace {
                Text("面 #\(face.faceIndex) · Z \(fmt(face.point.z))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(pickMode == .edge ? "轻点边线" : "轻点面")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showToolbox.toggle() }
            } label: {
                Image(systemName: "cube.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85))
                    .frame(width: 28, height: 28)
                    .background(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(SwiftUI.Color.white.opacity(0.55), lineWidth: 0.5))
        .frame(maxWidth: 370)
    }

    private func workbenchIconButton(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85) : SwiftUI.Color.primary)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var digit3DLeftRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                railItem("pencil", "草图", highlighted: false) { stage = .sketch }
                railItem("eye", "基准面", highlighted: showDatumPlane) { toggleDatumPlane() }
                railItem("arrow.up.to.line", "拉伸", highlighted: pendingFaceExtrude) { beginFaceExtrude() }
                railItem("arrow.triangle.2.circlepath", "旋转体") { openFeatureDrawer(.revolveBoss) }
                railItem("arrow.triangle.2.circlepath.circle", "同步") {
                    notice = "正在同步草图与实体…"
                    rebuild()
                }
                railItem("water.waves", "曲面") {
                    showWire = false
                    notice = "曲面着色显示：已关闭线框"
                }
                railItem("line.diagonal", "圆角", highlighted: selectedEdge != nil) {
                    openEdgeDrawer(chamfer: false)
                }
                railItem("square.dashed", "抽壳") { openFeatureDrawer(.shell) }
                railItem("scribble", "3D曲线") { stage = .sketch }
                railItem("plus.square", "更多") {
                    withAnimation(.easeOut(duration: 0.2)) { showToolbox = true }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
        }
        .frame(width: 60)
        .frame(maxHeight: 470)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var digit3DRightRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                railItem("square.stack.3d.up", "建模树", highlighted: showTreePanel) {
                    withAnimation(.easeOut(duration: 0.2)) { showTreePanel.toggle() }
                }
                railItem("point.3.connected.trianglepath.dotted", "模型树") {
                    withAnimation(.easeOut(duration: 0.2)) { showTreePanel.toggle() }
                }
                railItem("eye", "显示", highlighted: showWire) { showWire.toggle() }
                railItem("ruler", "测量") { announceMeasurement() }
                railItem("waveform.path.ecg", "分析") { announceAnalysis() }
                railItem("sun.max", "渲染", highlighted: renderDark) { toggleRenderMode() }
                railItem("arrow.counterclockwise", "视图复位") {
                    setViewOrientation(.iso)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
        }
        .frame(width: 60)
        .frame(maxHeight: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func railItem(
        _ icon: String,
        _ title: String,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            error = nil
            notice = nil
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(highlighted ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85) : SwiftUI.Color.primary.opacity(0.74))
            .frame(width: 50, height: 42)
            .background(
                highlighted
                    ? SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.12)
                    : SwiftUI.Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }

    private var viewCube: some View {
        ZStack {
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let top = Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: 0))
                    path.addLine(to: CGPoint(x: w, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.56))
                    path.addLine(to: CGPoint(x: 0, y: h * 0.28))
                    path.closeSubpath()
                }
                let front = Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.56))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.98))
                    path.addLine(to: CGPoint(x: 0, y: h * 0.70))
                    path.closeSubpath()
                }
                let right = Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.56))
                    path.addLine(to: CGPoint(x: w, y: h * 0.28))
                    path.addLine(to: CGPoint(x: w, y: h * 0.70))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.98))
                    path.closeSubpath()
                }
                context.fill(top, with: .color(SwiftUI.Color.white.opacity(0.97)))
                context.fill(front, with: .color(SwiftUI.Color.white.opacity(0.80)))
                context.fill(right, with: .color(SwiftUI.Color.white.opacity(0.91)))
                for path in [top, front, right] {
                    context.stroke(path, with: .color(SwiftUI.Color.black.opacity(0.16)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)

            cubeFaceButton("顶", x: 48, y: 24, width: 74, height: 34) {
                setViewOrientation(.top)
            }
            cubeFaceButton("前", x: 24, y: 72, width: 44, height: 42) {
                setViewOrientation(.front)
            }
            cubeFaceButton("右", x: 74, y: 72, width: 44, height: 42) {
                setViewOrientation(.right)
            }
            cubeFaceButton("后", x: 48, y: 111, width: 78, height: 30) {
                setViewOrientation(.back)
            }
        }
        .frame(width: 96, height: 128)
        .background(
            Ellipse()
                .fill(SwiftUI.Color.black.opacity(0.06))
                .frame(width: 70, height: 18)
                .offset(y: 48)
        )
        .shadow(color: SwiftUI.Color.black.opacity(0.10), radius: 8, y: 4)
    }

    private func cubeFaceButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SwiftUI.Color.black.opacity(0.62))
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: x, y: y)
    }

    private func featureDrawer(_ draft: True3DFeatureSpec) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: draft.kind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(featureDrawerTitle)
                        .font(.system(size: 17, weight: .bold))
                    Text(draft.kind.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { closeFeatureDrawer() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(SwiftUI.Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if draft.kind == .edgeFillet || draft.kind == .edgeChamfer {
                        edgeDrawerFields(draft)
                    } else {
                        if supportsCoordinates(draft.kind) {
                            coordinateEditor(featureDraftBinding)
                        }
                        featureEditor(featureDraftBinding, showPosition: false)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 360)

            Divider().opacity(0.4)
            HStack(spacing: 10) {
                Button {
                    closeFeatureDrawer()
                } label: {
                    Text("取消").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(SwiftUI.Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    commitFeatureDrawer()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("确定添加")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isBuilding || importBusy || ((draft.kind == .edgeFillet || draft.kind == .edgeChamfer) && selectedEdge == nil))
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SwiftUI.Color.white.opacity(0.5), lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func edgeDrawerFields(_ draft: True3DFeatureSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("边选择").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if let edge = selectedEdge {
                HStack {
                    Image(systemName: "line.diagonal")
                    Text("边 #\(edge.edgeIndex) · \(fmt(edge.length)) mm")
                    Spacer()
                    Button("重选") {
                        selectedEdge = nil
                        pickMode = .edge
                        notice = "轻点一条边"
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 12))
                .padding(10)
                .background(SwiftUI.Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Button {
                    pickMode = .edge
                    notice = "轻点一条边"
                } label: {
                    Label("在三维模型上选择一条边", systemImage: "line.diagonal")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text(draft.kind == .edgeChamfer ? "倒角距离 C" : "圆角半径 R")
                    .font(.system(size: 12))
                Spacer()
                TextField("0", value: featureDraftBinding.depth, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                    .textFieldStyle(.roundedBorder)
                Text("mm").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(draft.kind == .edgeChamfer ? "倒角方式：等距离" : "连续性：G1，等半径")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func supportsCoordinates(_ kind: True3DFeatureKind) -> Bool {
        switch kind {
        case .hole, .boss, .rectBoss, .coneBoss, .loftBoss, .circularPocket, .rectPocket, .slot, .profileBoss, .profileCut, .revolveBoss, .revolveCut:
            return true
        default:
            return false
        }
    }

    private func coordinateEditor(_ f: Binding<True3DFeatureSpec>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("位置坐标")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            numRow("位置 X", f.x)
            numRow("位置 Y", f.y)
            numRow("位置 Z", Binding(
                get: { f.wrappedValue.topZ ?? params.height },
                set: { f.wrappedValue.topZ = $0 }
            ))
            if f.wrappedValue.topZ != nil {
                Button("恢复默认顶面 Z") { f.wrappedValue.topZ = nil }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85))
            }
        }
    }

    private var digit3DFilletCard: some View {
        VStack(spacing: 6) {
            filletCardRow("类型") {
                Menu {
                    Button("圆角") {
                        edgeFeatureIsChamfer = false
                        filletRadius = 2
                        clearFilletPreview(restoreScene: true)
                    }
                    Button("倒角") {
                        edgeFeatureIsChamfer = true
                        filletRadius = 1
                        clearFilletPreview(restoreScene: true)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: edgeFeatureIsChamfer ? "square.dashed" : "line.diagonal")
                        Text(edgeFeatureIsChamfer ? "倒角" : "圆角")
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85))
                }
            }
            filletCardRow("连续性") {
                Text(edgeFeatureIsChamfer ? "—" : "G1")
                    .foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85))
            }
            filletCardRow("方法") {
                Text(edgeFeatureIsChamfer ? "等距离" : "等半径")
                    .foregroundStyle(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85))
            }
            HStack(spacing: 8) {
                Text(edgeFeatureIsChamfer ? "距离" : "半径")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { filletRadius = max(0.2, filletRadius - 0.5) } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                        .background(SwiftUI.Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                Text(String(format: "%.1f mm", filletRadius))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 60)
                Button { filletRadius = min(200, filletRadius + 0.5) } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .background(SwiftUI.Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(SwiftUI.Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("曲线规则：\(edgeFilterLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                Button {
                    clearEdgeSelection()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 34, height: 34)
                        .background(SwiftUI.Color.black.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    filletRadius = edgeFeatureIsChamfer ? 1 : 2
                    clearFilletPreview(restoreScene: true)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 34, height: 34)
                        .background(SwiftUI.Color.black.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    previewFillet()
                } label: {
                    Image(systemName: "eye")
                        .frame(width: 34, height: 34)
                        .background(SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85).opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isPreviewingFillet || isBuilding || importBusy || isDirty)

                Button {
                    commitFillet()
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 38, height: 38)
                        .background(
                            (filletPreview == nil ? SwiftUI.Color.black.opacity(0.08) : SwiftUI.Color(red: 0.12, green: 0.42, blue: 0.85)),
                            in: Circle()
                        )
                        .foregroundStyle(filletPreview == nil ? SwiftUI.Color.secondary : SwiftUI.Color.white)
                }
                .buttonStyle(.plain)
                .disabled(
                    filletPreview == nil
                    || (filletPreviewRadius ?? -1) != filletRadius
                    || isPreviewingFillet
                    || isBuilding
                    || importBusy
                    || isDirty
                )

                if isPreviewingFillet { ProgressView().scaleEffect(0.7) }
            }
            .padding(.top, 2)
        }
        .padding(9)
        .frame(width: 264)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SwiftUI.Color.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: SwiftUI.Color.black.opacity(0.07), radius: 12, y: 4)
    }

    @ViewBuilder
    private func filletCardRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            content()
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(SwiftUI.Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var toolboxItems: [(title: String, kind: True3DFeatureKind)] {
        [
            ("孔", .hole),
            ("凸台", .boss),
            ("矩形凸台", .rectBoss),
            ("锥形凸台", .coneBoss),
            ("放样凸台", .loftBoss),
            ("螺旋扫掠", .sweepBoss),
            ("拔模", .draft),
            ("全边圆角", .edgeFillet),
            ("全边倒角", .edgeChamfer),
            ("抽壳", .shell),
            ("旋转凸台", .revolveBoss),
            ("旋转切除", .revolveCut),
            ("圆腔", .circularPocket),
            ("方腔", .rectPocket),
            ("腰形槽", .slot)
        ]
    }

    private var digit3DTreePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("建模树")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showTreePanel = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(SwiftUI.Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.4)

            ScrollView {
                if let result {
                    featureTree(result)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                } else {
                    Text("模型尚未构建")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
            }
        }
        .frame(width: min(330, UIScreen.main.bounds.width * 0.80))
        .frame(maxHeight: 500)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SwiftUI.Color.white.opacity(0.5), lineWidth: 0.5))
    }

    private var digit3DToolbox: some View {
        VStack(spacing: 10) {
            HStack {
                Text("工具箱")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showToolbox = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(SwiftUI.Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(toolboxItems.enumerated()), id: \.offset) { _, item in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showToolbox = false }
                        if item.kind == .edgeFillet || item.kind == .edgeChamfer {
                            openEdgeDrawer(chamfer: item.kind == .edgeChamfer)
                        } else {
                            openFeatureDrawer(item.kind)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: icon(for: item.kind))
                                .font(.system(size: 14))
                                .frame(width: 22)
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary.opacity(0.78))
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .background(SwiftUI.Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: min(310, UIScreen.main.bounds.width * 0.78))
        .frame(maxHeight: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SwiftUI.Color.white.opacity(0.5), lineWidth: 0.5))
    }

    private var toolboxNames: [String] {
        ["拔模", "拆分体", "修剪体", "加厚", "缩放体", "管", "包容体", "螺纹",
         "刻字", "删除体", "优化体", "孔", "基本体", "随机着色", "抽取面", "去除参数",
         "齿轮", "弹簧", "螺栓螺钉", "螺母", "垫圈", "型材"]
    }

    private func itemIcon(_ title: String) -> String {
        switch title {
        case "拔模": return "arrow.up.right"
        case "拆分体": return "square.split.2x1"
        case "修剪体": return "scissors"
        case "加厚": return "square.stack.3d.up"
        case "缩放体": return "arrow.up.left.and.arrow.down.right"
        case "管": return "circle.dashed"
        case "包容体": return "cube"
        case "螺纹": return "scribble"
        case "刻字": return "character.cursor.ibeam"
        case "删除体": return "trash"
        case "优化体": return "sparkles"
        case "孔": return "circle"
        case "基本体": return "cube"
        case "随机着色": return "paintpalette"
        case "抽取面": return "square.on.square"
        case "去除参数": return "function"
        case "齿轮": return "gearshape"
        case "弹簧": return "waveform.path"
        case "螺栓螺钉": return "bolt"
        case "螺母": return "hexagon"
        case "垫圈": return "circle.circle"
        default: return "square.grid.2x2"
        }
    }

    private var modelingStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let importedPart {
                    importedPartBanner(importedPart)
                }
                if importBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(importMode == .step ? "正在导入 STEP…" : "正在读取文件…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if let editingID = assemblyEditingID,
                   let component = assemblyComponents.first(where: { $0.id == editingID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.50))
                        Text("正在编辑装配零件：\(component.name)")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button("保存回装配") { saveAssemblyPart() }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.10, green: 0.55, blue: 0.50))
                        Button("取消") {
                            assemblyEditingID = nil
                            stage = .assembly
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                    }
                    .padding(9)
                    .background(Color(red: 0.10, green: 0.55, blue: 0.50).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                modelToolBar
                    .disabled(importedPart != nil)
                    .opacity(importedPart == nil ? 1 : 0.45)

                True3DSceneView(scene: scene, showWire: showWire, onPickEdge: { view, point, size in
                    pickEdge(in: view, at: point, viewSize: size)
                })
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )

                statusArea
                if importedPart == nil, !params.features.isEmpty {
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
                    featureTree(result)
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
                if let importedPart {
                    importedPartDrawer(importedPart)
                } else {
                    edgeSelectionSection
                    parametersArea
                    featureListArea
                    patternArea
                }
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

    @ViewBuilder
    private var edgeSelectionSection: some View {
        if let edge = selectedEdge {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("已选中一条边", systemImage: "line.diagonal")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("清除") { clearEdgeSelection() }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
                Text("边 #\(edge.edgeIndex) · 长 \(String(format: "%.1f", edge.length)) mm · 相邻面 \(edge.adjacentFaceIndices.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                numRow("圆角 R", $filletRadius)
                HStack(spacing: 8) {
                    Button {
                        previewFillet()
                    } label: {
                        Label(isPreviewingFillet ? "预览中…" : "预览圆角", systemImage: "eye")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                    .disabled(isPreviewingFillet || isBuilding || importBusy || isDirty)

                    Button {
                        commitFillet()
                    } label: {
                        Label("确认圆角", systemImage: "checkmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        filletPreview == nil
                            || (filletPreviewRadius ?? -1) != filletRadius
                            || isPreviewingFillet
                            || isBuilding
                            || importBusy
                            || isDirty
                    )
                }
                if let filletPreview {
                    Text("预览 R\(String(format: "%.2f", filletPreviewRadius ?? filletRadius)) · \(filletPreview.stats.faces) 面")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.05))
                }
                Text("先预览，确认后才写入操作历史并重建。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: filletRadius) { _ in
                if filletPreview != nil || isPreviewingFillet {
                    clearFilletPreview(restoreScene: true)
                }
            }
        } else if result != nil {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                    .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.05))
                Text("轻点模型边线，选中一条边")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func importedPartBanner(_ part: True3DImportedPart) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.50))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("STEP 零件")
                        .font(.system(size: 13, weight: .bold))
                    Text(part.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(part.stats.faces) 面 · \(part.stats.edges) 边 · \(String(format: "%.1f×%.1f×%.1f", part.stats.sizeX, part.stats.sizeY, part.stats.sizeZ)) mm")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 5) {
                Button("重新导入") {
                    importMode = .step
                    showImporter = true
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.bordered)
                Button("退出 STEP") { exitImportedPart() }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
            }
            .disabled(importBusy || isBuilding)
        }
        .padding(11)
        .background(Color(red: 0.10, green: 0.55, blue: 0.50).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func importedPartDrawer(_ part: True3DImportedPart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            edgeSelectionSection
            sectionTitle("STEP 模型源")
            Text(part.name)
                .font(.system(size: 13, weight: .semibold))
            Text("只读 B-Rep · \(part.stats.faces) 面 / \(part.stats.edges) 边")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let localURL = part.localURL {
                Text(localURL.lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("参数化基础体、孔/凸台/型腔命令在 STEP 模型下会禁用。R1 下一刀接边选择与圆角预览。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("重新导入 STEP") {
                    importMode = .step
                    showImporter = true
                    showModelDrawer = false
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.10, green: 0.55, blue: 0.50))
                Button("退出 STEP") {
                    showModelDrawer = false
                    exitImportedPart()
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }
            .disabled(importBusy || isBuilding)
        }
    }

    private var assemblyStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("装配")
                        .font(.system(size: 22, weight: .bold))
                    Text("多零件")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.10, green: 0.55, blue: 0.50).opacity(0.12))
                        .foregroundStyle(Color(red: 0.08, green: 0.42, blue: 0.38))
                        .clipShape(Capsule())
                    Spacer()
                }

                if assemblyComponents.isEmpty {
                    Text("先在“建模”页生成实体，或添加一个零件快照，再回装配。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("回到建模页") { stage = .model }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                } else {
                    if let assemblyError {
                        Label(assemblyError, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    True3DSceneView(scene: assemblyScene, showWire: showWire)
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    Text("零件位姿（基础块坐标，mm）")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 6) {
                        assemblyField("X", value: $assemblyX)
                        assemblyField("Y", value: $assemblyY)
                        assemblyField("Z", value: $assemblyZ)
                        assemblyField("Rz°", value: $assemblyRotation)
                    }
                    HStack(spacing: 8) {
                        Button {
                            addAssemblyPart(from: params)
                        } label: {
                            Label("添加当前零件快照", systemImage: "plus.square.on.square")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
                        .disabled(importedPart != nil)

                        Button {
                            addBlankAssemblyPart()
                        } label: {
                            Label("新建空白零件", systemImage: "doc.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    ForEach($assemblyComponents) { $component in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(uiColor: assemblyColor(component.colorIndex)))
                                    .frame(width: 8, height: 8)
                                TextField("名称", text: $component.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(component.summary)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("编辑") { editAssemblyPart(component) }
                                    .font(.system(size: 10, weight: .semibold))
                                    .buttonStyle(.bordered)
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

    private func assemblyColor(_ index: Int) -> UIColor {
        let palette: [UIColor] = [
            UIColor(red: 0.46, green: 0.58, blue: 0.70, alpha: 1),
            UIColor(red: 0.78, green: 0.52, blue: 0.30, alpha: 1),
            UIColor(red: 0.34, green: 0.62, blue: 0.48, alpha: 1),
            UIColor(red: 0.68, green: 0.45, blue: 0.62, alpha: 1),
            UIColor(red: 0.70, green: 0.65, blue: 0.34, alpha: 1)
        ]
        return palette[abs(index) % palette.count]
    }

    private func addAssemblyPart(from part: True3DParams) {
        let name = "零件 \(assemblyComponents.count + 1)"
        assemblyComponents.append(True3DAssemblyComponent(
            name: name, x: assemblyX, y: assemblyY,
            z: assemblyZ, rotationZ: assemblyRotation,
            colorIndex: assemblyComponents.count, part: part
        ))
        rebuildAssemblyScene()
    }

    private func addBlankAssemblyPart() {
        var blank = True3DParams()
        blank.projectName = "零件 \(assemblyComponents.count + 1)"
        blank.features = []
        addAssemblyPart(from: blank)
    }

    private func editAssemblyPart(_ component: True3DAssemblyComponent) {
        params = component.part
        importedPart = nil
        modelOperations = []
        modelDocumentID = UUID()
        selectedFeatureID = nil
        assemblyEditingID = component.id
        stage = .model
        rebuild()
    }

    private func saveAssemblyPart() {
        guard let id = assemblyEditingID,
              let index = assemblyComponents.firstIndex(where: { $0.id == id }) else {
            assemblyEditingID = nil
            return
        }
        assemblyComponents[index].part = params
        if !params.projectName.isEmpty {
            assemblyComponents[index].name = params.projectName
        }
        assemblyEditingID = nil
        rebuildAssemblyScene()
        stage = .assembly
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
        assemblyBuildTask?.cancel()
        assemblyGeneration += 1
        let generation = assemblyGeneration
        let components = assemblyComponents

        guard !components.isEmpty else {
            assemblyScene = SCNScene()
            assemblyError = nil
            return
        }

        assemblyError = nil
        assemblyBuildTask = Task { @MainActor in
            var builtParts: [(True3DAssemblyComponent, True3DResult)] = []
            var failure: String?

            for comp in components {
                do {
                    let result = try await self.kernelService.build(
                        True3DModelDocument(params: comp.part)
                    )
                    guard !Task.isCancelled, generation == self.assemblyGeneration else { return }
                    builtParts.append((comp, result))
                } catch is CancellationError {
                    return
                } catch {
                    failure = "\(comp.name) 生成失败：\(error.localizedDescription)"
                }
            }

            guard !Task.isCancelled, generation == self.assemblyGeneration else { return }
            self.assemblyScene = self.makeAssemblyScene(parts: builtParts)
            self.assemblyError = failure
        }
    }

    private func makeAssemblyScene(
        parts: [(True3DAssemblyComponent, True3DResult)]
    ) -> SCNScene {
        let newScene = SCNScene()
        newScene.background.contents = renderDark
            ? UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            : UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        let root = SCNNode()
        root.eulerAngles.x = -Float.pi / 2
        newScene.rootNode.addChildNode(root)
        var maxSize: Double = 20
        var maxHeight: Double = 0

        for (comp, partResult) in parts {
            let holder = SCNNode()
            holder.position = SCNVector3(Float(comp.x), Float(comp.y), Float(comp.z))
            holder.eulerAngles.z = Float(comp.rotationZ * .pi / 180)
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = assemblyColor(comp.colorIndex)
            material.metalness.contents = 0.18
            material.roughness.contents = 0.48
            let geometry = partResult.mesh.sceneKitGeometry()
            geometry.materials = [material]
            holder.addChildNode(SCNNode(geometry: geometry))
            let wireMaterial = SCNMaterial()
            wireMaterial.lightingModel = .constant
            wireMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.15, blue: 0.20, alpha: 0.72)
            wireMaterial.fillMode = .lines
            wireMaterial.isDoubleSided = true
            let wire = partResult.mesh.sceneKitGeometry()
            wire.materials = [wireMaterial]
            let wireNode = SCNNode(geometry: wire)
            wireNode.name = "wireOverlay"
            wireNode.scale = SCNVector3(1.002, 1.002, 1.002)
            wireNode.isHidden = !showWire
            holder.addChildNode(wireNode)
            root.addChildNode(holder)
            let bossMax = comp.part.bossFeatures.map(\.bossHeight).max() ?? 0
            maxSize = max(maxSize, comp.part.width, comp.part.depth, comp.part.height + bossMax)
            maxHeight = max(maxHeight, comp.part.height)
        }

        let maxSizeFinal = maxSize
        let camera = SCNNode()
        camera.name = "workbenchCamera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 10000
        camera.position = SCNVector3(Float(maxSizeFinal * 1.55), Float(maxSizeFinal * 1.35), Float(maxSizeFinal * 1.55))
        let target = SCNNode()
        target.position = SCNVector3(0, Float(maxHeight / 2), 0)
        newScene.rootNode.addChildNode(target)
        camera.constraints = [SCNLookAtConstraint(target: target)]
        newScene.rootNode.addChildNode(camera)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 1100
        light.light?.temperature = 6500
        light.position = SCNVector3(Float(maxSizeFinal * 1.2), Float(maxSizeFinal * 1.8), Float(maxSizeFinal * 1.2))
        newScene.rootNode.addChildNode(light)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 350
        fill.light?.color = UIColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1)
        newScene.rootNode.addChildNode(fill)
        addAxisGizmo(to: root, size: maxSizeFinal)
        return newScene
    }

    private func addAxisGizmo(to parent: SCNNode, size: Double) {
        let length = Float(min(max(size * 0.36, 12), 42))
        let group = SCNNode()
        group.name = "axisGizmo"
        group.position = SCNVector3(-Float(size * 0.60), -Float(size * 0.60), 0)

        func shaft(_ color: UIColor, _ position: SCNVector3, _ euler: SCNVector3) {
            let box = SCNBox(width: CGFloat(length), height: 0.5, length: 0.5, chamferRadius: 0)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.position = position
            node.eulerAngles = euler
            group.addChildNode(node)
        }

        func head(_ color: UIColor, _ position: SCNVector3, _ euler: SCNVector3) {
            let cone = SCNCone(topRadius: 0, bottomRadius: 1.8, height: 5)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            cone.materials = [material]
            let node = SCNNode(geometry: cone)
            node.position = position
            node.eulerAngles = euler
            group.addChildNode(node)
        }

        func label(_ text: String, _ color: UIColor, _ position: SCNVector3) {
            let side: CGFloat = 64
            let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
                UIColor.clear.setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 52, weight: .heavy),
                    .foregroundColor: color
                ]
                let string = text as NSString
                let textSize = string.size(withAttributes: attributes)
                string.draw(
                    at: CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2),
                    withAttributes: attributes
                )
            }
            let plane = SCNPlane(width: 7, height: 7)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.transparencyMode = .aOne
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.position = position
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            node.constraints = [billboard]
            group.addChildNode(node)
        }

        let xColor = UIColor.systemRed
        let yColor = UIColor.systemGreen
        let zColor = UIColor.systemBlue

        shaft(xColor, SCNVector3(length / 2, 0, 0), SCNVector3(0, 0, 0))
        head(xColor, SCNVector3(length, 0, 0), SCNVector3(0, 0, -Float.pi / 2))
        label("X", xColor, SCNVector3(length + 5, -1, 0))

        shaft(yColor, SCNVector3(0, length / 2, 0), SCNVector3(0, 0, Float.pi / 2))
        head(yColor, SCNVector3(0, length, 0), SCNVector3(0, 0, 0))
        label("Y", yColor, SCNVector3(-1, length + 5, 0))

        shaft(zColor, SCNVector3(0, 0, length / 2), SCNVector3(Float.pi / 2, 0, 0))
        head(zColor, SCNVector3(0, 0, length), SCNVector3(Float.pi / 2, 0, 0))
        label("Z", zColor, SCNVector3(-1, -1, length + 5))

        parent.addChildNode(group)
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
                    modelTool("导入 STEP", "cube.transparent") {
                        importMode = .step
                        showImporter = true
                    }
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
                    Label(importedPart == nil
                          ? "参数已修改，当前显示仍是上次生成的实体；请点“生成实体”更新"
                          : "操作历史已修改，当前显示仍是上次结果；请点“重新构建 STEP”更新",
                          systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if filletPreview != nil {
                    HStack(spacing: 8) {
                        Label("圆角预览 R\(String(format: "%.2f", filletPreviewRadius ?? filletRadius))", systemImage: "eye")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.05))
                        Spacer()
                        Button("取消预览") { clearFilletPreview(restoreScene: true) }
                            .font(.system(size: 11))
                            .buttonStyle(.borderless)
                    }
                }
                if let selectedEdge {
                    HStack(spacing: 8) {
                        Label("已选边 · \(String(format: "%.1f", selectedEdge.length)) mm", systemImage: "line.diagonal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.05))
                        Spacer()
                        Button("设参数") { showModelDrawer = true }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.borderless)
                        Button("清除") { clearEdgeSelection() }
                            .font(.system(size: 11))
                            .buttonStyle(.borderless)
                    }
                } else {
                    Label("轻点模型边线，选中一条边", systemImage: "hand.tap")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else {
            HStack(spacing: 8) {
                if isBuilding || importBusy { ProgressView() }
                Text(importBusy ? (importMode == .step ? "正在导入 STEP…" : "正在识别轮廓…") : message)
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
                Label(isBuilding ? "生成中…" : (importedPart == nil ? "生成实体" : "重新构建 STEP"), systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 1.0, green: 0.42, blue: 0.10))
            .disabled(isBuilding || importBusy)

            Button {
                params = True3DParams()
                importedPart = nil
                modelOperations = []
                modelDocumentID = UUID()
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

    private func featureTree(_ result: True3DResult) -> some View {
        let nodes = result.nodes.isEmpty ? fallbackNodes(from: result.features) : result.nodes
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("建模树")
                Spacer()
                if let selectedFeatureID {
                    Button("清除选择") { self.selectedFeatureID = nil }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    featureTreeRow(node, index: index)
                    if index < nodes.count - 1 { Divider().padding(.leading, 24) }
                }
            }
            .padding(.horizontal, 6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func featureTreeRow(_ node: True3DTreeNode, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: treeIcon(for: node.status))
                .foregroundStyle(treeColor(for: node.status))
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.system(size: 13, weight: .semibold))
                Text(node.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(index + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            featureTreeMenu(node)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            selectedFeatureID == node.id
                ? SwiftUI.Color(red: 1.0, green: 0.42, blue: 0.10).opacity(0.12)
                : SwiftUI.Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFeatureID = selectedFeatureID == node.id ? nil : node.id
        }
    }

    @ViewBuilder
    private func featureTreeMenu(_ node: True3DTreeNode) -> some View {
        if let operationID = node.operationID {
            Menu {
                Button {
                    toggleOperationSuppression(operationID)
                } label: {
                    Label(
                        node.suppressed ? "恢复" : "抑制",
                        systemImage: node.suppressed ? "arrow.uturn.forward" : "minus.circle"
                    )
                }
                Button("删除", role: .destructive) {
                    deleteOperation(operationID)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleOperationSuppression(_ operationID: UUID) {
        guard let index = modelOperations.firstIndex(where: { $0.id == operationID }) else { return }
        modelOperations[index].suppressed.toggle()
        selectedFeatureID = nil
        rebuild()
    }

    private func deleteOperation(_ operationID: UUID) {
        modelOperations.removeAll { $0.id == operationID }
        if selectedFeatureID != nil {
            selectedFeatureID = nil
        }
        clearEdgeSelection()
        rebuild()
    }

    private func fallbackNodes(from features: [True3DFeature]) -> [True3DTreeNode] {
        features.enumerated().map { index, feature in
            True3DTreeNode(
                id: feature.id,
                kind: index == 0 ? .root : .feature,
                name: feature.name,
                detail: feature.detail,
                suppressed: false,
                status: feature.ok ? .ok : .failed(feature.detail),
                operationID: nil
            )
        }
    }

    private func treeIcon(for status: True3DTreeNode.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .suppressed: return "minus.circle"
        }
    }

    private func treeColor(for status: True3DTreeNode.Status) -> SwiftUI.Color {
        switch status {
        case .ok: return .green
        case .failed: return .orange
        case .suppressed: return SwiftUI.Color.secondary
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
    private func featureEditor(_ f: Binding<True3DFeatureSpec>, showPosition: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("特征名称", text: f.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            switch f.wrappedValue.kind {
            case .hole:
                numRow("直径 Ø", f.dia)
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
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
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
            case .rectBoss:
                numRow("X 长", f.width)
                numRow("Y 宽", f.depthY)
                numRow("高度 H", f.bossHeight)
                numRow("圆角 R", f.cornerRadius)
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
            case .coneBoss:
                numRow("底直径", f.dia)
                numRow("顶直径", f.topDia)
                numRow("高度 H", f.bossHeight)
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
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
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
            case .sweepBoss:
                Picker("路径", selection: f.sweepPathKind) {
                    ForEach(True3DSweepPath.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .font(.system(size: 12))
                numRow("截面 Ø", f.dia)
                if f.wrappedValue.sweepPathKind != .line {
                    numRow("路径 R", f.sweepPathRadius)
                }
                if f.wrappedValue.sweepPathKind == .helix {
                    numRow("螺距", f.sweepPitch)
                    numRow("圈数", f.sweepTurns)
                }
                if f.wrappedValue.sweepPathKind == .line {
                    numRow("路径长度", f.sweepLength)
                }
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
                Picker("倒角方式", selection: f.chamferMode) {
                    ForEach(True3DChamferMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .font(.system(size: 12))
                numRow("倒角 C", f.depth)
                if f.wrappedValue.chamferMode == .twoDistance {
                    numRow("第二距离", f.chamferSecondDistance)
                }
                if f.wrappedValue.chamferMode == .distanceAngle {
                    numRow("角度°", f.chamferAngle)
                }
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
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
            case .rectPocket:
                numRow("X 长", f.width)
                numRow("Y 宽", f.depthY)
                numRow("深度", f.depth)
                numRow("圆角 R", f.cornerRadius)
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
            case .slot:
                numRow("总长", f.width)
                numRow("槽宽", f.depthY)
                numRow("深度", f.depth)
                if showPosition {
                    numRow("中心 X", f.x)
                    numRow("中心 Y", f.y)
                }
            case .profileBoss:
                Text("草图轮廓：\(f.wrappedValue.profile.count) 个点")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                numRow("拉伸高度", f.bossHeight)
            case .profileCut:
                Text("草图轮廓：\(f.wrappedValue.profile.count) 个点")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                numRow("切除深度", f.depth)
            }
            if showPosition { topZEditor(f) }
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

    private func runRailFeature(_ kind: True3DFeatureKind) {
        openFeatureDrawer(kind)
    }

    private func makeDraftFeature(_ kind: True3DFeatureKind) -> True3DFeatureSpec {
        var f = True3DFeatureSpec(kind: kind)
        switch kind {
        case .hole:
            f.name = "新孔"; f.x = -params.width * 0.25; f.y = 0; f.dia = 10
        case .boss:
            f.name = "新凸台"; f.x = params.width * 0.25; f.y = 0; f.dia = 20; f.bossHeight = 6
        case .rectBoss:
            f.name = "新矩形凸台"; f.x = params.width * 0.25; f.y = 0
            f.width = min(30, params.width * 0.5); f.depthY = min(20, params.depth * 0.5)
            f.bossHeight = 6
        case .coneBoss:
            f.name = "锥形凸台"; f.x = params.width * 0.25; f.y = 0
            f.dia = 24; f.topDia = 12; f.bossHeight = 8
        case .loftBoss:
            f.name = "放样凸台"; f.x = 0; f.y = 0; f.bossHeight = 10
        case .sweepBoss:
            f.name = "扫掠凸台"; f.x = 0; f.y = 0
            f.dia = 8; f.sweepPathKind = .helix
            f.sweepPathRadius = 25; f.sweepPitch = 12; f.sweepTurns = 2; f.sweepLength = 60
        case .revolveBoss:
            f = True3DFeatureSpec(kind: .revolveBoss)
            f.name = "旋转凸台"
        case .revolveCut:
            f = True3DFeatureSpec(kind: .revolveCut)
            f.name = "旋转切除"
        case .circularPocket:
            f.name = "新圆腔"; f.x = -params.width * 0.25; f.y = 0; f.dia = 20; f.depth = 5
        case .rectPocket:
            f.name = "新方腔"; f.x = params.width * 0.25; f.y = 0; f.width = 24; f.depthY = 18; f.depth = 5
        case .slot:
            f.name = "新腰形槽"; f.x = 0; f.y = -params.depth * 0.25; f.width = 40; f.depthY = 12; f.depth = 5
        case .edgeFillet:
            f.name = "边圆角"; f.depth = max(filletRadius, 0.2)
        case .edgeChamfer:
            f.name = "边倒角"; f.depth = max(filletRadius, 0.2)
        case .draft:
            f.name = "拔模"; f.angle = 3
        case .shell:
            f.name = "抽壳"; f.depth = min(2, min(params.width, params.depth, params.height) / 4)
        case .profileBoss:
            f.name = "草图凸台"; f.bossHeight = 5
        case .profileCut:
            f.name = "草图切除"; f.depth = 5
        }
        return f
    }

    private func openFeatureDrawer(_ kind: True3DFeatureKind) {
        guard importedPart == nil else {
            error = "STEP 模型只能做边圆角/倒角；请先退出 STEP 再用参数化特征"
            return
        }
        pickMode = .edge
        pendingFaceExtrude = false
        draftFeature = makeDraftFeature(kind)
        showFeatureDrawer = true
        error = nil
        notice = nil
    }

    private func beginFaceExtrude() {
        guard importedPart == nil else {
            error = "STEP 模型暂不支持面拉伸"
            return
        }
        closeFeatureDrawer()
        pickMode = .face
        pendingFaceExtrude = true
        selectedFace = nil
        scene.rootNode.childNode(withName: "selectedFace", recursively: true)?.removeFromParentNode()
        notice = "拉伸：先选择一个朝上的平面"
    }

    private func openEdgeDrawer(chamfer: Bool) {
        guard importedPart == nil else {
            error = "STEP 模型请使用边的圆角/倒角"
            return
        }
        var f = True3DFeatureSpec(kind: chamfer ? .edgeChamfer : .edgeFillet)
        f.name = chamfer ? "边倒角" : "边圆角"
        f.depth = max(filletRadius, 0.2)
        draftFeature = f
        pickMode = .edge
        pendingFaceExtrude = false
        showFeatureDrawer = true
        error = nil
        notice = nil
    }

    private func closeFeatureDrawer() {
        showFeatureDrawer = false
        draftFeature = nil
        pendingFaceExtrude = false
    }

    private var featureDraftBinding: Binding<True3DFeatureSpec> {
        Binding(
            get: { draftFeature ?? True3DFeatureSpec() },
            set: { draftFeature = $0 }
        )
    }

    private var featureDrawerTitle: String {
        guard let draft = draftFeature else { return "参数" }
        switch draft.kind {
        case .rectBoss where draft.name == "拉伸凸台": return "拉伸参数"
        case .edgeFillet: return "圆角参数"
        case .edgeChamfer: return "倒角参数"
        default: return draft.name.isEmpty ? draft.kind.rawValue : draft.name
        }
    }

    private func commitFeatureDrawer() {
        guard var draft = draftFeature else { return }
        if draft.kind == .edgeFillet || draft.kind == .edgeChamfer {
            guard let edge = selectedEdge else {
                error = "请先在三维模型上选择一条边"
                return
            }
            if draft.kind == .edgeFillet {
                modelOperations.append(True3DHistoryOperation(kind: .fillet(edge: edge, radius: max(draft.depth, 0.1))))
            } else {
                modelOperations.append(True3DHistoryOperation(kind: .chamfer(edge: edge, distance: max(draft.depth, 0.1))))
            }
            selectedEdge = nil
            scene.rootNode.childNode(withName: "selectedEdge", recursively: true)?.removeFromParentNode()
            closeFeatureDrawer()
            notice = draft.kind == .edgeFillet ? "已添加边圆角" : "已添加边倒角"
            rebuild()
            return
        }
        if draft.kind == .revolveBoss {
            draft.bossHeight = max(draft.bossHeight, 0.1)
        }
        draft.name = draft.name.isEmpty ? draft.kind.rawValue : draft.name
        selectedFace = nil
        scene.rootNode.childNode(withName: "selectedFace", recursively: true)?.removeFromParentNode()
        params.features.append(draft)
        selectedFeatureID = draft.id
        pendingFeatureID = draft.id
        closeFeatureDrawer()
        notice = "已添加 \(draft.name)，正在重建"
        rebuild()
    }

    private func addFeature(_ kind: True3DFeatureKind) {
        error = nil
        notice = nil
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
            f.name = "扫掠凸台"; f.x = 0; f.y = 0
            f.dia = 8; f.sweepPathKind = .helix
            f.sweepPathRadius = 25; f.sweepPitch = 12; f.sweepTurns = 2; f.sweepLength = 60
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
        pendingFeatureID = f.id
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
            sketchProfile = points
            sketchClosed = points.count >= 3
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
            sketchProfile = feature.profile
            sketchClosed = feature.profile.count >= 3
            params.features.append(feature)
            selectedFeatureID = feature.id
            message = "已添加 \(feature.name)，正在重建实体"
        case .features(let features):
            if let largest = features.max(by: { profileArea($0.profile) < profileArea($1.profile) }) {
                sketchProfile = largest.profile
                sketchClosed = largest.profile.count >= 3
            }
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
        importedPart = nil
        modelOperations = []
        modelDocumentID = UUID()
        selectedFeatureID = nil
        sketchProfile = []
        sketchClosed = false
        sketchTool = .polyline
        sketchSavedProfiles = []
        notice = "已新建空白工程：可直接添加孔/凸台/型腔，或进入草图"
        stage = .model
        rebuild()
    }

    private func rebuild() {
        captureCameraOrbit()
        buildGeneration += 1
        let generation = buildGeneration
        buildTask?.cancel()
        clearFilletPreview(restoreScene: true)

        error = nil
        notice = nil
        camResult = nil
        gcodeURL = nil
        stepURL = nil
        stlURL = nil
        isBuilding = true
        message = "正在构建 OCCT 实体…"

        let document: True3DModelDocument
        if let importedPart {
            document = True3DModelDocument(
                id: modelDocumentID,
                imported: importedPart,
                operations: modelOperations
            )
        } else {
            document = True3DModelDocument(
                id: modelDocumentID,
                params: params,
                operations: modelOperations
            )
        }
        buildTask = Task { @MainActor in
            do {
                let newResult = try await self.kernelService.build(document)
                guard !Task.isCancelled, generation == self.buildGeneration else { return }
                self.result = newResult
                self.message = "构建完成"
                self.pendingFeatureID = nil
                self.selectedEdge = nil
                self.scene = self.makeScene(result: newResult)
                self.applyOrbit()
                if self.showDatumPlane { self.addDatumPlane(report: false) }
                self.isBuilding = false
            } catch is CancellationError {
                guard generation == self.buildGeneration else { return }
                self.isBuilding = false
                self.message = "构建已取消"
            } catch {
                guard generation == self.buildGeneration else { return }
                let failedFeature = self.pendingFeatureID
                if let failedFeature,
                   let index = self.params.features.firstIndex(where: { $0.id == failedFeature }) {
                    self.params.features.remove(at: index)
                    self.selectedFeatureID = nil
                    self.pendingFeatureID = nil
                    self.message = "特征未生效，已撤回"
                    self.error = "\(error.localizedDescription)（已撤销该特征）"
                } else {
                    self.message = "构建失败"
                    self.error = error.localizedDescription
                }
                self.isBuilding = false
            }
        }
    }

    private func previewFillet() {
        guard let edgeRef = selectedEdge,
              let result,
              !isDirty,
              !isBuilding,
              !importBusy else {
            return
        }
        guard filletRadius > 0 else {
            error = edgeFeatureIsChamfer ? "倒角距离必须大于 0" : "圆角半径必须大于 0"
            return
        }
        guard let edge = result.shape.edge(at: edgeRef.edgeIndex) else {
            error = "选中的边已经失效，请重新选边"
            return
        }

        captureCameraOrbit()
        clearFilletPreview(restoreScene: true)
        filletPreviewGeneration += 1
        let generation = filletPreviewGeneration
        filletPreviewTask?.cancel()
        isPreviewingFillet = true
        error = nil
        notice = nil
        let radius = filletRadius
        let shape = result.shape
        filletPreviewTask = Task { @MainActor in
            do {
                let preview: True3DPreview
                if self.edgeFeatureIsChamfer {
                    preview = try await self.kernelService.previewChamfer(
                        on: shape,
                        edge: edge,
                        distance: radius
                    )
                } else {
                    preview = try await self.kernelService.previewFillet(
                        on: shape,
                        edge: edge,
                        radius: radius
                    )
                }
                guard !Task.isCancelled, generation == self.filletPreviewGeneration else { return }
                self.captureCameraOrbit()
                self.filletPreview = preview
                self.filletPreviewRadius = radius
                self.scene = self.makePreviewScene(preview)
                self.applyOrbit()
                self.isPreviewingFillet = false
                self.message = self.edgeFeatureIsChamfer
                    ? "倒角预览 C\(String(format: "%.2f", radius))"
                    : "圆角预览 R\(String(format: "%.2f", radius))"
            } catch is CancellationError {
                guard generation == self.filletPreviewGeneration else { return }
                self.isPreviewingFillet = false
            } catch {
                guard generation == self.filletPreviewGeneration else { return }
                self.error = error.localizedDescription
                self.isPreviewingFillet = false
            }
        }
    }

    private func commitFillet() {
        guard let edge = selectedEdge,
              filletRadius > 0,
              filletPreview != nil,
              (filletPreviewRadius ?? -1) == filletRadius,
              !isDirty,
              !isPreviewingFillet,
              !isBuilding else {
            return
        }
        if edgeFeatureIsChamfer {
            modelOperations.append(
                True3DHistoryOperation(kind: .chamfer(edge: edge, distance: filletRadius))
            )
        } else {
            modelOperations.append(
                True3DHistoryOperation(kind: .fillet(edge: edge, radius: filletRadius))
            )
        }
        selectedEdge = nil
        selectedFeatureID = nil
        error = nil
        notice = nil
        clearFilletPreview(restoreScene: false)
        rebuild()
    }

    private func clearFilletPreview(restoreScene: Bool) {
        let hadPreview = filletPreview != nil || isPreviewingFillet
        filletPreviewGeneration += 1
        filletPreviewTask?.cancel()
        filletPreviewTask = nil
        filletPreview = nil
        filletPreviewRadius = nil
        isPreviewingFillet = false
        if restoreScene, hadPreview, let result {
            scene = makeScene(result: result)
            applyOrbit()
            if showDatumPlane { addDatumPlane(report: false) }
            if let selectedEdge,
               let edge = result.shape.edge(at: selectedEdge.edgeIndex),
               let modelRoot = scene.rootNode.childNode(withName: "modelRoot", recursively: false) {
                highlightSelectedEdge(modelRoot: modelRoot, edge: edge)
            }
        }
    }

    private func pickEdge(in view: SCNView, at point: CGPoint, viewSize: CGSize) {
        guard stage == .model,
              !isBuilding,
              !importBusy,
              !isDirty,
              filletPreview == nil,
              !isPreviewingFillet,
              let result else { return }
        guard let scene = view.scene,
              let modelRoot = scene.rootNode.childNode(withName: "modelRoot", recursively: false) else {
            return
        }

        let nearWorld = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
        let farWorld = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
        let nearLocal = modelRoot.convertPosition(nearWorld, from: nil)
        let farLocal = modelRoot.convertPosition(farWorld, from: nil)
        let delta = SIMD3<Double>(
            Double(farLocal.x - nearLocal.x),
            Double(farLocal.y - nearLocal.y),
            Double(farLocal.z - nearLocal.z)
        )
        let length = (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
        guard length > 1e-9 else { return }
        let origin = SIMD3<Double>(Double(nearLocal.x), Double(nearLocal.y), Double(nearLocal.z))
        let direction = SIMD3<Double>(delta.x / length, delta.y / length, delta.z / length)

        guard let hit = result.shape.raycastNearest(origin: origin, direction: direction) else {
            if pickMode == .face {
                selectedFace = nil
                scene.rootNode.childNode(withName: "selectedFace", recursively: true)?.removeFromParentNode()
                notice = "没点到实体；轻点模型表面再试"
            } else {
                clearEdgeSelection()
                notice = "没点到实体；轻点模型边线再试"
            }
            return
        }

        if pickMode == .face {
            selectFace(hit)
            return
        }

        let box = result.mesh.boundingBox
        let diagonal = Double(
            pow(Double(box.max.x - box.min.x), 2)
            + pow(Double(box.max.y - box.min.y), 2)
            + pow(Double(box.max.z - box.min.z), 2)
        ).squareRoot()
        let nearby3D = max(0.8, diagonal * 0.07)
        let hitPoint = hit.point

        var bestEdge: OCCTSwift.Edge?
        var bestDistance = Double.greatestFiniteMagnitude
        for edge in result.shape.edges() {
            let samples = edge.points(count: 24)
            let nearest3D = samples.map { sample -> Double in
                let dx = sample.x - hitPoint.x
                let dy = sample.y - hitPoint.y
                let dz = sample.z - hitPoint.z
                return (dx * dx + dy * dy + dz * dz).squareRoot()
            }.min() ?? .greatestFiniteMagnitude
            guard nearest3D <= nearby3D else { continue }
            for sample in samples {
                let world = modelRoot.convertPosition(
                    SCNVector3(Float(sample.x), Float(sample.y), Float(sample.z)),
                    to: nil
                )
                let projected = view.projectPoint(world)
                guard projected.z >= 0, projected.z <= 1 else { continue }
                let dx = Double(projected.x) - Double(point.x)
                let dy = Double(projected.y) - Double(point.y)
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < bestDistance {
                    bestDistance = distance
                    bestEdge = edge
                }
            }
        }

        let tolerance = max(16, min(30, Double(viewSize.width) * 0.045))
        guard let edge = bestEdge, bestDistance <= tolerance else {
            clearEdgeSelection()
            notice = "没点到边；靠近边线再试"
            return
        }

        let reference = True3DEdgeRef.make(edge: edge, in: result.shape)
        selectedEdge = reference
        selectedFace = nil
        scene.rootNode.childNode(withName: "selectedFace", recursively: true)?.removeFromParentNode()
        selectedFeatureID = nil
        error = nil
        notice = nil
        message = "已选中边 #\(reference.edgeIndex)，点圆角/倒角设置参数"
        highlightSelectedEdge(modelRoot: modelRoot, edge: edge)
    }

    private func selectFace(_ hit: OCCTSwift.RayHit) {
        guard let result else { return }
        let face = result.shape.face(at: hit.faceIndex)
        let bounds = face?.bounds
        let sizeX = bounds.map { $0.max.x - $0.min.x } ?? 20
        let sizeY = bounds.map { $0.max.y - $0.min.y } ?? 20
        selectedFace = True3DFaceSelection(
            faceIndex: hit.faceIndex,
            point: hit.point,
            normal: hit.normal,
            sizeX: max(sizeX, 1),
            sizeY: max(sizeY, 1)
        )

        scene.rootNode.childNode(withName: "selectedFace", recursively: true)?.removeFromParentNode()
        if let modelRoot = scene.rootNode.childNode(withName: "modelRoot", recursively: false) {
            let marker = SCNNode()
            marker.name = "selectedFace"
            marker.position = SCNVector3(Float(hit.point.x), Float(hit.point.y), Float(hit.point.z) + 0.15)
            if hit.normal.z > 0.5 {
                let plane = SCNPlane(width: CGFloat(min(sizeX * 0.94, 80)), height: CGFloat(min(sizeY * 0.94, 80)))
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = UIColor(red: 0.12, green: 0.46, blue: 0.95, alpha: 1)
                material.transparency = 0.22
                material.isDoubleSided = true
                material.writesToDepthBuffer = false
                plane.materials = [material]
                marker.geometry = plane
                marker.renderingOrder = 20
            } else {
                let sphere = SCNSphere(radius: 1.8)
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = UIColor(red: 0.12, green: 0.46, blue: 0.95, alpha: 1)
                sphere.materials = [material]
                marker.geometry = sphere
            }
            modelRoot.addChildNode(marker)
        }

        if pendingFaceExtrude {
            guard hit.normal.z > 0.5 else {
                error = "拉伸只支持朝上的平面；请重新选择顶面"
                return
            }
            var draft = True3DFeatureSpec(kind: .rectBoss)
            draft.name = "拉伸凸台"
            draft.x = hit.point.x
            draft.y = hit.point.y
            draft.topZ = hit.point.z
            draft.width = min(max(sizeX * 0.6, 8), 80)
            draft.depthY = min(max(sizeY * 0.6, 8), 80)
            draft.bossHeight = 5
            draftFeature = draft
            showFeatureDrawer = true
            pendingFaceExtrude = false
            pickMode = .face
            notice = "已选择面 #\(hit.faceIndex)，可设置拉伸尺寸与 XYZ"
        } else {
            notice = "已选择面 #\(hit.faceIndex) · Z \(fmt(hit.point.z))"
        }
    }

    private func highlightSelectedEdge(modelRoot: SCNNode, edge: OCCTSwift.Edge) {
        modelRoot.childNode(withName: "selectedEdge", recursively: false)?.removeFromParentNode()
        let points = edge.points(count: 64)
        guard points.count >= 2 else { return }

        let vertices = points.map {
            SCNVector3(Float($0.x), Float($0.y), Float($0.z))
        }
        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        indices.reserveCapacity((vertices.count - 1) * 2)
        for index in 0..<(vertices.count - 1) {
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 1.0, green: 0.32, blue: 0.05, alpha: 1)
        material.emission.contents = UIColor(red: 1.0, green: 0.32, blue: 0.05, alpha: 1)
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "selectedEdge"
        node.renderingOrder = 200
        modelRoot.addChildNode(node)
    }

    private func clearEdgeSelection() {
        clearFilletPreview(restoreScene: true)
        selectedEdge = nil
        notice = nil
        scene.rootNode.childNode(withName: "selectedEdge", recursively: true)?.removeFromParentNode()
    }

    private func toggleDatumPlane() {
        showDatumPlane.toggle()
        if showDatumPlane {
            addDatumPlane()
        } else {
            scene.rootNode.childNode(withName: "datumPlane", recursively: true)?.removeFromParentNode()
            notice = "基准面已隐藏"
        }
    }

    private func addDatumPlane(report: Bool = true) {
        guard let target = scene.rootNode.childNode(withName: "cameraTarget", recursively: true) else { return }
        scene.rootNode.childNode(withName: "datumPlane", recursively: true)?.removeFromParentNode()
        let stats = result?.stats
        let planeWidth = max(CGFloat(stats?.sizeX ?? params.width) * 1.7, 30)
        let planeDepth = max(CGFloat(stats?.sizeY ?? params.depth) * 1.7, 30)
        let plane = SCNPlane(width: planeWidth, height: planeDepth)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.20, green: 0.50, blue: 0.90, alpha: 1)
        material.transparency = 0.16
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.name = "datumPlane"
        node.position = target.position
        node.renderingOrder = -60
        scene.rootNode.addChildNode(node)
        if report { notice = "基准面已显示：XY 平面" }
    }

    private func announceMeasurement() {
        guard let result else { notice = "先生成实体，再测量"; return }
        let stats = result.stats
        notice = "测量：\(fmt(stats.sizeX)) × \(fmt(stats.sizeY)) × \(fmt(stats.sizeZ)) mm · 体积 \(fmt(stats.volume)) mm³"
    }

    private func announceAnalysis() {
        guard let result else { notice = "先生成实体，再分析"; return }
        let stats = result.stats
        notice = "分析：\(stats.faces) 面 / \(stats.edges) 边 / \(stats.triangles) 三角面 · \(stats.valid ? "实体有效" : "实体无效")"
    }

    private func toggleRenderMode() {
        renderDark.toggle()
        scene.background.contents = renderDark
            ? UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            : UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        notice = renderDark ? "渲染：深色背景已开启" : "渲染：浅色背景已恢复"
    }

    private func captureCameraOrbit() {
        guard let camera = scene.rootNode.childNode(withName: "workbenchCamera", recursively: true),
              let target = scene.rootNode.childNode(withName: "cameraTarget", recursively: true) else {
            return
        }
        let dx = camera.position.x - target.position.x
        let dy = camera.position.y - target.position.y
        let dz = camera.position.z - target.position.z
        let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
        guard distance > 0.01 else { return }
        orbitDistance = Double(distance)
        orbitYaw = Double(atan2(dx, dz)) * 180 / Double.pi
        orbitPitch = min(85, max(-85, Double(asin(min(1, max(-1, dy / distance)))) * 180 / Double.pi))
    }

    private func setViewOrientation(_ orientation: True3DViewOrientation) {
        viewOrientation = orientation
        switch orientation {
        case .iso:
            orbitYaw = 45
            orbitPitch = 29
        case .top:
            orbitYaw = 0
            orbitPitch = 89.5
        case .front:
            orbitYaw = 0
            orbitPitch = 0
        case .right:
            orbitYaw = 90
            orbitPitch = 0
        case .back:
            orbitYaw = 180
            orbitPitch = 0
        }
        applyOrbit(animated: true)
    }

    private func applyOrbit(animated: Bool = false) {
        guard let camera = scene.rootNode.childNode(withName: "workbenchCamera", recursively: true),
              let target = scene.rootNode.childNode(withName: "cameraTarget", recursively: true) else {
            return
        }
        let dx = camera.position.x - target.position.x
        let dy = camera.position.y - target.position.y
        let dz = camera.position.z - target.position.z
        let currentDistance = max((dx * dx + dy * dy + dz * dz).squareRoot(), 1)
        let distance = orbitDistance.map { Float($0) } ?? currentDistance
        let yaw = orbitYaw * Double.pi / 180
        let pitch = min(89.5, max(-89.5, orbitPitch)) * Double.pi / 180
        let direction = SCNVector3(
            Float(sin(yaw) * cos(pitch)),
            Float(sin(pitch)),
            Float(cos(yaw) * cos(pitch))
        )
        let length = max(
            (direction.x * direction.x + direction.y * direction.y + direction.z * direction.z).squareRoot(),
            0.001
        )
        let newPosition = SCNVector3(
            target.position.x + direction.x / length * distance,
            target.position.y + direction.y / length * distance,
            target.position.z + direction.z / length * distance
        )
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            camera.position = newPosition
            SCNTransaction.commit()
        } else {
            camera.position = newPosition
        }
    }

    private func makeScene(result: True3DResult) -> SCNScene {
        makeScene(
            mesh: result.mesh,
            stats: result.stats,
            shape: result.shape,
            materialColor: UIColor(red: 0.52, green: 0.54, blue: 0.57, alpha: 1),
            isPreview: false
        )
    }

    private func makePreviewScene(_ preview: True3DPreview) -> SCNScene {
        makeScene(
            mesh: preview.mesh,
            stats: preview.stats,
            shape: preview.shape,
            materialColor: UIColor(red: 0.20, green: 0.47, blue: 0.92, alpha: 1),
            isPreview: true
        )
    }

    private func brepLineGeometry(shape: OCCTSwift.Shape, samplesPerEdge: Int = 24) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for edge in shape.edges() {
            let points = edge.points(count: samplesPerEdge)
            guard points.count > 1 else { continue }
            let start = Int32(vertices.count)
            for point in points {
                vertices.append(SCNVector3(Float(point.x), Float(point.y), Float(point.z)))
            }
            for index in 0..<(points.count - 1) {
                indices.append(start + Int32(index))
                indices.append(start + Int32(index + 1))
            }
        }
        guard !vertices.isEmpty, !indices.isEmpty else {
            return SCNGeometry()
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        return SCNGeometry(sources: [source], elements: [element])
    }

    private func makeScene(
        mesh: Mesh,
        stats: True3DStats,
        shape: OCCTSwift.Shape,
        materialColor: UIColor,
        isPreview: Bool
    ) -> SCNScene {
        let newScene = SCNScene()
        newScene.background.contents = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        let modelRoot = SCNNode()
        modelRoot.name = "modelRoot"
        modelRoot.eulerAngles.x = -Float.pi / 2
        newScene.rootNode.addChildNode(modelRoot)
        let geometry = mesh.sceneKitGeometry()
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = materialColor
        material.metalness.contents = 0.08
        material.roughness.contents = 0.55
        geometry.materials = [material]
        let solidNode = SCNNode(geometry: geometry)
        solidNode.name = isPreview ? "previewSolid" : "solid"
        modelRoot.addChildNode(solidNode)
        let wireMaterial = SCNMaterial()
        wireMaterial.lightingModel = .constant
        wireMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.15, blue: 0.20, alpha: 0.72)
        wireMaterial.fillMode = .lines
        wireMaterial.isDoubleSided = true
        let wireGeometry = brepLineGeometry(shape: shape)
        wireGeometry.materials = [wireMaterial]
        let wireNode = SCNNode(geometry: wireGeometry)
        wireNode.name = "wireOverlay"
        wireNode.scale = SCNVector3(1.002, 1.002, 1.002)
        wireNode.isHidden = !showWire
        modelRoot.addChildNode(wireNode)
        let box = mesh.boundingBox
        let meshSizeX = Double(box.max.x - box.min.x)
        let meshSizeY = Double(box.max.y - box.min.y)
        let meshSizeZ = Double(box.max.z - box.min.z)
        let meshCenter = SCNVector3(
            (box.min.x + box.max.x) / 2,
            (box.min.y + box.max.y) / 2,
            (box.min.z + box.max.z) / 2
        )
        let maxSize = max(meshSizeX, meshSizeY, meshSizeZ, 1)
        let worldCenter = modelRoot.convertPosition(meshCenter, to: nil)
        let camera = SCNNode()
        camera.name = "workbenchCamera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.camera?.zNear = max(0.01, maxSize / 5000)
        camera.camera?.zFar = max(1000, maxSize * 40)
        let distance = maxSize * 2.15
        camera.position = SCNVector3(
            worldCenter.x + Float(distance * 0.78),
            worldCenter.y + Float(distance * 0.62),
            worldCenter.z + Float(distance * 0.78)
        )
        let target = SCNNode()
        target.name = "cameraTarget"
        target.position = worldCenter
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
        addAxisGizmo(to: modelRoot, size: maxSize)
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
        let stored: True3DStoredProject
        if let importedPart {
            guard let fileName = importedPart.localURL?.lastPathComponent else {
                self.error = "STEP 源文件没有复制到 App 容器，无法保存工程"
                return
            }
            stored = True3DStoredProject(
                id: modelDocumentID,
                name: importedPart.name,
                sourceKind: .importedStep,
                importedName: importedPart.name,
                importedFileName: fileName,
                importedUnitInMeters: importedPart.unitInMeters,
                importedAt: importedPart.importedAt,
                operations: modelOperations,
                selectedNodeID: selectedFeatureID
            )
        } else {
            stored = True3DStoredProject(
                id: modelDocumentID,
                name: params.projectName,
                sourceKind: .parametric,
                params: params,
                operations: modelOperations,
                selectedNodeID: selectedFeatureID
            )
        }

        do {
            try True3DProjectStore.saveDocument(stored)
            notice = "工程已保存到 Documents/MacroGen-3D-project.json"
        } catch {
            self.error = "保存工程失败：\(error.localizedDescription)"
        }
    }

    private func loadProject() {
        guard !importBusy else { return }
        error = nil
        do {
            let stored = try True3DProjectStore.loadDocument()
            applyStoredProject(stored)
        } catch {
            do {
                params = try True3DProjectStore.load()
                importedPart = nil
                modelOperations = []
                modelDocumentID = UUID()
                selectedFeatureID = nil
                stage = .model
                rebuild()
                notice = "已载入上次保存的 3D 工程"
            } catch {
                self.error = "载入工程失败：\(error.localizedDescription)"
            }
        }
    }

    private func applyStoredProject(_ stored: True3DStoredProject) {
        stage = .model
        if stored.sourceKind == .importedStep {
            guard let fileName = stored.importedFileName else {
                self.error = "工程缺少 STEP 文件名，无法载入"
                return
            }
            let url = True3DProjectStore.modelURL(fileName: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else {
                self.error = "STEP 源文件已不在 Documents/MacroGen-3D-models，请重新导入"
                return
            }
            importBusy = true
            importMode = .step
            Task { @MainActor in
                defer { self.importBusy = false }
                do {
                    var part = try await self.kernelService.importSTEP(
                        from: url,
                        name: stored.importedName ?? url.deletingPathExtension().lastPathComponent
                    )
                    if let unitInMeters = stored.importedUnitInMeters {
                        part.unitInMeters = unitInMeters
                    }
                    self.importedPart = part
                    self.params = stored.params ?? True3DParams()
                    self.modelOperations = stored.operations
                    self.modelDocumentID = stored.id
                    self.selectedFeatureID = stored.selectedNodeID
                    self.result = nil
                    self.scene = SCNScene()
                    self.rebuild()
                    self.notice = "已载入 STEP 工程：\(part.name)"
                } catch {
                    self.error = "载入 STEP 工程失败：\(error.localizedDescription)"
                }
            }
            return
        }

        importedPart = nil
        params = stored.params ?? True3DParams()
        modelOperations = stored.operations
        modelDocumentID = stored.id
        selectedFeatureID = stored.selectedNodeID
        rebuild()
        notice = "已载入上次保存的 3D 工程"
    }

    private func handlePickedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "step", "stp":
            importSTEP(url)
        case "dxf":
            importDXF(url)
        default:
            error = "只支持 STEP / STP / DXF 文件，当前选择的是 .\(ext.isEmpty ? "未知格式" : ext)"
        }
    }

    private func importSTEP(_ url: URL) {
        guard !importBusy else { return }
        importMode = .step
        importBusy = true
        error = nil
        let access = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                self.importBusy = false
            }
            var copiedURL: URL?
            do {
                let copied = try await Task.detached(priority: .userInitiated) {
                    try True3DProjectStore.copyModelFile(from: url)
                }.value
                copiedURL = copied
                let name = url.deletingPathExtension().lastPathComponent
                let part = try await self.kernelService.importSTEP(from: copied, name: name)
                self.importedPart = part
                self.modelOperations = []
                self.modelDocumentID = UUID()
                self.selectedFeatureID = nil
                self.result = nil
                self.scene = SCNScene()
                self.stage = .model
                self.rebuild()
                self.notice = "已导入 STEP：\(name)"
            } catch {
                if let copiedURL {
                    try? FileManager.default.removeItem(at: copiedURL)
                }
                self.error = "STEP 导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func exitImportedPart() {
        importedPart = nil
        modelOperations = []
        params = True3DParams()
        params.features = []
        modelDocumentID = UUID()
        selectedFeatureID = nil
        result = nil
        scene = SCNScene()
        stage = .model
        rebuild()
        notice = "已退出 STEP 模型，回到空白参数化模型"
    }

    private func importDXF(_ url: URL) {
        importMode = .dxf
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
        importedPart = nil
        modelOperations = []
        modelDocumentID = UUID()
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

struct True3DSceneView: UIViewRepresentable {
    let scene: SCNScene
    let showWire: Bool
    let allowsCameraControl: Bool
    var onPickEdge: ((SCNView, CGPoint, CGSize) -> Void)?

    init(
        scene: SCNScene,
        showWire: Bool,
        allowsCameraControl: Bool = true,
        onPickEdge: ((SCNView, CGPoint, CGSize) -> Void)? = nil
    ) {
        self.scene = scene
        self.showWire = showWire
        self.allowsCameraControl = allowsCameraControl
        self.onPickEdge = onPickEdge
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPickEdge: ((SCNView, CGPoint, CGSize) -> Void)?
        private var panStartPosition: SCNVector3?
        private var panStartTarget: SCNVector3?
        private var panStartDistance: Float = 0
        private var panStartYaw: Double = 0
        private var panStartPitch: Double = 0

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            onPickEdge?(view, gesture.location(in: view), view.bounds.size)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? SCNView,
                  let scene = view.scene,
                  let camera = scene.rootNode.childNode(withName: "workbenchCamera", recursively: true),
                  let target = scene.rootNode.childNode(withName: "cameraTarget", recursively: true) else { return }
            if gesture.state == .began {
                panStartPosition = camera.position
                panStartTarget = target.position
                let dx = camera.position.x - target.position.x
                let dy = camera.position.y - target.position.y
                let dz = camera.position.z - target.position.z
                panStartDistance = max((dx * dx + dy * dy + dz * dz).squareRoot(), 0.001)
                panStartYaw = Double(atan2(dx, dz))
                panStartPitch = Double(asin(max(-1, min(1, dy / panStartDistance))))
            }
            guard gesture.state == .changed || gesture.state == .ended,
                  panStartPosition != nil else { return }
            let translation = gesture.translation(in: view)
            let yaw = panStartYaw - Double(translation.x) * 0.009
            let pitch = max(-1.552, min(1.552, panStartPitch + Double(translation.y) * 0.008))
            let direction = SCNVector3(
                Float(sin(yaw) * cos(pitch)),
                Float(sin(pitch)),
                Float(cos(yaw) * cos(pitch))
            )
            let length = max((direction.x * direction.x + direction.y * direction.y + direction.z * direction.z).squareRoot(), 0.001)
            let targetPosition = panStartTarget ?? target.position
            let newPosition = SCNVector3(
                targetPosition.x + direction.x / length * panStartDistance,
                targetPosition.y + direction.y / length * panStartDistance,
                targetPosition.z + direction.z / length * panStartDistance
            )
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            camera.position = newPosition
            SCNTransaction.commit()
            if gesture.state == .ended {
                panStartPosition = nil
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        if let camera = scene.rootNode.childNode(withName: "workbenchCamera", recursively: true) {
            view.pointOfView = camera
        }
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        if allowsCameraControl {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = context.coordinator
            view.addGestureRecognizer(pan)
        }
        context.coordinator.onPickEdge = onPickEdge
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        uiView.allowsCameraControl = false
        if let camera = scene.rootNode.childNode(withName: "workbenchCamera", recursively: true) {
            uiView.pointOfView = camera
        }
        context.coordinator.onPickEdge = onPickEdge
        uiView.scene?.rootNode.enumerateChildNodes { node, _ in
            if node.name == "wireOverlay" {
                node.isHidden = !showWire
            }
        }
    }
}

struct True3DDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: True3DDocumentPicker

        init(_ parent: True3DDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
