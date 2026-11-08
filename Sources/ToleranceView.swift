import SwiftUI

/// 尺寸公差查询页：H7 / H8 / g6 / e7 等
struct ToleranceView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var sizeText = "30"
    @State private var isHole = true
    @State private var pos = "H"
    @State private var grade = 7

    private var size: Double? { Double(sizeText.replacingOccurrences(of: ",", with: ".")) }
    private var positions: [String] { isHole ? ToleranceEngine.holePositions : ToleranceEngine.shaftPositions }

    private var dev: (Int, Int, Int)? {
        guard let s = size else { return nil }
        return isHole ? ToleranceEngine.holeDev(pos, s, grade) : ToleranceEngine.shaftDev(pos, s, grade)
    }

    private var fits: [(String, String)] = [
        ("H7", "g6"), ("H7", "h6"), ("H8", "f7"), ("H7", "k6"),
        ("H7", "n6"), ("H7", "p6"), ("H9", "d9"), ("H11", "d11")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本尺寸") {
                    HStack {
                        Text("公称尺寸 mm")
                        Spacer()
                        TextField("30", text: $sizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Picker("类型", selection: $isHole) {
                        Text("孔（大写 H7…）").tag(true)
                        Text("轴（小写 h6…）").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isHole) { v in
                        pos = v ? "H" : "h"
                    }
                }

                Section {
                    Picker("公差带", selection: $pos) {
                        ForEach(positions, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                    Picker("公差等级", selection: $grade) {
                        ForEach(ToleranceEngine.minGrade...ToleranceEngine.maxGrade, id: \.self) { g in
                            Text("IT\(g)").tag(g)
                        }
                    }
                } header: {
                    Text("公差带与等级")
                } footer: {
                    Text(isHole ? "孔的常用偏差带：H 基孔制，G/F/E/D 为间隙孔" : "轴的常用偏差带：h 基轴制，g/f/e/d 间隙，k/m/n/p 过渡到过盈")
                }

                Section("查询结果") {
                    if let s = size, let d = dev {
                        let up = isHole ? "ES" : "es"
                        let lo = isHole ? "EI" : "ei"
                        Text("Ø\(fmt(s))  \(pos)\(grade)")
                            .font(.title2.bold())
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.1))
                        let half = pos == "js" || pos == "JS"
                        row("上偏差 \(up)", half ? ToleranceEngine.textHalf(d.2) : ToleranceEngine.text(d.0))
                        row("下偏差 \(lo)", half ? ToleranceEngine.textHalf(-d.2) : ToleranceEngine.text(d.1))
                        row("公差", ToleranceEngine.text(d.2) + "  (IT\(grade))")
                        row("最大极限", String(format: "%.4f", s + (half ? Double(d.2) / 2000 : Double(d.0) / 1000)))
                        row("最小极限", String(format: "%.4f", s - (half ? Double(d.2) / 2000 : Double(-d.1) / 1000)))
                    } else {
                        Text("请输入 0～500 之间的尺寸").foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(Array(fits.enumerated()), id: \.offset) { pair in
                        fitRow(pair.element.0, pair.element.1)
                    }
                } header: {
                    Text("常用配合速查（Ø30 例）")
                } footer: {
                    Text("数值按 GB/T 1800.2 标准公差与基本偏差计算，单位 mm。加工时以图纸标注为准，把实测尺寸与上下极限对比即可判断合格。")
                }
            }
            .navigationTitle("尺寸公差查询")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func fitRow(_ hole: String, _ shaft: String) -> some View {
        let hg = Int(hole.filter { $0.isNumber }) ?? 7
        let sg = Int(shaft.filter { $0.isNumber }) ?? 6
        let h = ToleranceEngine.holeDev(hole, 30, hg)
        let s = ToleranceEngine.shaftDev(shaft, 30, sg)
        let type = ToleranceEngine.fitType(hole: hole, shaft: shaft, size: 30, hg: hg, sg: sg)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Ø30  \(hole)/\(shaft)").font(.subheadline.bold())
                Spacer()
                Text(type).font(.caption).foregroundStyle(.orange)
            }
            if let h = h, let s = s {
                Text("孔 \(ToleranceEngine.text(h.0))/\(ToleranceEngine.text(h.1))   轴 \(ToleranceEngine.text(s.0))/\(ToleranceEngine.text(s.1))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("最大间隙 \(ToleranceEngine.text(h.0 - s.1))   最小间隙 \(ToleranceEngine.text(h.1 - s.0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
