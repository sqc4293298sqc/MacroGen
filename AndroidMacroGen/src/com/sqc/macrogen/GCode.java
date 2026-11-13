package com.sqc.macrogen;

import java.text.DecimalFormat;
import java.text.DecimalFormatSymbols;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class GCode {

    public static final int CORNER_R = 0;
    public static final int CORNER_C = 1;
    public static final int CORNER_SQUARE = 2;

    public double length = 120;
    public double width = 80;
    public double depth = 10;
    public static final int MODE_POCKET = 0;
    public static final int MODE_TAPER = 1;
    public static final int MODE_FACE = 2;
    public static final int MODE_SPIRAL = 3;
    public static final int MODE_KEY = 4;
    public static final int MODE_OUTER = 5;
    public static final int MODE_CHAMFER = 6;      // 内孔倒角
    public static final int MODE_ODCHAM = 7;       // 外圆倒角（圆柱外缘端面）

    public int mode = MODE_POCKET;      // 加工类型
    public double taperDia = 50;        // 大头直径
    public double taperDiaSmall = 34;   // 小头直径
    public double taperDepth = 38;      // 深度
    public double spiralDia = 50;       // 螺旋铣 圆直径
    public double keyLength = 40;       // 键槽 槽长（含两端圆弧）
    public double keyWidth = 12;        // 键槽 槽宽
    public double toolCornerR = 5;      // 刀尖圆弧半径 R（平底刀填 0）
    public int hNo = 13;                // 刀补号 H
    public double chaDia = 14;          // 内圆倒角: 孔径
    public double chaAngle = 60;        // 内圆倒角: 锥角(全角)
    public double chaDepth = 4;         // 内圆倒角: 倒角深度
    public double chaStep = 0.1;        // 内圆倒角: 每层切深
    public double odDia = 50;           // 外圆倒角: 外圆直径
    public double odAngle = 90;         // 外圆倒角: 锥角(全角)
    public double odDepth = 2;          // 外圆倒角: 倒角深
    public double odStep = 0.1;         // 外圆倒角: 每层切深

    public int cornerType = CORNER_R;
    public double cornerValue = 8;
    public double toolDia = 12;
    public double stepDown = 3;
    public double stepOver = 6;
    public int spindle = 2000;
    public int feed = 400;
    public double safeZ = 100;
    public int compNo = 1;
    public boolean compact = true;
    public int coord = 54;   // 工件坐标系 54~59
    public double cx = 0;    // 型腔中心 X
    public double cy = 0;    // 型腔中心 Y

    double toolRadius() { return toolDia / 2.0; }

    String check() {
        StringBuilder sb = new StringBuilder();
        if (mode == MODE_TAPER) return checkTaper();
        if (mode == MODE_FACE) return checkFace();
        if (mode == MODE_SPIRAL) return checkSpiral();
        if (mode == MODE_KEY) return checkKey();
        if (mode == MODE_OUTER) return checkOuter();
        if (mode == MODE_CHAMFER) return checkChamfer();
        if (mode == MODE_ODCHAM) return checkODCham();
        if (length <= 0 || width <= 0 || depth <= 0) sb.append("长宽深必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (toolDia >= Math.min(length, width)) sb.append("刀具直径必须小于型腔最小边\n");
        if (stepDown <= 0) sb.append("每层切深必须大于 0\n");
        if (cornerType != CORNER_SQUARE && cornerValue <= 0) sb.append("R/C 值必须大于 0，或选直角\n");
        if (cornerType == CORNER_R && cornerValue < toolRadius())
            sb.append("圆角 R 小于刀具半径，壁面一刀切不到，需换小刀或先清角\n");
        if (cornerType == CORNER_C && cornerValue > Math.min(length, width) / 2.0)
            sb.append("倒角 C 过大\n");
        if (stepOver <= 0 || stepOver > toolDia) sb.append("行距应在 0 到刀具直径之间\n");
        return sb.toString().trim();
    }

    String checkTaper() {
        StringBuilder sb = new StringBuilder();
        if (taperDia <= 0 || taperDiaSmall <= 0) sb.append("大头/小头必须大于 0\n");
        if (taperDia <= taperDiaSmall) sb.append("大头必须大于小头\n");
        if (taperDepth <= 0) sb.append("深度必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (toolCornerR < 0 || toolCornerR > toolRadius())
            sb.append("刀尖 R 不能大于刀具半径（平底刀填 0）\n");
        if (toolRadius() >= taperDiaSmall / 2.0)
            sb.append("刀具半径大于小头半径，下不到底，需换小刀\n");
        if (stepDown <= 0) sb.append("每层切深必须大于 0\n");
        return sb.toString().trim();
    }

    String checkFace() {
        StringBuilder sb = new StringBuilder();
        if (length <= 0 || width <= 0) sb.append("长宽必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (depth <= 0) sb.append("要去掉的总深度必须大于 0\n");
        if (stepDown <= 0) sb.append("每层切深必须大于 0\n");
        if (stepDown > depth + 1e-9) sb.append("每层切深大于总深度，改小一点\n");
        return sb.toString().trim();
    }

    String checkChamfer() {
        StringBuilder sb = new StringBuilder();
        double topDia = chaDia + 2 * chaDepth * Math.tan(Math.toRadians(chaAngle / 2));
        if (chaDia <= 0) sb.append("孔径必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (toolDia >= chaDia) sb.append("刀具直径必须小于孔径，否则刀进不去\n");
        if (toolDia >= topDia) sb.append("刀太大，放到顶口也套不进去，换小刀或减小锥角\n");
        if (chaDepth <= 0) sb.append("倒角深度必须大于 0\n");
        if (chaAngle <= 1 || chaAngle >= 179) sb.append("锥角应在 1~179 度之间（按图纸全角填）\n");
        if (chaStep <= 0) sb.append("每层切深必须大于 0\n");
        if (chaStep > chaDepth + 1e-9) sb.append("每层切深大于总深度，改小一点\n");
        return sb.toString().trim();
    }

    String checkODCham() {
        StringBuilder sb = new StringBuilder();
        double half = Math.toRadians(odAngle / 2);
        double w = odDepth * Math.tan(half);
        if (odDia <= 0) sb.append("外圆直径必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (toolDia >= odDia) sb.append("刀具直径必须小于外圆直径，否则整个盖面都会被切\n");
        if (odDepth <= 0) sb.append("倒角深必须大于 0\n");
        if (odAngle <= 1 || odAngle >= 179) sb.append("锥角应在 1~179 度之间（按图纸全角填）\n");
        if (odStep <= 0) sb.append("每层切深必须大于 0\n");
        if (odStep > odDepth + 1e-9) sb.append("每层切深大于倒角深，改小一点\n");
        if (w >= odDia / 2.0) sb.append("倒角宽超过外圆半径，改小倒角深或锥角\n");
        return sb.toString().trim();
    }

    String checkSpiral() {
        StringBuilder sb = new StringBuilder();
        if (spiralDia <= 0) sb.append("圆直径必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (toolDia >= spiralDia) sb.append("刀具直径必须小于圆直径\n");
        if (depth <= 0) sb.append("要去掉的总深度必须大于 0\n");
        if (stepDown <= 0) sb.append("每圈下刀量必须大于 0\n");
        if (stepDown > depth + 1e-9) sb.append("每圈下刀量大于总深度，改小一点\n");
        return sb.toString().trim();
    }

    // 各模式的新手使用说明（App 里显示在程序下方）
    public String manual() {
        StringBuilder sb = new StringBuilder();
        if (mode == MODE_CHAMFER) {
            sb.append("【干什么用】\n给孔口铣一圈锥面倒角（图纸上标 60°、90° 的那种）。"
                    + "用一把平底铣刀，刀心在孔里一圈一圈往外挪，每层只下 0.1，\n"
                    + "下几十层就把锥面一刀一刀叠出来。螺纹孔、销孔的口部倒角都用这个。\n\n");
            sb.append("【刀要多大】\n必须比孔小：Ø14 的孔最多用 Ø12 的刀，Ø10 最稳。"
                    + "刀比孔大，连孔都进不去，程序会直接报警不给算。\n\n");
            sb.append("【程序里几个数怎么改】\n");
            sb.append("#1 孔径：图纸上孔的名义尺寸，Ø14 就填 14。\n");
            sb.append("#2 刀径：实际装上去的铣刀直径。\n");
            sb.append("#3 倒角深：从工件上表面往下倒多深。图纸标 4 就填 4。\n");
            sb.append("#4 每层：每圈往下吃多少。0.1 很稳，赶时间可 0.2；想更光可 0.05。\n");
            sb.append("#5 锥角：填图纸上标的角度，注意是【全角】。标 60° 填 60，标 90° 填 90。\n");
            sb.append("#6 下刀进给、#7 圆周进给：材料硬就把 #7 调小。\n\n");
            sb.append("【倒角尺寸怎么核对】\n顶口直径 = 孔径 + 2 × 倒角深 × tan(锥角/2)。\n"
                    + "例：Ø14 孔、深 4、60° → 顶口约 Ø18.62，正好比 M16 螺纹大一圈。"
                    + "如果图纸那个倒角只倒到 M16 大径（Ø16），深其实只有 1.7 左右，把 #3 改成 1.7。\n\n");
            sb.append("【为什么第一刀比后面多切一点】\n第一刀的半径是按“工件上表面”算的，"
                    + "所以正好把顶面那一圈切干净，倒角边齐平、不留薄边。\n\n");
            sb.append("【上机注意】\n");
            sb.append("1. Z0 要打在工件上表面，X0Y0 是孔中心（用 G52 平移过去了，不用改坐标）。\n");
            sb.append("2. 孔必须先打穿或至少深过倒角，否则刀会在孔底顶到余料。\n");
            sb.append("3. 倒角面是一层层叠出来的，刀纹是细台阶，想很光就把 #4 改 0.05 再走一遍。\n");
        }
        if (mode == MODE_ODCHAM) {
            sb.append("【干什么用】\n给圆柱（圆盘、凸台）的外圈顶边倒角。刀在工件外面贴着外圆绕整圆，每层往里收一点点，一层层把外圈那圈锥面叠出来。\n\n");
            sb.append("【刀要多大】\n必须比外圆小，否则整个盖面都被切平了。常用 Ø10~Ø12。\n\n");
            sb.append("【程序里几个数怎么改】\n#1 外圆直径、#2 刀径、#3 倒角深、#4 每层（0.1 最稳）、#5 锥角（全角，常见 90°、45°）、#6 下刀进给、#7 圆周进给。\n\n");
            sb.append("【倒角宽怎么核对】\n倒角宽 = 倒角深 × tan(锥角/2)；顶口直径 = 外圆 − 2 × 倒角宽。例：Ø50、倒角深 2、90° → 宽 2、顶口 Ø46。\n\n");
            sb.append("【上机注意】\n1. Z0 打在工件上表面，X0Y0 是外圆圆心\n2. 第一刀在工件上方先抬到安全高度，逐层往下降，刀始终在外侧，不会撞件\n3. 外圆如果不是整圆（有缺口、有键槽），这段程序会把缺口处也切一刀，先确认再上机\n4. 想更光：每层改 0.05，末层再空走一圈");
            return sb.toString();
        }
        if (mode == MODE_TAPER) {
            sb.append("【干什么用】\n铣 1:N 锥度的圆孔。刀具从大头中心下刀，一圈一圈往下扩，逐层把锥面铣出来。\n\n");
            sb.append("【上机前必须做】\n1. Z0 对在工件顶面（不是台面、不是毛坯底面）\n2. G54 的 X0 Y0 对在锥孔中心，程序会自动 G52 平移\n3. 刀具实际直径、刀补号 H 要和程序一致\n\n");
            sb.append("【可以改的变量】\n#1 = 小头直径\n#2 = 大头直径\n#3 = 半角（度）\n#4 = 刀具直径\n#5 = 刀尖 R（平底刀填 0，球刀填 R 值）\n#16 = 每层深度\n#21 = 总深\n#9 = 进给\n\n");
            sb.append("【不用管的变量】\n#6 当前深度、#11 大头半径、#7 刀尖R补偿、#8 Z向补偿、#12 刀心半径、#13 下刀 Z 都是程序自己算的。\n\n");
            sb.append("【改法举例】\n想把小头改到 30：只改 #1=30。\n想每层切 1.5：改 #16=1.5。\n改了大头或小头后，半角 #3 要重新算：\n#3 = ATAN[(大头-小头)/2/总深]\n\n");
            sb.append("【注意】\n- 刀半径不能大于小头半径，否则下不到底，程序会让你换小刀\n- #12 那行有 IF 保护，刀心半径算出来小于 0 时会自动取 0.001，防止 I 值为负报警\n- 走刀方向是 G3（逆时针），想改顺铣要改成 G2，I 值同时变正号");
            return sb.toString();
        }
        if (mode == MODE_KEY) {
            sb.append("【干什么用】\n键槽。每一层从上方直接落刀，沿槽下壁走到右端 → G3 铣右端 R → 沿上壁走回左端 → G3 铣左端 R，一个闭合的往复就铣完一层，再落下一层。两端 R 是 G3 单独铣出来的，不靠刀带。\n\n");
            sb.append("【上机前必须做】\n1. Z0 对在工件顶面\n2. G54 的 X0 Y0 对在键槽中心（槽长的中点），程序自动 G52 平移\n3. 刀径按实际填，槽宽/行程都是靠它算的\n\n");
            sb.append("【可以改的变量】\n#1 = 槽长（含两端圆弧的总长）\n#2 = 槽宽\n#3 = 刀具直径\n#4 = 总深\n#5 = 每层切深\n#6 = 起始 Z\n#7 = 终点 Z（自动=-#4）\n\n");
            sb.append("【自动算的】\n#8 = (槽长-槽宽)/2，两端圆弧的圆心 X\n#9 = 槽宽/2 - 刀径/2，端弧的刀心半径（R 减去刀半径）\n#13 = 当前 Z\n\n");
            sb.append("【改法举例】\n槽 40×12 深 5、用 Ø10 刀：\n#1=40  #2=12  #3=10 → #8=14，两端圆心在 ±14；#9=1，端弧刀心半径 1，一刀往复就铣满 12 宽\n槽 40×20 深 5、用 Ø12 刀：\n#2=20  #3=12 → #9=4，两刀（±4）正好盖满 20 宽\n\n");
            sb.append("【注意】\n- 刀径必须小于槽宽，两个 G3 的 R 才铣得出来；刀径等于槽宽时 R 只剩刀半径，等于没 R\n- 刀径要 ≥ 槽宽的一半，一个往复才盖满整宽；比一半还小中间会留料\n- 两个 G3 绝对不能删：G3 Y#9 I0. J#9 是右端，G3 Y-#9 I0. J-#9 是左端\n- 每层 #5 建议 ≤1mm（键槽刀可直扎）；用普通立铣刀请减到 0.3\n- 槽长 #1 是含两端圆弧的总长，不是直线段长度");
            return sb.toString();
        }
        if (mode == MODE_FACE) {
            sb.append("【干什么用】\n铣平面。X 向一刀一刀往复，每一层走完整幅面再下一层，适合毛坯飞面、去黑皮。\n\n");
            sb.append("【上机前必须做】\n1. Z0 对在工件顶面\n2. G54 的 X0 Y0 对在矩形中心，程序会自动 G52 平移\n3. 刀具直径要填真实值，行距是按它自动算的\n\n");
            sb.append("【可以改的变量】\n#1 = 长（X 方向）\n#2 = 宽（Y 方向）\n#3 = 刀具直径\n#4 = 起始 Z（默认 0，从顶面开始）\n#5 = 终点 Z（负值，铣到多深就写多少）\n#6 = 每层切深\n\n");
            sb.append("【自动算的】\n#7 半长、#8 半宽、#9 行距（=75% 刀径）、#10 方向、#11 当前Z、#12 X位置\n\n");
            sb.append("【改法举例】\n毛坯要飞掉 2mm，每刀 0.5：\n#5=-2.  #6=0.5\n行距想更密，把 #9 那行改成 #9=[#3*0.6]\n\n");
            sb.append("【注意】\n- #5 必须比 #4 小（更负），否则循环一次都不进，程序空跑\n- 每一趟都先抬到 [#11+2] 再定位，不在材料里横着快走\n- 最后一层如果除不尽，会自动落到 #5，不会多切");
            return sb.toString();
        }
        if (mode == MODE_SPIRAL) {
            sb.append("【干什么用】\n螺旋铣圆形面或圆孔。刀具在刀心圆上一边走 G3 一边下降，从工件上方直接螺旋下刀，不用先扎到 Z0 再开始。每圈吃一层，Z 连续到底。\n\n");
            sb.append("【上机前必须做】\n1. Z0 对在工件顶面\n2. G54 的 X0 Y0 对在圆心，程序会自动 G52 平移\n3. 刀具直径填真实值——刀心圆半径就是靠它算的\n\n");
            sb.append("【可以改的变量】\n#1 = 圆直径（要铣的圆）\n#2 = 刀具直径\n#3 = 工件表面 Z（一般写 0）\n#4 = 终点 Z（负值）\n#5 = 每圈下刀量\n\n");
            sb.append("【自动算的】\n#6 = 刀心圆半径 =（圆直径-刀径）/2\n#7 = 当前 Z\n\n");
            sb.append("【改法举例】\nØ50 的圆用 Ø30 刀：\n#1=50  #2=30 → 刀心半径自动 10\n和手工写的 G1 X-10.78 / G3 I10.78 是同一个意思，这个程序会自动算出来。\n\n");
            sb.append("【注意】\n- 刀具直径必须小于圆直径，等于或大于程序会拦下来\n- 每圈下刀量别超过刀尖强度，#5 建议 0.3~0.6\n- 下刀靠 G0 Z[#3+2.] + 后面整段 G3，全程螺旋，没有直插；照抄时别把它改回 G1 Z0\n- 想顺铣把 G3 改成 G2，同时 #6 前面加负号（G2 I-#6）");
            return sb.toString();
        }
        if (mode == MODE_OUTER) {
            sb.append("【干什么用】\n只铣外形。刀偏在工件轮廓外面，一圈一圈贴着外形往下走，把 长×宽 的方料修成外形（落料、修边都行）。每层走一圈，走到总深为止。\n\n");
            sb.append("【上机前必须做】\n1. Z0 对在工件顶面\n2. G54 的 X0 Y0 对在工件中心（程序自动 G52 平移）\n3. 刀补号 D 和 H 要填真实号，别写死\n4. 先在机床上空跑一次，确认 G41 让刀偏在工件外侧，偏里面就是方向反了\n\n");
            sb.append("【可以改的变量】\n#1 = 工件长\n#2 = 工件宽\n#3 = 刀具直径\n#4 = 总深\n#5 = 每层切深\n#6 = 工件表面 Z（一般 0）\n#7 = 终点 Z（自动=-#4）\n\n");
            sb.append("【自动算的】\n#8 = 刀半径 + 2，起刀点离开工件的距离\n#9 = 当前 Z\n\n");
            sb.append("【改法举例】\n外形 120×80、深 10、每层 3、Ø12 刀：\n#1=120  #2=80  #4=10  #5=3  #3=12\n想一次少切点就把 #5 改 2\n\n");
            sb.append("【注意】\n- G41 是左刀补，程序是顺时针绕，刀才落在工件外侧；改成逆时针就必须换 G42\n- 退刀前必须有 G40，不然下一段还带着刀补\n- 每层别超过刀径的 60%，侧刃吃太多会震刀\n- 刀径大于工件最小边时，拐角会让刀让不过来，换小刀或加 R");
            return sb.toString();
        }
        sb.append("【干什么用】\n铣方形型腔，可做 R 圆角或 C 倒角。先分层粗铣把中间掏空，最后 G41 刀补精修一圈侧壁。\n\n");
        sb.append("【上机前必须做】\n1. Z0 对在工件顶面\n2. G54 的 X0 Y0 对在型腔中心，程序自动 G52 平移\n3. 刀补号 H（G43）和 D（G41）要用真实刀补号，别写死 D1\n\n");
        sb.append("【可以改的变量】\n#20 = 半长（长的一半，直接写数值）\n#21 = 半宽\n#22 = 刀具半径\n#3 = 总深\n#4 = 圆角 R 或倒角 C（直角就写 0）\n#6 = 每层切深\n#7 = 行距\n#9 = 进给\n#10 = 安全高度\n\n");
        sb.append("【自动算的】\n#23 当前深度、#24 环号、#27 环半长、#28 环半宽、#29 环圆角、#30 内缩量\n\n");
        sb.append("【改法举例】\n120×80 的腔、R8、Ø12 刀：\n#20=60  #21=40  #22=6  #4=8\n行距想细一点：#7 改成 5（别超过 #22 的两倍）\n\n");
        sb.append("【注意】\n- 刀具半径大于圆角 R 时，角上铣不出来，要换小刀清角\n- 行距 #7 大于刀径会留台阶\n- 精修段有 G41，上机前先在机床上空跑校验刀补方向\n- 程序里 #29 有 IF 保护，圆角算成负数会取 0.001，不会报警停机");
        return sb.toString();
    }

    String checkKey() {
        StringBuilder sb = new StringBuilder();
        if (keyLength <= 0) sb.append("槽长必须大于 0\n");
        if (keyWidth <= 0) sb.append("槽宽必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (toolDia > keyWidth) sb.append("刀径不能大于槽宽，否则铣出来比槽宽\n");
        if (toolDia > keyLength) sb.append("刀径不能大于槽长\n");
        if (depth <= 0) sb.append("总深必须大于 0\n");
        if (stepDown <= 0) sb.append("每层切深必须大于 0\n");
        if (stepDown > depth + 1e-9) sb.append("每层切深大于总深，改小一点\n");
        if (toolDia < keyWidth / 2.0)
            sb.append("刀径小于槽宽一半，往复两刀中间会留料，建议换大一点的刀或先开粗\n");
        return sb.toString().trim();
    }

    String checkOuter() {
        StringBuilder sb = new StringBuilder();
        if (length <= 0 || width <= 0) sb.append("工件长宽必须大于 0\n");
        if (toolDia <= 0) sb.append("刀具直径必须大于 0\n");
        if (depth <= 0) sb.append("总深必须大于 0\n");
        if (stepDown <= 0) sb.append("每层切深必须大于 0\n");
        if (stepDown > depth + 1e-9) sb.append("每层切深大于总深，改小一点\n");
        if (stepDown > toolDia * 0.6) sb.append("每层切深超过刀径 60%，外形侧铣吃得太多，改小一点\n");
        if (cornerType != CORNER_SQUARE && cornerValue <= 0) sb.append("R/C 值必须大于 0，或选直角\n");
        if (cornerType != CORNER_SQUARE && cornerValue >= Math.min(length, width) / 2.0)
            sb.append("R/C 值不能大于工件最小边的一半\n");
        return sb.toString().trim();
    }

    private String generateOuter() {
        StringBuilder out = new StringBuilder();
        out.append("%\n");
        out.append("O1006 (铣外方形)\n");
        out.append("G17 G21 G40 G49 G80 G90 G" + coord + "\n");
        out.append("G52 X" + f(cx, 3) + " Y" + f(cy, 3) + " (平移到工件中心)\n");
        out.append("G43 H" + hNo + " Z" + f(safeZ, 1) + "\n");
        out.append("M3 S" + spindle + "\n");
        out.append("M8\n");
        out.append("#1=" + f(length, 1) + " (工件长)\n");
        out.append("#2=" + f(width, 1) + " (工件宽)\n");
        out.append("#3=" + f(toolDia, 1) + " (刀具直径)\n");
        out.append("#4=" + f(cornerType == CORNER_SQUARE ? 0 : cornerValue, 3)
                + (cornerType == CORNER_C ? " (倒角C，直角写0)\n" : " (圆角R，直角写0)\n"));
        out.append("#5=" + f(depth, 3) + " (总深)\n");
        out.append("#6=" + f(stepDown, 2) + " (每层)\n");
        out.append("#7=0 (工件表面Z)\n");
        out.append("#8=-#5 (终点Z)\n");
        out.append("#9=[#3/2.+2.] (起刀让量)\n");
        out.append("#10=[#1/2.] (半长)\n");
        out.append("#11=[#2/2.] (半宽)\n");
        out.append("#12=[#10-#4] (角起点X)\n");
        out.append("#13=#7 (当前Z)\n");
        out.append("WHILE[#13GT#8]DO1\n");
        out.append("#13=#13-#6\n");
        out.append("IF[#13LT#8]THEN#13=#8\n");
        out.append("G0 Z[#13+2.] (抬到本层上方2mm)\n");
        out.append("G0 X-[#10+#9] Y[#11+#9] (到左上角外侧)\n");
        out.append("G1 Z#13 F" + (feed / 2) + " (落刀到本层)\n");
        out.append("G41 D" + hNo + " G1 X-#12 Y#11 F" + feed + " (左刀补切入，刀在轮廓外)\n");
        out.append("G1 X#12 F" + feed + " (上边 → 右上角)\n");
        if (cornerType == CORNER_R) {
            out.append("G2 X#10 Y[#11-#4] R#4 F" + feed + " (右上圆角 R)\n");
            out.append("G1 Y-[#11-#4] F" + feed + " (右边)\n");
            out.append("G2 X#12 Y-#11 R#4 F" + feed + " (右下圆角 R)\n");
            out.append("G1 X-#12 F" + feed + " (下边 → 左下角)\n");
            out.append("G2 X-#10 Y-[#11-#4] R#4 F" + feed + " (左下圆角 R)\n");
            out.append("G1 Y[#11-#4] F" + feed + " (左边)\n");
            out.append("G2 X-#12 Y#11 R#4 F" + feed + " (左上圆角 R)\n");
        } else {
            out.append("G1 X#10 Y[#11-#4] F" + feed + " (右上倒角 C)\n");
            out.append("G1 Y-[#11-#4] F" + feed + " (右边)\n");
            out.append("G1 X#12 Y-#11 F" + feed + " (右下倒角 C)\n");
            out.append("G1 X-#12 F" + feed + " (下边 → 左下角)\n");
            out.append("G1 X-#10 Y-[#11-#4] F" + feed + " (左下倒角 C)\n");
            out.append("G1 Y[#11-#4] F" + feed + " (左边)\n");
            out.append("G1 X-#12 Y#11 F" + feed + " (左上倒角 C)\n");
        }
        out.append("G40 G1 X-[#10+#9] Y[#11+#9] F" + feed + " (取消刀补退刀)\n");
        out.append("END1\n");
        out.append("G0 Z" + f(safeZ, 1) + "\n");
        out.append("G52 X0 Y0\n");
        out.append("M5\n");
        out.append("M9\n");
        out.append("G28 G91 Z0\n");
        out.append("G28 G91 Y0\n");
        out.append("G90\n");
        out.append("M30\n");
        out.append("%");
        String r = out.toString();
        return r.endsWith("\n") ? r.substring(0, r.length() - 1) : r;
    }

    static String f(double v, int digits) {
        DecimalFormatSymbols sym = new DecimalFormatSymbols(Locale.US);
        StringBuilder p = new StringBuilder();
        for (int i = 0; i < digits; i++) p.append('0');
        DecimalFormat df = new DecimalFormat("0." + p, sym);
        df.setGroupingUsed(false);
        return df.format(v);
    }

    public String generate() {
        if (mode == MODE_TAPER) return generateTaper();
        if (mode == MODE_FACE) return generateFace();
        if (mode == MODE_SPIRAL) return generateSpiral();
        if (mode == MODE_KEY) return generateKey();
        if (mode == MODE_OUTER) return generateOuter();
        if (mode == MODE_CHAMFER) return generateChamfer();
        if (mode == MODE_ODCHAM) return generateODCham();
        List<String> L = new ArrayList<>();
        L.add("%");
        L.add("O1001 (型腔宏程序)");
        L.add("( 长=" + f(length, 3) + " 宽=" + f(width, 3) + " 深=" + f(depth, 3) + " )");
        L.add("( 四角=" + cornerDesc() + " 刀具=" + f(toolDia, 3) + " )");
        L.add("( 切深=" + f(stepDown, 3) + " 行距=" + f(stepOver, 3) + " 转速=" + spindle + " 进给=" + feed + " )");
        L.add("( 坐标 G" + coord + "  中心X=" + f(cx, 3) + " 中心Y=" + f(cy, 3) + "  Z0=工件顶面 )");
        L.add("( 由 MacroGen 生成 上机前请核对 )");
        L.add("");
        L.add("G17 G21 G40 G49 G80 G90 G" + coord);
        L.add("#31=" + f(cx, 3) + " (中心X)");
        L.add("#32=" + f(cy, 3) + " (中心Y)");
        L.add("G52 X#31 Y#32 (平移到型腔中心)");
        L.add("G43 H" + hNo + " Z" + f(safeZ, 3));
        L.add("M3 S" + spindle);
        L.add("M8");
        L.add("");
        L.add("#20=" + f(length / 2, 3) + " (半长)");
        L.add("#21=" + f(width / 2, 3) + " (半宽)");
        L.add("#22=" + f(toolDia / 2, 3) + " (刀具半径)");
        L.add("#3=" + f(depth, 3) + " (深)");
        L.add("#4=" + f(cornerValue, 3) + " (圆角或倒角)");
        L.add("#6=" + f(stepDown, 3) + " (每层切深)");
        L.add("#7=" + f(stepOver, 3) + " (行距)");
        L.add("#9=" + feed + " (进给)");
        L.add("#10=" + f(safeZ, 3) + " (安全高度)");
        L.add("#23=0. (当前深度)");
        L.add("");
        L.add("( === 分层粗铣 === )");
        L.add("WHILE[#23LT#3]DO1");
        L.add("#23=#23+#6");
        L.add("IF[#23GT#3]THEN#23=#3");
        L.add("#26=-#23");
        L.add("( 斜插下刀 )");
        L.add("G00 X0 Y0");
        L.add("G01 Z[#26+1.5] F[#9]");
        L.add("G01 X[#20/3.] Z#26 F[#9/2.]");
        L.add("#24=0 (环号)");
        L.add("WHILE[[#22+#24*#7]LE[#21-0.5]]DO2");
        L.add("#30=[#22+#24*#7] (内缩量)");
        L.add("#27=[#20-#30] (环半长)");
        L.add("#28=[#21-#30] (环半宽)");
        L.add("#29=[#4-#30] (环圆角)");
        L.add("IF[#29LT0.]THEN#29=0.");
        if (cornerType == CORNER_R) L.add("IF[#29LT0.001]THEN#29=0.001");
        L.add("#24=#24+1");
        if (compact) {
            L.addAll(ringBlocksCompact(false));
        } else {
            L.addAll(ringBlocks("G01 X#27 Y0 F[#9]"));
        }
        L.add("END2");
        L.add("END1");
        L.add("");
        L.add("( === 精修壁面 G41 === )");
        L.add("#27=#20");
        L.add("#28=#21");
        L.add("#29=#4");
        L.add("G00 Z[#26+2.] (抬到本层上方，刀仍在腔内)");
        L.add("G00 X0 Y0 (回腔中心，别往壁里冲)");
        L.add("G01 Z#26 F[#9]");
        L.add("G41 D" + hNo + " G01 X#27 Y0 F[#9]");
        if (compact) {
            L.addAll(ringBlocksCompact(true));
        } else {
            L.addAll(ringBlocks(null));
        }
        L.add("G40 G01 X0 Y0 F[#9] (退回腔中心再抬刀)");
        L.add("G00 Z#10");
        L.add("G52 X0 Y0 (取消局部坐标)");
        L.add("M5");
        L.add("M9");
        L.add("G28 G91 Z0");
        L.add("G28 G91 Y0");
        L.add("G90");
        L.add("M30");
        L.add("%");

        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < L.size(); i++) {
            String line = L.get(i);
            line = line.trim();
            if (line.isEmpty()) continue;
            sb.append(line);
            if (i < L.size() - 1) sb.append("\n");
        }
        String out = sb.toString();
        return out.endsWith("\n") ? out.substring(0, out.length() - 1) : out;
    }

    /** 锥孔：照机床常用写法，G43/M8/整圆 G3 I-，R 角刀带补偿 */
    private String generateTaper() {
        double r1 = taperDia / 2.0;
        double r2 = taperDiaSmall / 2.0;
        double halfAngle = Math.toDegrees(Math.atan((r1 - r2) / taperDepth));
        double taperN = taperDepth / (taperDia - taperDiaSmall);
        double fullAngle = halfAngle * 2;

        List<String> L = new ArrayList<>();
        L.add("%");
        L.add("O1002(锥孔)");
        L.add("( 小头" + f(taperDiaSmall, 3) + " 大头" + f(taperDia, 3) + " 深" + f(taperDepth, 3) + " )");
        L.add("( 半角" + f(halfAngle, 3) + " 锥度1:" + f(taperN, 2) + " 全角" + f(fullAngle, 2) + " )");
        L.add("( 刀" + f(toolDia, 3) + " 刀尖R" + f(toolCornerR, 3) + " 层" + f(stepDown, 3) + " )");
        L.add("( G" + coord + " 中心X" + f(cx, 3) + " Y" + f(cy, 3) + " Z0=顶面 )");
        L.add("G17 G" + coord + " G80 G90 G40 G49");
        L.add("#31=" + f(cx, 3) + "(中心X)");
        L.add("#32=" + f(cy, 3) + "(中心Y)");
        L.add("G52 X#31 Y#32");
        L.add("G0 X0 Y0");
        L.add("G43 H" + hNo + " Z" + f(safeZ, 3));
        L.add("M3 S" + spindle);
        L.add("Z10.");
        L.add("M8");
        L.add("");
        L.add("#1=" + f(taperDiaSmall, 3) + "(小头)");
        L.add("#2=" + f(taperDia, 3) + "(大头)");
        L.add("#3=" + f(halfAngle, 4) + "(半角)");
        L.add("#4=" + f(toolDia, 3) + "(刀直径)");
        L.add("#5=" + f(toolCornerR, 3) + "(刀尖R)");
        L.add("#16=" + f(stepDown, 3) + "(层深)");
        L.add("#21=" + f(taperDepth, 3) + "(总深)");
        L.add("#9=" + feed + "(进给)");
        L.add("#6=0(当前深度)");
        L.add("#11=[#2/2.](大头半径)");
        L.add("#7=#5*[1-COS[#3]](刀尖R径向补偿)");
        L.add("#8=#5*SIN[#3]");
        L.add("");
        L.add("WHILE[#6LE#21]DO2");
        L.add("#12=#11+#7-#4/2-#6*TAN[#3](刀心半径)");
        L.add("#13=#8-#5-#6(Z)");
        L.add("IF[#12LT.001]THEN#12=.001");
        L.add("G0 X0 Y0");
        L.add("G1 Z[#13+#5]F[#9/2.]");
        L.add("G1 X#12 F[#9]");
        L.add("G3 I-#12 F[#9]");
        L.add("G1 X0 Y0");
        L.add("#6=#6+#16");
        L.add("END2");
        L.add("");
        L.add("G0 Z" + f(safeZ, 3));
        L.add("G52 X0 Y0");
        L.add("M5");
        L.add("M9");
        L.add("G28 G91 Z0");
        L.add("G28 G91 Y0");
        L.add("G90");
        L.add("M30");
        L.add("%");

        StringBuilder sb = new StringBuilder();
        for (String line : L) {
            if (line.trim().isEmpty()) continue;
            sb.append(line).append("\n");
        }
        String out = sb.toString();
        return out.endsWith("\n") ? out.substring(0, out.length() - 1) : out;
    }

    // 键槽：沿 X 往复分层，槽宽大于刀径时按行距分几行走
    private String generateKey() {
        StringBuilder out = new StringBuilder();
        out.append("%\n");
        out.append("O1005 (键槽宏程序)\n");
        out.append("G17 G21 G40 G49 G80 G90 G" + coord + "\n");
        out.append("G52 X" + f(cx, 3) + " Y" + f(cy, 3) + " (平移到键槽中心)\n");
        out.append("G43 H" + hNo + " Z" + f(safeZ, 1) + "\n");
        out.append("M3 S" + spindle + "\n");
        out.append("M8\n");
        out.append("#1=" + f(keyLength, 1) + " (槽长含圆弧)\n");
        out.append("#2=" + f(keyWidth, 1) + " (槽宽)\n");
        out.append("#3=" + f(toolDia, 1) + " (刀具直径)\n");
        out.append("#4=" + f(depth, 3) + " (总深)\n");
        out.append("#5=" + f(stepDown, 2) + " (每层)\n");
        out.append("#6=0 (工件表面Z)\n");
        out.append("#7=-#4 (终点Z)\n");
        out.append("#8=[#1-#2]/2. (两端圆弧圆心X)\n");
        out.append("#9=[#2/2.-#3/2.] (端弧刀心半径)\n");
        out.append("IF[#9LT0.01]THEN#9=0.01\n");
        out.append("#13=#6 (当前Z)\n");
        out.append("WHILE[#13GT#7]DO1\n");
        out.append("#13=#13-#5\n");
        out.append("IF[#13LT#7]THEN#13=#7\n");
        out.append("G0 Z[#13+2.] (抬到本层上方2mm)\n");
        out.append("G0 X0 Y0 (在槽中心落刀，别贴壁下刀)\n");
        out.append("G1 Z#13 F" + (feed / 2) + " (落刀到本层)\n");
        out.append("G1 X-#8 Y-#9 F" + (feed / 2) + " (切到左端弧起点)\n");
        out.append("G1 X#8 F" + feed + " (下壁走到右端)\n");
        out.append("G3 Y#9 I0. J#9 F" + feed + " (右端圆弧 R)\n");
        out.append("G1 X-#8 F" + feed + " (上壁走回左端)\n");
        out.append("G3 Y-#9 I0. J-#9 F" + feed + " (左端圆弧 R)\n");
        out.append("END1\n");
        out.append("G0 Z" + f(safeZ, 1) + "\n");
        out.append("G52 X0 Y0\n");
        out.append("M5\n");
        out.append("M9\n");
        out.append("G28 G91 Z0\n");
        out.append("G28 G91 Y0\n");
        out.append("G90\n");
        out.append("M30\n");
        out.append("%");
        String r = out.toString();
        return r.endsWith("\n") ? r.substring(0, r.length() - 1) : r;
    }

    // 螺旋铣：圆形面/圆孔，一圈一圈螺旋下刀
    /** 内圆倒角：一把平底刀贴着锥面一圈一圈往下缩，每层切深很小，切出 60°/90° 这类锥口 */
    private String generateChamfer() {
        double topDia = chaDia + 2 * chaDepth * Math.tan(Math.toRadians(chaAngle / 2));
        int plunge = (int) Math.max(50, feed / 3);
        StringBuilder out = new StringBuilder();
        out.append("%\n");
        out.append("O1005 (内圆倒角宏程序)\n");
        out.append("( 孔Ø" + f(chaDia, 2) + "  锥角" + f(chaAngle, 1) + "°  深" + f(chaDepth, 2)
                + "  刀Ø" + f(toolDia, 2) + " )\n");
        out.append("( 顶口Ø" + f(topDia, 2) + "  每层" + f(chaStep, 3)
                + "  中心X=" + f(cx, 2) + " Y=" + f(cy, 2) + " )\n");
        out.append("( Z0=工件上表面  孔要先打穿或至少深过倒角 )\n");
        out.append("( 由 MacroGen 生成 上机前请核对 )\n");
        out.append("G17 G21 G40 G49 G80 G90 G" + coord + "\n");
        boolean shift = Math.abs(cx) > 1e-9 || Math.abs(cy) > 1e-9;
        if (shift) {
            out.append("G52 X" + f(cx, 3) + " Y" + f(cy, 3) + " (平移到孔中心)\n");
        } else {
            out.append("( X0 Y0 就是 G" + coord + " 零点, 不对刀就不用改 )\n");
        }
        out.append("G43 H" + hNo + " Z" + f(safeZ, 1) + "\n");
        out.append("M3 S" + spindle + "\n");
        out.append("M8\n");
        out.append("#1=" + f(chaDia, 2) + " (孔径)\n");
        out.append("#2=" + f(toolDia, 2) + " (刀径)\n");
        out.append("#3=" + f(chaDepth, 2) + " (倒角深)\n");
        out.append("#4=" + f(chaStep, 3) + " (每层)\n");
        out.append("#5=" + f(chaAngle, 1) + " (锥角 全角)\n");
        out.append("#6=" + plunge + " (下刀F)\n");
        out.append("#7=" + feed + " (圆周F)\n");
        out.append("#25=TAN[#5/2.] (半角正切)\n");
        out.append("#26=FIX[#3/#4] (层数,取整防少切一层)\n");
        out.append("#21=[[#1/2.]+[#3*#25]]-[#2/2.] (顶层刀心半径)\n");
        out.append("G0 Z[#3+2.] (先到工件上方)\n");
        out.append("G0 X#21 Y0\n");
        out.append("G1 Z-#4 F#6 (第一刀把顶面那圈也切掉)\n");
        out.append("G2 X-#21 Y0 R#21 F#7 (前半圆, 圆心在X0Y0)\n");
        out.append("G2 X#21 Y0 R#21 F#7 (后半圆)\n");
        out.append("#20=2 (从第二层开始循环)\n");
        out.append("WHILE[#20LE#26]DO1\n");
        out.append("#21=[[#1/2.]+[[#3-[#20*#4]]*#25]]-[#2/2.] (本层刀心半径)\n");
        out.append("G0 Z2. (抬到工件上方再移刀)\n");
        out.append("G0 X#21 Y0\n");
        out.append("G1 Z-[#20*#4] F#6 (下本层)\n");
        out.append("G2 X-#21 Y0 R#21 F#7 (前半圆, 圆心在X0Y0)\n");
        out.append("G2 X#21 Y0 R#21 F#7 (后半圆)\n");
        out.append("#20=#20+1\n");
        out.append("END1\n");
        out.append("G0 Z" + f(safeZ, 1) + "\n");
        if (shift) out.append("G52 X0 Y0\n");
        out.append("M5\n");
        out.append("M9\n");
        out.append("G28 G91 Z0\n");
        out.append("G28 G91 Y0\n");
        out.append("G90\n");
        out.append("M30\n");
        out.append("%");
        String r = out.toString();
        return r.endsWith("\n") ? r.substring(0, r.length() - 1) : r;
    }


    /** 外圆倒角：圆柱外缘端面倒角，刀在外圆外侧绕整圆，逐层向外挪 */
    private String generateODCham() {
        double half = Math.toRadians(odAngle / 2);
        double w = odDepth * Math.tan(half);
        double topDia = odDia - 2 * w;
        int plunge = (int) Math.max(50, feed / 3);
        StringBuilder out = new StringBuilder();
        out.append("%\n");
        out.append("O1007 (外圆倒角宏程序)\n");
        out.append("( 外圆Ø" + f(odDia, 2) + "  锥角" + f(odAngle, 1) + "°  深" + f(odDepth, 2)
                + "  刀Ø" + f(toolDia, 2) + " )\n");
        out.append("( 倒角宽" + f(w, 2) + "  顶口Ø" + f(topDia, 2) + "  每层" + f(odStep, 3)
                + "  中心X=" + f(cx, 2) + " Y=" + f(cy, 2) + " )\n");
        out.append("( Z0=工件上表面  圆柱外缘端面倒角 )\n");
        out.append("( 由 MacroGen 生成 上机前请核对 )\n");
        out.append("G17 G21 G40 G49 G80 G90 G" + coord + "\n");
        boolean shift = Math.abs(cx) > 1e-9 || Math.abs(cy) > 1e-9;
        if (shift) {
            out.append("G52 X" + f(cx, 3) + " Y" + f(cy, 3) + " (平移到圆心)\n");
        } else {
            out.append("( X0 Y0 就是 G" + coord + " 零点, 不对刀就不用改 )\n");
        }
        out.append("G43 H" + hNo + " Z" + f(safeZ, 1) + "\n");
        out.append("M3 S" + spindle + "\n");
        out.append("M8\n");
        out.append("#1=" + f(odDia, 2) + " (外圆直径)\n");
        out.append("#2=" + f(toolDia, 2) + " (刀径)\n");
        out.append("#3=" + f(odDepth, 2) + " (倒角深)\n");
        out.append("#4=" + f(odStep, 3) + " (每层)\n");
        out.append("#5=" + f(odAngle, 1) + " (锥角 全角)\n");
        out.append("#6=" + plunge + " (下刀F)\n");
        out.append("#7=" + feed + " (圆周F)\n");
        out.append("#25=TAN[#5/2.] (半角正切)\n");
        out.append("#26=FIX[#3/#4] (层数)\n");
        out.append("#20=1\n");
        out.append("WHILE[#20LE#26]DO1\n");
        out.append("#21=[[#1/2.]-[[#3-[#20*#4]]*#25]]+[#2/2.] (本层刀心半径)\n");
        out.append("G0 Z2. (抬到工件上方再移刀)\n");
        out.append("G0 X#21 Y0\n");
        out.append("G1 Z-[#20*#4] F#6 (下本层)\n");
        out.append("G3 I-#21 F#7 (整圆, 圆心在X0Y0)\n");
        out.append("#20=#20+1\n");
        out.append("END1\n");
        out.append("G0 Z" + f(safeZ, 1) + "\n");
        if (shift) out.append("G52 X0 Y0\n");
        out.append("M5\n");
        out.append("M9\n");
        out.append("G28 G91 Z0\n");
        out.append("G28 G91 Y0\n");
        out.append("G90\n");
        out.append("M30\n");
        out.append("%");
        String r = out.toString();
        return r.endsWith("\n") ? r.substring(0, r.length() - 1) : r;
    }

    private String generateSpiral() {
        StringBuilder out = new StringBuilder();
        out.append("%\n");
        out.append("O1004 (螺旋铣宏程序)\n");
        out.append("G17 G21 G40 G49 G80 G90 G" + coord + "\n");
        out.append("G52 X" + f(cx, 3) + " Y" + f(cy, 3) + " (平移到圆心)\n");
        out.append("G43 H" + hNo + " Z" + f(safeZ, 1) + "\n");
        out.append("M3 S" + spindle + "\n");
        out.append("M8\n");
        out.append("#1=" + f(spiralDia, 1) + " (圆直径)\n");
        out.append("#2=" + f(toolDia, 1) + " (刀具直径)\n");
        out.append("#3=0 (工件表面Z)\n");
        out.append("#4=" + f(-depth, 3) + " (终点Z)\n");
        out.append("#5=" + f(stepDown, 2) + " (每圈下刀)\n");
        out.append("#6=[#1/2.-#2/2.] (刀心圆半径)\n");
        out.append("IF[#6LT0.01]THEN#6=0.01 (防半径算成 0 或负数)\n");
        out.append("#7=#3 (当前Z)\n");
        out.append("G0 X-#6 Y0 (进到圆上)\n");
        out.append("G0 Z[#3+2.] (只到工件上方2mm，不再直插到Z0)\n");
        out.append("WHILE[#7GT#4]DO1\n");
        out.append("#7=#7-#5\n");
        out.append("IF[#7LT#4]THEN#7=#4\n");
        out.append("G3 I#6 Z#7 F" + feed + "\n");
        out.append("END1\n");
        out.append("G0 Z" + f(safeZ, 1) + "\n");
        out.append("G52 X0 Y0\n");
        out.append("M5\n");
        out.append("M9\n");
        out.append("G28 G91 Z0\n");
        out.append("G28 G91 Y0\n");
        out.append("G90\n");
        out.append("M30\n");
        out.append("%");
        String r = out.toString();
        return r.endsWith("\n") ? r.substring(0, r.length() - 1) : r;
    }

    // 铣飞面：长宽刀径、起止Z、每层都可改，Z0 起刀逐层往复
    private String generateFace() {
        StringBuilder out = new StringBuilder();
        out.append("%\n");
        out.append("O1003 (飞面宏程序)\n");
        out.append("G17 G21 G40 G49 G80 G90 G" + coord + "\n");
        out.append("G52 X" + f(cx, 3) + " Y" + f(cy, 3) + " (平移到平面中心)\n");
        out.append("G43 H" + hNo + " Z" + f(safeZ, 1) + "\n");
        out.append("M3 S" + spindle + "\n");
        out.append("M8\n");
        out.append("#1=" + f(length, 1) + " (长)\n");
        out.append("#2=" + f(width, 1) + " (宽)\n");
        out.append("#3=" + f(toolDia, 1) + " (刀具直径)\n");
        out.append("#4=0 (起始Z)\n");
        out.append("#5=" + f(-depth, 3) + " (终点Z)\n");
        out.append("#6=" + f(stepDown, 2) + " (每层)\n");
        out.append("#7=[#1/2.+#3/2.] (半长+刀半径，刀心走出工件边缘)\n");
        out.append("#8=[#2/2.+#3/2.] (半宽+刀半径，进出刀都在料外)\n");
        out.append("#9=[#3*0.75] (行距)\n");
        out.append("#10=1 (方向)\n");
        out.append("#11=#4 (当前Z)\n");
        out.append("WHILE[#11GT#5]DO1\n");
        out.append("#11=#11-#6\n");
        out.append("IF[#11LT#5]THEN#11=#5\n");
        out.append("#12=-#7 (X起点)\n");
        out.append("WHILE[#12LE#7]DO2\n");
        out.append("G0 Z[#4+2.] (抬到工件表面上方2mm再横移)\n");
        out.append("G0 X#12 Y[#8*#10]\n");
        out.append("G0 Z[#11+0.5]\n");
        out.append("G1 Z#11 F" + (feed / 2) + "\n");
        out.append("G1 Y[-#8*#10] F" + feed + "\n");
        out.append("#10=-#10\n");
        out.append("#12=#12+#9\n");
        out.append("END2\n");
        out.append("END1\n");
        out.append("G0 Z" + f(safeZ, 1) + "\n");
        out.append("G52 X0 Y0\n");
        out.append("M5\n");
        out.append("M9\n");
        out.append("G28 G91 Z0\n");
        out.append("G28 G91 Y0\n");
        out.append("G90\n");
        out.append("M30\n");
        out.append("%");
        String r = out.toString();
        return r.endsWith("\n") ? r.substring(0, r.length() - 1) : r;
    }

    private String cornerDesc() {
        if (cornerType == CORNER_R) return "R" + f(cornerValue, 2);
        if (cornerType == CORNER_C) return "C" + f(cornerValue, 2);
        return "NONE";
    }

    /** 用 FANUC 自动倒圆/倒角语法 ,R / ,C 压缩轮廓 */
    private List<String> ringBlocksCompact(boolean skipFirst) {
        List<String> out = new ArrayList<>();
        String sfx;
        if (cornerType == CORNER_R) sfx = ",R[#29]";
        else if (cornerType == CORNER_C) sfx = ",C[#29]";
        else sfx = "";
        if (!skipFirst) out.add("G01X#27Y0F[#9]");
        out.add("G01X#27Y#28" + sfx);
        out.add("G01X[-#27]Y#28" + sfx);
        out.add("G01X[-#27]Y[-#28]" + sfx);
        out.add("G01X#27Y[-#28]" + sfx);
        out.add("G01X#27Y0" + sfx);
        return out;
    }

    private List<String> ringBlocks(String approach) {
        List<String> out = new ArrayList<>();
        if (approach != null) out.add(approach);
        if (cornerType == CORNER_R) {
            out.add("G01 Y[#28-#29]");
            out.add("G03 X[#27-#29] Y#28 R#29");
            out.add("G01 X[#29-#27]");
            out.add("G03 X[-#27] Y[#28-#29] R#29");
            out.add("G01 Y[#29-#28]");
            out.add("G03 X[#29-#27] Y[-#28] R#29");
            out.add("G01 X[#27-#29]");
            out.add("G03 X#27 Y[#29-#28] R#29");
            out.add("G01 Y0");
        } else if (cornerType == CORNER_C) {
            out.add("G01 Y[#28-#29]");
            out.add("G01 X[#27-#29] Y#28");
            out.add("G01 X[#29-#27]");
            out.add("G01 X[-#27] Y[#28-#29]");
            out.add("G01 Y[#29-#28]");
            out.add("G01 X[#29-#27] Y[-#28]");
            out.add("G01 X[#27-#29]");
            out.add("G01 X#27 Y[#29-#28]");
            out.add("G01 Y0");
        } else {
            out.add("G01 Y#28");
            out.add("G01 X[-#27]");
            out.add("G01 Y[-#28]");
            out.add("G01 X#27");
            out.add("G01 Y0");
        }
        return out;
    }
}
