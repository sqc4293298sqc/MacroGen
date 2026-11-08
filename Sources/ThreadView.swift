import SwiftUI

/// 丝锥底孔查询页：螺距、切削底孔、挤压底孔、推荐钻头
struct ThreadView: View {

    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable {
        case coarse = "公制粗牙"
        case fine = "公制细牙"
        case pipe = "管螺纹 G"
        case npt = "NPT 锥管"
        case inch = "美制 UNC/UNF"
    }

    @State private var tab: Tab = .coarse

    private var rows: [ThreadRow] {
        switch tab {
        case .coarse: return ThreadData.metricRows(coarse: true)
        case .fine: return ThreadData.metricRows(coarse: false)
        case .pipe: return ThreadData.inchRows(ThreadData.gThread)
        case .npt: return ThreadData.inchRows(ThreadData.npt)
        case .inch: return ThreadData.inchRows(ThreadData.unc)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { r in
                        HStack(spacing: 8) {
                            Text(r.name)
                                .font(.subheadline.bold())
                                .frame(width: 96, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("螺距 \(r.pitchText)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("挤压底孔 \(r.squeeze)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(r.drill)
                                    .font(.headline)
                                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.1))
                                Text("底孔").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(tab.rawValue)
                }

                Section("底孔怎么算") {
                    Text("切削丝锥（普通丝锥）：底孔 = 公称直径 − 螺距")
                    Text("挤压丝锥（无屑丝锥）：底孔 ≈ 公称直径 − 螺距/2")
                    Text("攻丝进给：F = 螺距（mm/r），转速×螺距必须等于进给。例 M10×1.5、S400 → F1.5")
                    Text("不锈钢、调质钢底孔取大 0.05～0.1，防止丝锥挤死；铝、铜取表中值。")
                    Text("实际按 0.05mm 就近选钻头：M8 算出 6.75 → 用 6.8 钻头。")
                }
                .font(.footnote)
            }
            .navigationTitle("丝锥底孔查询")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
