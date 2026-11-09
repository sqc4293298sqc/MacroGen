import SwiftUI

/// 刀具转速进给推荐：皇冠钻 / 整体合金钻 / 普通高速钢钻
struct ToolFeedView: View {
    let materials = ["碳钢 / 合金钢", "不锈钢", "铸铁", "铝 / 铜"]
    let tools = ["皇冠钻（U 钻 / 可换头）", "整体合金钻", "普通高速钢钻"]

    // Vc（m/min）：[刀具][材料]
    static let vc: [[Double]] = [
        [130, 80, 150, 250],
        [100, 60, 110, 200],
        [25, 15, 22, 60]
    ]
    // 每转进给 = k × 直径
    static let frevK: [Double] = [0.012, 0.010, 0.008]
    static let dias: [Double] = [3, 5, 6, 8, 10, 12, 16, 20, 25, 30]

    @State private var tool = 0
    @State private var mat = 0
    @State private var diaText = "10"
    @State private var deepText = "30"
    @Environment(\.dismiss) private var dismiss

    private var dia: Double { max(Double(diaText.replacingOccurrences(of: ",", with: ".")) ?? 10, 0.1) }
    private var deep: Double { Double(deepText.replacingOccurrences(of: ",", with: ".")) ?? dia * 3 }
    private var ratio: Double { deep / dia }

    private var nFactor: Double { ratio <= 3 ? 1.0 : (ratio <= 5 ? 0.85 : 0.7) }
    private var fFactor: Double { ratio <= 3 ? 1.0 : (ratio <= 5 ? 0.9 : 0.75) }

    private var nRaw: Double { 1000 * ToolFeedView.vc[tool][mat] / (Double.pi * dia) }
    private var nMax: Double { tool == 2 ? 3000 : 5000 }
    private var n: Double { min(nRaw * nFactor, nMax) }
    private var frev: Double { ToolFeedView.frevK[tool] * dia * fFactor }
    private var feed: Double { n * frev }

    var body: some View {
        NavigationStack {
            Form {
                Section("选刀具和工况") {
                    Picker("刀具类型", selection: $tool) {
                        ForEach(0..<tools.count, id: \.self) { i in
                            Text(tools[i]).tag(i)
                        }
                    }
                    Picker("工件材料", selection: $mat) {
                        ForEach(0..<materials.count, id: \.self) { i in
                            Text(materials[i]).tag(i)
                        }
                    }
                    HStack {
                        Text("钻头直径 Ø")
                        Spacer()
                        TextField("10", text: $diaText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("孔深 (mm)")
                        Spacer()
                        TextField("30", text: $deepText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }

                Section("推荐") {
                    HStack(spacing: 4) {
                        numBlock("转速 S", "\(Int(roundTo10(n)))", "r/min")
                        numBlock("进给 F", "\(Int(round(feed)))", "mm/min")
                        numBlock("每转进给", String(format: "%.2f", frev), "mm/r")
                    }
                    Text("S×每转进给 = \(Int(round(feed))) mm/min；可写 F\(Int(round(feed)))（G94）或每转 F\(String(format: "%.2f", frev))（G95）")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(advice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("常用直径推荐（3 倍径以内）") {
                    ForEach(ToolFeedView.dias, id: \.self) { d in
                        let nn = min(1000 * ToolFeedView.vc[tool][mat] / (Double.pi * d), nMax)
                        let ff = nn * ToolFeedView.frevK[tool] * d
                        HStack {
                            Text("Ø\(fmt(d))").bold()
                            Spacer()
                            Text("\(Int(roundTo10(nn))) r/min")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(round(ff))) mm/min")
                                .bold()
                                .foregroundStyle(.orange)
                        }
                        .font(.footnote)
                    }
                }

                Section("怎么用、怎么微调") {
                    Text("""
                    转速：S = 1000 × Vc ÷ (3.14 × 直径)，Vc 是切削速度（m/min），刀样本上都有
                    进给：F = S × 每转进给，每转进给约取直径的 0.8%～1.2%
                    倍径 = 孔深 ÷ 直径。3 倍径以内按表值；3～5 倍降 15%；超过 5 倍降 30%，必须分步钻
                    皇冠钻 / 合金钻：一定内冷（M8 或内冷刀柄），铁屑冲得出来才不会挤刀
                    普通高速钢钻：深孔用 G83 啄钻，转速别超 3000
                    不锈钢：转速再降一档，别在原地磨，容易硬化
                    铝：转速可再高 20%，进给给足，注意排屑
                    表里只是起点：看铁屑颜色（发蓝=偏热）、听声音（尖叫=转速高或让刀），上下调 10%～20%
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("刀具转速进给")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var advice: String {
        var out: [String] = []
        if ratio > 5 { out.append("• \(fmt(ratio)) 倍径属于深孔：必须分步钻（G83 每次 2～3mm），保证内冷") }
        else if ratio > 3 { out.append("• \(fmt(ratio)) 倍径：建议分两步，先钻一半再到底") }
        if tool == 0 { out.append("• 皇冠钻是单刃可换头，每转进给别小于 \(String(format: "%.2f", ToolFeedView.frevK[0] * dia * 0.6)) mm/r，太小磨刀头") }
        if tool == 1 { out.append("• 合金钻：入钻先给 50% 转速，钻进 1～2mm 再全速") }
        if tool == 2 { out.append("• 普通高速钢钻：深孔用 G83 啄钻，转速别超 3000") }
        if mat == 1 { out.append("• 不锈钢：切屑粘刀，进给别太小，宁可慢也别原地磨") }
        if mat == 3 { out.append("• 铝：转速可再高 20%，进给给足防粘刀") }
        out.append("• 直径大于 20 优先皇冠钻或合金钻，普通钻给不到这么高切削速度")
        return out.joined(separator: "\n")
    }

    private func numBlock(_ caption: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.orange)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
            Text(caption).font(.caption).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roundTo10(_ v: Double) -> Double { (v / 10).rounded() * 10 }

    private func fmt(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.001 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
    }
}
