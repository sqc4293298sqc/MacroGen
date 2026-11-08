import SwiftUI

struct CodeItem: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let desc: String
}

let gCodes: [CodeItem] = [
    CodeItem(code: "G00", name: "快速定位", desc: "刀具以机床设定的最快速度移到目标点，不切削。例：G00 X100 Y50 Z100。\n下刀前必须先 G00 抬到安全高度，再动 XY。"),
    CodeItem(code: "G01", name: "直线插补", desc: "按 F 设定的进给速度走直线，切削主力。\n例：G01 Z-3. F400（下刀 3mm）；G01 X120. F400（铣一条直线）。"),
    CodeItem(code: "G02", name: "顺时针圆弧", desc: "走顺时针圆弧。写法两种：\n① G02 X终点 Y终点 R半径（R 为负表示大于半圆的弧）\n② G02 X终点 Y终点 I圆心到起点X J圆心到起点Y\n整圆只写圆心偏移：G02 I-10."),
    CodeItem(code: "G03", name: "逆时针圆弧", desc: "走逆时针圆弧，写法同 G02。\n螺旋铣、锥孔就是靠它：G03 I#6 Z#7，一圈下降 #7。"),
    CodeItem(code: "G04", name: "暂停（延时）", desc: "G04 X1.5 表示停 1.5 秒，G04 P1500 表示停 1500 毫秒。\n孔底停一下、清角停一下都用它。"),
    CodeItem(code: "G09", name: "准确停止", desc: "走这一段时先减速停稳再走下一段，只在当前段有效。\n精修拐角、怕过切时加。"),
    CodeItem(code: "G10", name: "可编程数据输入", desc: "用程序改刀补或工件坐标，不用手动敲面板。\n例：G10 L12 P1 R6.0（把 1 号刀补半径改成 6）；G10 L2 P1 X0 Y0（改 G54）。"),
    CodeItem(code: "G17/G18/G19", name: "选择加工平面", desc: "G17=XY 平面（铣床默认）、G18=ZX、G19=YZ。\n铣削基本都写 G17。"),
    CodeItem(code: "G20/G21", name: "英制 / 公制", desc: "G20 英寸、G21 毫米。开机默认一般是 G21，不用管，但换系统要确认。"),
    CodeItem(code: "G28", name: "返回参考点", desc: "回机械零点。例：G28 G91 Z0（Z 回零）、G28 G91 Y0。\n一定要带 G91，否则会按坐标值乱跑。"),
    CodeItem(code: "G30", name: "返回第二参考点", desc: "回厂家设定的第二参考点，加工中心常把它设成换刀点。写法同 G28。"),
    CodeItem(code: "G31", name: "跳转指令", desc: "碰到外部信号就立即跳到下一段，用于测头测量、对刀。"),
    CodeItem(code: "G40", name: "取消刀补", desc: "取消 G41/G42 半径补偿。程序结束前要写。"),
    CodeItem(code: "G41", name: "左刀补", desc: "沿走刀方向看，刀具在工件左边。\n铣内轮廓（型腔）用它：G41 D13，D 是刀补号。"),
    CodeItem(code: "G42", name: "右刀补", desc: "沿走刀方向看，刀具在工件右边。铣外形（外轮廓凸台）常用。"),
    CodeItem(code: "G43", name: "刀具长度补偿（正）", desc: "把刀长差补上，不写就会按机床 Z 值撞刀。\n例：G43 H13 Z100，H13 要和该刀对刀时的高度号一致。"),
    CodeItem(code: "G44", name: "刀具长度补偿（负）", desc: "很少用，一般只用 G43。"),
    CodeItem(code: "G49", name: "取消长度补偿", desc: "程序结束前写，避免下次调用出错。"),
    CodeItem(code: "G50/G51", name: "比例缩放 / 取消", desc: "G51 X0 Y0 P0.5 表示图形缩小一半，G50 取消。图形放大缩小用。"),
    CodeItem(code: "G52", name: "局部坐标系", desc: "在 G54 里再设一个小原点，只对本程序有效。\n例：G52 X#31 Y#32 把原点平移到型腔中心，程序里就能按中心编程。"),
    CodeItem(code: "G53", name: "机床坐标系移动", desc: "不受 G54~G59 影响，直接走到机床固定点。换刀、清台面常用。"),
    CodeItem(code: "G54~G59", name: "工件坐标系", desc: "最常用的六个坐标系，装夹找正后把原点输进对应的 G54~G59。\n扩展坐标系：G54.1 P1 ~ P48。"),
    CodeItem(code: "G65", name: "调用宏程序", desc: "G65 P9010 A5. B3. 调用 9010 号宏，A/B 把值传给子程序里的 #1/#2。"),
    CodeItem(code: "G66/G67", name: "模态宏调用 / 取消", desc: "G66 之后每一次移动都自动调一次宏，G67 取消。做阵列、多孔时省代码。"),
    CodeItem(code: "G68/G69", name: "坐标旋转 / 取消", desc: "例：G68 X0 Y0 R45. 让后面的程序整体旋转 45°，G69 取消。斜孔、斜槽常用。"),
    CodeItem(code: "G73", name: "高速深孔钻（断屑）", desc: "每次钻一小段就快速退回一点点，把屑带出来。适合深孔、易积屑材料。"),
    CodeItem(code: "G74", name: "左旋攻丝", desc: "反牙螺纹用。F 值 = 螺距 × 转速。"),
    CodeItem(code: "G76", name: "精镗", desc: "镗到孔底主轴停下、刀尖让开再退，不刮伤孔壁。镗精度孔必备。"),
    CodeItem(code: "G80", name: "取消固定循环", desc: "钻孔、镗孔、攻丝做完必须写，否则后面的移动会按循环方式乱走。"),
    CodeItem(code: "G81", name: "钻孔", desc: "例：G81 X0 Y0 Z-20. R2. F100，钻到 Z-20，R2 是安全平面。"),
    CodeItem(code: "G82", name: "沉孔 / 孔底暂停", desc: "和 G81 一样，多了孔底停顿 P 值，沉孔、扩孔用。"),
    CodeItem(code: "G83", name: "深孔啄钻", desc: "例：G83 X0 Y0 Z-30. R2. Q3. F80，每次啄 3mm 排屑一次，Q 是每次深度。"),
    CodeItem(code: "G84", name: "攻丝", desc: "例：M29 S800 / G84 X0 Y0 Z-15. R2. F1.5（M22×1.5 时 F=1.5）。\n必须要有刚性攻丝，转速×螺距=进给。"),
    CodeItem(code: "G85", name: "镗孔（进给退刀）", desc: "一边进给一边退，最简单的一种镗孔循环。"),
    CodeItem(code: "G86", name: "镗孔（停主轴后退）", desc: "孔底主轴停，刀偏移让开再退。精度要求高时用 G76。"),
    CodeItem(code: "G90/G91", name: "绝对 / 增量编程", desc: "G90 按坐标值走，G91 按“再走多少”走。\n回零、抬刀用 G91 更安全：G91 Z50。"),
    CodeItem(code: "G92", name: "工件坐标预置", desc: "把当前位置设成指定坐标，等于挪原点，容易出错，新手少用。"),
    CodeItem(code: "G94/G95", name: "每分钟 / 每转进给", desc: "G94 单位 mm/min（铣床默认），G95 单位 mm/r（攻丝、镗孔有时用）。"),
    CodeItem(code: "G98/G99", name: "固定循环返回点", desc: "G98 每次退回到初始高度，G99 只退到 R 点。\n同一平面多个孔用 G99 可以少走很多空行程。"),
    CodeItem(code: "G61/G64", name: "准停模式 / 切削模式", desc: "G61 每一段都停稳再走，精度高、速度慢；G64 连续过渡最顺，模具曲面用。"),
    CodeItem(code: "G96/G97", name: "恒线速 / 取消", desc: "车床上按线速度恒定，铣床基本不用。"),
]

let mCodes: [CodeItem] = [
    CodeItem(code: "M00", name: "程序无条件停止", desc: "程序执行到这一句就停，按“循环启动”继续。装夹、检查时用。"),
    CodeItem(code: "M01", name: "计划停止", desc: "只有面板上的“选择停止”开关打开时才停。试首件时打开，很方便。"),
    CodeItem(code: "M02", name: "程序结束", desc: "结束并复位，但光标不一定回开头，一般用 M30 更彻底。"),
    CodeItem(code: "M03", name: "主轴正转", desc: "例：M03 S2000。S 是转速 r/min。\n顺时针（面向主轴看）为正转，一般铣刀都用正转。"),
    CodeItem(code: "M04", name: "主轴反转", desc: "反牙攻丝、某些刀柄需要反转。"),
    CodeItem(code: "M05", name: "主轴停止", desc: "程序结束、换刀前必须停。"),
    CodeItem(code: "M06", name: "自动换刀", desc: "例：M06 T13，T13 是刀号。\n换刀前必须 G91 G28 Z0 回 Z 零点，否则撞刀。"),
    CodeItem(code: "M07", name: "雾状冷却", desc: "气雾冷却，铸铁、铝件常用，比大水冲干净。"),
    CodeItem(code: "M08", name: "开冷却液", desc: "切削液开。钢件开粗、深孔必开。"),
    CodeItem(code: "M09", name: "关冷却液", desc: "程序结束前关，避免漏液。"),
    CodeItem(code: "M19", name: "主轴定向", desc: "主轴停在一个固定角度，镗孔让刀、反镗刀进出孔要用。"),
    CodeItem(code: "M30", name: "程序结束并复位", desc: "光标回到程序开头，最适合连续加工。程序最后一句写它。"),
    CodeItem(code: "M98/M99", name: "调用子程序 / 返回", desc: "M98 P1000 L3 表示调用 1000 号子程序、重复 3 次，子程序最后一行写 M99 返回。"),
    CodeItem(code: "M10/M11", name: "夹紧 / 松开", desc: "由机床厂家定义，常见是夹紧 M10、松开 M11。使用前查机床说明书。"),
    CodeItem(code: "M48/M49", name: "倍率忽略 / 恢复", desc: "刚性攻丝前写 M48 锁住进给倍率，攻完 M49 恢复。"),
    CodeItem(code: "M41/M42/M43", name: "主轴档位切换", desc: "老式齿轮箱主轴用，现在多为主轴电机无级调速，可不写。"),
    CodeItem(code: "M60", name: "托盘交换", desc: "带自动交换工作台的加工中心用，换台面。"),
]

let others: [CodeItem] = [
    CodeItem(code: "F", name: "进给速度", desc: "单位 mm/min（G94 时）。粗铣钢件 300~600，精铣 600~1200，看刀具和机床。"),
    CodeItem(code: "S", name: "主轴转速", desc: "单位 r/min。转速和进给要配合，转速太高小刀会烧，太低会振刀。"),
    CodeItem(code: "T", name: "刀具号", desc: "T1~T99 常见，和刀库位置对应。换刀写 M06 T 号。"),
    CodeItem(code: "D", name: "刀补号", desc: "半径补偿号。G41 D13 表示用 13 号刀补半径，改尺寸只需改刀补，不用改程序。"),
    CodeItem(code: "H", name: "刀长补偿号", desc: "G43 H13，和 D 一样是号，别混：D 管半径，H 管长度。"),
    CodeItem(code: "O", name: "程序号", desc: "O0001~O9999。本 App 生成 O1001~O1005 分别对应五种模式。"),
    CodeItem(code: "N", name: "程序段号", desc: "N10、N20… 便于跳段和查找，可不写。"),
    CodeItem(code: "括号", name: "注释", desc: "（型腔粗铣）括号里是注释，机床会忽略，写清楚方便下次看。"),
]

let macroItems: [CodeItem] = [
    CodeItem(code: "#1~#33", name: "局部变量", desc: "只在本程序内有效，断电丢失。切削参数一般放这里：\n#1=120.（长） #2=80.（宽）"),
    CodeItem(code: "#100~#199", name: "公共变量", desc: "各程序共用，断电一般清零。#500~#999 断电保持，用来记数、记状态。"),
    CodeItem(code: "#1000 以上", name: "系统变量", desc: "机床内部状态量（坐标、刀补等），读写要小心，新手别碰。"),
    CodeItem(code: "[ ]", name: "运算括号", desc: "宏程序里必须用方括号：#11=[#1/2.]。\n写成 (#1/2) 会报警。小数点也别省：#1=1. 要带点。"),
    CodeItem(code: "EQ/NE/GT/GE/LT/LE", name: "比较", desc: "等于 / 不等于 / 大于 / 大于等于 / 小于 / 小于等于。\n例：WHILE[#23LT#3]DO1 表示当前深度小于总深就继续循环。"),
    CodeItem(code: "AND/OR/XOR", name: "逻辑", desc: "与 / 或 / 异或，用在条件判断里组合多个条件。"),
    CodeItem(code: "ABS/SQRT", name: "绝对值 / 开方", desc: "ABS[-5]=5；SQRT[16]=4。"),
    CodeItem(code: "SIN/COS/TAN", name: "三角函数", desc: "角度按度算（FANUC 默认）。锥孔半角就靠 TAN[#3] 算每一层的半径差。"),
    CodeItem(code: "ATAN", name: "反正切", desc: "由两直角边求角度：#3=ATAN[[#1-#2]/2./#4]，本 App 的锥孔半角就是这么算的。"),
    CodeItem(code: "ROUND/FIX/FUP", name: "取整", desc: "四舍五入 / 舍去小数 / 进位。分层数、圈数用它。"),
    CodeItem(code: "WHILE[ ] DO n … END n", name: "当型循环", desc: "条件成立就一直循环，n 为 1~3 层号，END n 收尾，必须成对。\n本 App 的分层、分行都是这种结构。"),
    CodeItem(code: "IF[ ] THEN", name: "条件执行", desc: "IF[#23GT#3]THEN#23=#3 —— 超深了就拉回到总深，防止过切。"),
    CodeItem(code: "IF[ ] GOTO n / GOTO n", name: "条件跳转 / 无条件跳转", desc: "跳到段号 N 处。少用，容易死循环。"),
    CodeItem(code: "#10=#10+1", name: "自增计数", desc: "常用写法，统计走了第几圈、第几行。"),
]

let tips: [CodeItem] = [
    CodeItem(code: "①", name: "先抬刀再动 XY", desc: "任何换位、进给之前，先把 Z 抬到安全高度（本 App 用 #10=100），再动 X/Y。撞刀九成是顺序反了。"),
    CodeItem(code: "②", name: "G43 H 号必须有", desc: "每把刀都要 G43 H 对应的补偿号，号或正负错了直接扎工件。"),
    CodeItem(code: "③", name: "先空跑验证", desc: "新程序把 Z 整体抬高 100 空跑一遍，看清刀路再落刀。"),
    CodeItem(code: "④", name: "参数集中写前面", desc: "尺寸、深度、转速、进给都放在程序开头的 #1~#9，改一处就全改，别散在中间。"),
    CodeItem(code: "⑤", name: "循环必须有出口", desc: "WHILE 一定要有让条件变假的语句（#23=#23+#6），否则死机。"),
    CodeItem(code: "⑥", name: "结束要收干净", desc: "G80 取消循环、M09 关液、G91 G28 Z0 回零、M30 结束，缺一句都可能报警或撞机。"),
]

struct CodeRefView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private func match(_ items: [CodeItem]) -> [CodeItem] {
        let kw = query.trimmingCharacters(in: .whitespaces).lowercased()
        if kw.isEmpty { return items }
        return items.filter {
            $0.code.lowercased().contains(kw)
                || $0.name.lowercased().contains(kw)
                || $0.desc.lowercased().contains(kw)
        }
    }

    private var totalHits: Int {
        match(gCodes).count + match(mCodes).count + match(others).count
            + match(macroItems).count + match(tips).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("按 FANUC 0i 系列整理，不同机床的 M 代码可能有差异，上机前请核对机床说明书。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                section("G 代码（准备功能）", gCodes)
                section("M 代码（辅助功能）", mCodes)
                section("其他常用指令", others)
                section("宏程序基础语法", macroItems)
                section("新手六条铁律", tips)

                if totalHits == 0 {
                    Section {
                        Text("没找到「\(query)」\n换个说法试试：G43、攻丝、刀补、WHILE、M30")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("编程代码大全")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索代码或关键词：G43 / 攻丝 / 刀补")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [CodeItem]) -> some View {
        let hits = match(items)
        if !hits.isEmpty {
        Section(query.isEmpty ? title : title + " · 相关") {
            ForEach(hits) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.code)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 1, green: 0.42, blue: 0.10).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(item.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.11, green: 0.14, blue: 0.19))
                    }
                    Text(item.desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.48, green: 0.52, blue: 0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 3)
            }
        }
        }
    }
}
