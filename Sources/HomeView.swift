import SwiftUI

/// 首页：三列宫格工具箱，点一下就进对应功能（照着数控大师的布局做的）
struct HomeView: View {
    @State private var showRef = false
    @State private var showTol = false
    @State private var showThread = false
    @State private var showFeed = false
    @State private var showImport = false

    private let prog: [(String, String, MachiningMode)] = [
        ("型腔铣", "square.dashed", .pocket),
        ("平面铣", "rectangle.split.3x1", .face),
        ("螺旋铣", "circle.hexagongrid", .spiral),
        ("键槽", "capsule", .key),
        ("外方形", "square.on.square", .outer),
        ("锥孔", "triangle", .taper),
        ("内圆倒角", "circle.circle", .innerChamfer),
        ("外圆倒角", "circle", .odCham)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                group("编程")

                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(prog, id: \.0) { item in
                        NavigationLink {
                            ContentView(mode: item.2)
                        } label: {
                            Tile(title: item.0, icon: item.1, tint: Color(red: 1.0, green: 0.42, blue: 0.10))
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        DrawScreen()
                    } label: {
                        Tile(title: "绘图编程", icon: "scribble.variable",
                             tint: Color(red: 1.0, green: 0.42, blue: 0.10))
                    }
                    .buttonStyle(.plain)
                }

                group("查询 · 工具")

                LazyVGrid(columns: gridColumns, spacing: 20) {
                    Button { showImport = true } label: {
                        Tile(title: "导入模拟", icon: "camera.viewfinder", tint: toolColor(0))
                    }
                    .buttonStyle(.plain)

                    Button { showRef = true } label: {
                        Tile(title: "代码大全", icon: "book", tint: toolColor(1))
                    }
                    .buttonStyle(.plain)

                    Button { showTol = true } label: {
                        Tile(title: "尺寸公差", icon: "ruler", tint: toolColor(2))
                    }
                    .buttonStyle(.plain)

                    Button { showThread = true } label: {
                        Tile(title: "丝锥底孔", icon: "circle.hexagongrid", tint: toolColor(3))
                    }
                    .buttonStyle(.plain)

                    Button { showFeed = true } label: {
                        Tile(title: "转速进给", icon: "gauge.with.dots.needle.bottom.50percent", tint: toolColor(0))
                    }
                    .buttonStyle(.plain)
                }

                Text("宏程序生成器 " + (AppInfo.version.isEmpty ? "" : "v" + AppInfo.version) + " · 当里个当制作")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.62, green: 0.66, blue: 0.71))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
        .navigationTitle("工具箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(AppInfo.version.isEmpty ? "" : "v" + AppInfo.version)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showRef) { CodeRefView() }
        .sheet(isPresented: $showTol) { ToleranceView() }
        .sheet(isPresented: $showThread) { ThreadView() }
        .sheet(isPresented: $showFeed) { ToolFeedView() }
        .sheet(isPresented: $showImport) { ImportView() }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    private func toolColor(_ i: Int) -> Color {
        let cols: [Color] = [
            Color(red: 0.16, green: 0.44, blue: 0.86),
            Color(red: 0.36, green: 0.32, blue: 0.72),
            Color(red: 0.10, green: 0.55, blue: 0.50),
            Color(red: 0.55, green: 0.40, blue: 0.86)
        ]
        return cols[i % cols.count]
    }

    private func group(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.14, green: 0.17, blue: 0.22))
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1)
        }
    }
}

/// 宫格里的一格：图标方框 + 名称
struct Tile: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(height: 66)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.16, green: 0.19, blue: 0.25))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
