import SwiftUI

/// 打开软件时的更新提示：只在本版本第一次打开时弹一次，一句话一条，不铺开写
enum UpdateNotes {
    static let items: [String] = [
        "锥孔 / 内圆倒角 / 外圆倒角改成螺旋一刀流，中途不抬刀",
        "外方形改成上边中点（X0）半圆弧切入、半圆弧退刀",
        "刀路仿真合批绘制 + 抽稀，几千个点也不卡了",
        "仿真画布照旧：双指缩放、拖动平移、双击复位"
    ]
}

struct UpdateSheet: View {
    let items: [String]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("更新内容")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(red: 0.106, green: 0.141, blue: 0.192))
                Text(AppInfo.versionTag.trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 1.0, green: 0.420, blue: 0.102))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.bottom, 16)

            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.420, blue: 0.102))
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(line)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.2, green: 0.251, blue: 0.31))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 11)
            }

            Spacer(minLength: 10)

            Button(action: onClose) {
                Text("知道了")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(red: 1.0, green: 0.420, blue: 0.102))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(20)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }
}
