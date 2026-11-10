package com.sqc.macrogen;

import android.app.Activity;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.widget.EditText;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** 编程代码大全：G/M 代码与其他常用指令的中文讲解，供新手查阅 */
public class CodeRefActivity extends Activity {

    private static final Object[][] G_CODES = {
            {"G00", "快速定位", "刀具以机床设定的最快速度移到目标点，不切削。例：G00 X100 Y50 Z100。\n下刀前必须先 G00 抬到安全高度，再动 XY。"},
            {"G01", "直线插补", "按 F 设定的进给速度走直线，切削主力。\n例：G01 Z-3. F400（下刀 3mm）；G01 X120. F400（铣一条直线）。"},
            {"G02", "顺时针圆弧", "走顺时针圆弧。写法两种：\n① G02 X终点 Y终点 R半径（R 为负表示大于半圆的弧）\n② G02 X终点 Y终点 I圆心到起点X J圆心到起点Y\n整圆只写圆心偏移：G02 I-10."},
            {"G03", "逆时针圆弧", "走逆时针圆弧，写法同 G02。\n螺旋铣、锥孔就是靠它：G03 I#6 Z#7，一圈下降 #7。"},
            {"G04", "暂停（延时）", "G04 X1.5 表示停 1.5 秒，G04 P1500 表示停 1500 毫秒。\n孔底停一下、清角停一下都用它。"},
            {"G09", "准确停止", "走这一段时先减速停稳再走下一段，只在当前段有效。\n精修拐角、怕过切时加。"},
            {"G10", "可编程数据输入", "用程序改刀补或工件坐标，不用手动敲面板。\n例：G10 L12 P1 R6.0（把 1 号刀补半径改成 6）；G10 L2 P1 X0 Y0（改 G54）。"},
            {"G17/G18/G19", "选择加工平面", "G17=XY 平面（铣床默认）、G18=ZX、G19=YZ。\n铣削基本都写 G17。"},
            {"G20/G21", "英制 / 公制", "G20 英寸、G21 毫米。开机默认一般是 G21，不用管，但换系统要确认。"},
            {"G28", "返回参考点", "回机械零点。例：G28 G91 Z0（Z 回零）、G28 G91 Y0。\n一定要带 G91，否则会按坐标值乱跑。"},
            {"G30", "返回第二参考点", "回厂家设定的第二参考点，加工中心常把它设成换刀点。写法同 G28。"},
            {"G31", "跳转指令", "碰到外部信号就立即跳到下一段，用于测头测量、对刀。"},
            {"G40", "取消刀补", "取消 G41/G42 半径补偿。程序结束前要写。"},
            {"G41", "左刀补", "沿走刀方向看，刀具在工件左边。\n铣内轮廓（型腔）用它：G41 D13，D 是刀补号。"},
            {"G42", "右刀补", "沿走刀方向看，刀具在工件右边。铣外形（外轮廓凸台）常用。"},
            {"G43", "刀具长度补偿（正）", "把刀长差补上，不写就会按机床 Z 值撞刀。\n例：G43 H13 Z100，H13 要和该刀对刀时的高度号一致。"},
            {"G44", "刀具长度补偿（负）", "很少用，一般只用 G43。"},
            {"G49", "取消长度补偿", "程序结束前写，避免下次调用出错。"},
            {"G50/G51", "比例缩放 / 取消", "G51 X0 Y0 P0.5 表示图形缩小一半，G50 取消。图形放大缩小用。"},
            {"G52", "局部坐标系", "在 G54 里再设一个小原点，只对本程序有效。\n例：G52 X#31 Y#32 把原点平移到型腔中心，程序里就能按中心编程。"},
            {"G53", "机床坐标系移动", "不受 G54~G59 影响，直接走到机床固定点。换刀、清台面常用。"},
            {"G54~G59", "工件坐标系", "最常用的六个坐标系，装夹找正后把原点输进对应的 G54~G59。\n扩展坐标系：G54.1 P1 ~ P48。"},
            {"G65", "调用宏程序", "G65 P9010 A5. B3. 调用 9010 号宏，A/B 把值传给子程序里的 #1/#2。"},
            {"G66/G67", "模态宏调用 / 取消", "G66 之后每一次移动都自动调一次宏，G67 取消。做阵列、多孔时省代码。"},
            {"G68/G69", "坐标旋转 / 取消", "例：G68 X0 Y0 R45. 让后面的程序整体旋转 45°，G69 取消。斜孔、斜槽常用。"},
            {"G73", "高速深孔钻（断屑）", "每次钻一小段就快速退回一点点，把屑带出来。适合深孔、易积屑材料。"},
            {"G74", "左旋攻丝", "反牙螺纹用。F 值 = 螺距 × 转速。"},
            {"G76", "精镗", "镗到孔底主轴停下、刀尖让开再退，不刮伤孔壁。镗精度孔必备。"},
            {"G80", "取消固定循环", "钻孔、镗孔、攻丝做完必须写，否则后面的移动会按循环方式乱走。"},
            {"G81", "钻孔", "例：G81 X0 Y0 Z-20. R2. F100，钻到 Z-20，R2 是安全平面。"},
            {"G82", "沉孔 / 孔底暂停", "和 G81 一样，多了孔底停顿 P 值，沉孔、扩孔用。"},
            {"G83", "深孔啄钻", "例：G83 X0 Y0 Z-30. R2. Q3. F80，每次啄 3mm 排屑一次，Q 是每次深度。"},
            {"G84", "攻丝", "例：M29 S800 / G84 X0 Y0 Z-15. R2. F1.5（M22×1.5 时 F=1.5）。\n必须要有刚性攻丝，转速×螺距=进给。"},
            {"G85", "镗孔（进给退刀）", "一边进给一边退，最简单的一种镗孔循环。"},
            {"G86", "镗孔（停主轴后退）", "孔底主轴停，刀偏移让开再退。精度要求高时用 G76。"},
            {"G90/G91", "绝对 / 增量编程", "G90 按坐标值走，G91 按“再走多少”走。\n回零、抬刀用 G91 更安全：G91 Z50。"},
            {"G92", "工件坐标预置", "把当前位置设成指定坐标，等于挪原点，容易出错，新手少用。"},
            {"G94/G95", "每分钟 / 每转进给", "G94 单位 mm/min（铣床默认），G95 单位 mm/r（攻丝、镗孔有时用）。"},
            {"G98/G99", "固定循环返回点", "G98 每次退回到初始高度，G99 只退到 R 点。\n同一平面多个孔用 G99 可以少走很多空行程。"},
            {"G61/G64", "准停模式 / 切削模式", "G61 每一段都停稳再走，精度高、速度慢；G64 连续过渡最顺，模具曲面用。"},
            {"G96/G97", "恒线速 / 取消", "车床上按线速度恒定，铣床基本不用。"},
    };

    private static final Object[][] M_CODES = {
            {"M00", "程序无条件停止", "程序执行到这一句就停，按“循环启动”继续。装夹、检查时用。"},
            {"M01", "计划停止", "只有面板上的“选择停止”开关打开时才停。试首件时打开，很方便。"},
            {"M02", "程序结束", "结束并复位，但光标不一定回开头，一般用 M30 更彻底。"},
            {"M03", "主轴正转", "例：M03 S2000。S 是转速 r/min。\n顺时针（面向主轴看）为正转，一般铣刀都用正转。"},
            {"M04", "主轴反转", "反牙攻丝、某些刀柄需要反转。"},
            {"M05", "主轴停止", "程序结束、换刀前必须停。"},
            {"M06", "自动换刀", "例：M06 T13，T13 是刀号。\n换刀前必须 G91 G28 Z0 回 Z 零点，否则撞刀。"},
            {"M07", "雾状冷却", "气雾冷却，铸铁、铝件常用，比大水冲干净。"},
            {"M08", "开冷却液", "切削液开。钢件开粗、深孔必开。"},
            {"M09", "关冷却液", "程序结束前关，避免漏液。"},
            {"M19", "主轴定向", "主轴停在一个固定角度，镗孔让刀、反镗刀进出孔要用。"},
            {"M30", "程序结束并复位", "光标回到程序开头，最适合连续加工。程序最后一句写它。"},
            {"M98/M99", "调用子程序 / 返回", "M98 P1000 L3 表示调用 1000 号子程序、重复 3 次，子程序最后一行写 M99 返回。"},
            {"M10/M11", "夹紧 / 松开", "由机床厂家定义，常见是夹紧 M10、松开 M11。使用前查机床说明书。"},
            {"M48/M49", "倍率忽略 / 恢复", "刚性攻丝前写 M48 锁住进给倍率，攻完 M49 恢复。"},
            {"M41/M42/M43", "主轴档位切换", "老式齿轮箱主轴用，现在多为主轴电机无级调速，可不写。"},
            {"M60", "托盘交换", "带自动交换工作台的加工中心用，换台面。"},
    };

    private static final Object[][] OTHERS = {
            {"F", "进给速度", "单位 mm/min（G94 时）。粗铣钢件 300~600，精铣 600~1200，看刀具和机床。"},
            {"S", "主轴转速", "单位 r/min。转速和进给要配合，转速太高小刀会烧，太低会振刀。"},
            {"T", "刀具号", "T1~T99 常见，和刀库位置对应。换刀写 M06 T 号。"},
            {"D", "刀补号", "半径补偿号。G41 D13 表示用 13 号刀补半径，改尺寸只需改刀补，不用改程序。"},
            {"H", "刀长补偿号", "G43 H13，和 D 一样是号，别混：D 管半径，H 管长度。"},
            {"O", "程序号", "O0001~O9999。本 App 生成 O1001~O1005 分别对应五种模式。"},
            {"N", "程序段号", "N10、N20… 便于跳段和查找，可不写。"},
            {"括号", "注释", "（型腔粗铣）括号里是注释，机床会忽略，写清楚方便下次看。"},
    };

    private static final Object[][] MACRO = {
            {"#1~#33", "局部变量", "只在本程序内有效，断电丢失。切削参数一般放这里：\n#1=120.（长） #2=80.（宽）"},
            {"#100~#199", "公共变量", "各程序共用，断电一般清零。#500~#999 断电保持，用来记数、记状态。"},
            {"#1000 以上", "系统变量", "机床内部状态量（坐标、刀补等），读写要小心，新手别碰。"},
            {"[ ]", "运算括号", "宏程序里必须用方括号：#11=[#1/2.]。\n写成 (#1/2) 会报警。小数点也别省：#1=1. 要带点。"},
            {"EQ/NE/GT/GE/LT/LE", "比较", "等于 / 不等于 / 大于 / 大于等于 / 小于 / 小于等于。\n例：WHILE[#23LT#3]DO1 表示当前深度小于总深就继续循环。"},
            {"AND/OR/XOR", "逻辑", "与 / 或 / 异或，用在条件判断里组合多个条件。"},
            {"ABS/SQRT", "绝对值 / 开方", "ABS[-5]=5；SQRT[16]=4。"},
            {"SIN/COS/TAN", "三角函数", "角度按度算（FANUC 默认）。锥孔半角就靠 TAN[#3] 算每一层的半径差。"},
            {"ATAN", "反正切", "由两直角边求角度：#3=ATAN[[#1-#2]/2./#4]，本 App 的锥孔半角就是这么算的。"},
            {"ROUND/FIX/FUP", "取整", "四舍五入 / 舍去小数 / 进位。分层数、圈数用它。"},
            {"WHILE[ ] DO n … END n", "当型循环", "条件成立就一直循环，n 为 1~3 层号，END n 收尾，必须成对。\n本 App 的分层、分行都是这种结构。"},
            {"IF[ ] THEN", "条件执行", "IF[#23GT#3]THEN#23=#3 —— 超深了就拉回到总深，防止过切。"},
            {"IF[ ] GOTO n / GOTO n", "条件跳转 / 无条件跳转", "跳到段号 N 处。少用，容易死循环。"},
            {"#10=#10+1", "自增计数", "常用写法，统计走了第几圈、第几行。"},
    };

    private static final Object[][] TIPS = {
            {"①", "先抬刀再动 XY", "任何换位、进给之前，先把 Z 抬到安全高度（本 App 用 #10=100），再动 X/Y。撞刀九成是顺序反了。"},
            {"②", "G43 H 号必须有", "每把刀都要 G43 H 对应的补偿号，号或正负错了直接扎工件。"},
            {"③", "先空跑验证", "新程序把 Z 整体抬高 100 空跑一遍，看清刀路再落刀。"},
            {"④", "参数集中写前面", "尺寸、深度、转速、进给都放在程序开头的 #1~#9，改一处就全改，别散在中间。"},
            {"⑤", "循环必须有出口", "WHILE 一定要有让条件变假的语句（#23=#23+#6），否则死机。"},
            {"⑥", "结束要收干净", "G80 取消循环、M09 关液、G91 G28 Z0 回零、M30 结束，缺一句都可能报警或撞机。"},
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(MainActivity.C_BG);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(24));
        scroll.addView(root);

        addTopBar(root);

        // 搜索框
        EditText search = new EditText(this);
        search.setHint("搜索代码或关键词：G43 / 攻丝 / 刀补 / WHILE");
        search.setTextSize(14);
        search.setSingleLine(true);
        search.setInputType(InputType.TYPE_CLASS_TEXT);
        search.setTextColor(MainActivity.C_TEXT);
        search.setHintTextColor(MainActivity.C_TEXT2);
        search.setBackground(bg(MainActivity.C_CARD, 12));
        search.setPadding(dp(14), dp(10), dp(14), dp(10));
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        slp.bottomMargin = dp(4);
        search.setLayoutParams(slp);
        root.addView(search);

        listBox = new LinearLayout(this);
        listBox.setOrientation(LinearLayout.VERTICAL);
        root.addView(listBox);

        search.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int a, int b, int c) { }

            @Override
            public void onTextChanged(CharSequence s, int a, int b, int c) {
                render(s.toString().trim());
            }

            @Override
            public void afterTextChanged(Editable s) { }
        });

        render("");

        TextView foot = new TextView(this);
        foot.setText("代码含义按 FANUC 0i 系列通用说明整理，不同机床的 M 代码可能有差异，上机前请核对机床说明书。");
        foot.setTextSize(11);
        foot.setTextColor(MainActivity.C_TEXT2);
        foot.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        flp.topMargin = dp(14);
        foot.setLayoutParams(flp);
        root.addView(foot);

        setContentView(scroll);
    }

    private LinearLayout listBox;

    private static final String[][] SECTIONS = {
            {"G 代码（准备功能）", "铣削 / 加工中心常用，斜体字是写法示例"},
            {"M 代码（辅助功能）", "主轴、冷却、换刀、程序结束"},
            {"其他常用指令", "F/S/T/D/H/O/N 与注释"},
            {"宏程序基础语法", "本 App 生成的程序全部用到这些"},
            {"新手六条铁律", "记住这六条，少撞九成刀"},
    };

    private Object[][] dataOf(int idx) {
        switch (idx) {
            case 0: return G_CODES;
            case 1: return M_CODES;
            case 2: return OTHERS;
            case 3: return MACRO;
            default: return TIPS;
        }
    }

    /** 按关键字重建列表；关键字为空则显示全部 */
    private void render(String keyword) {
        listBox.removeAllViews();
        String kw = keyword.toLowerCase();
        int total = 0;

        for (int s = 0; s < SECTIONS.length; s++) {
            Object[][] data = dataOf(s);
            int hit = 0;
            for (Object[] it : data) {
                String code = (String) it[0];
                String name = (String) it[1];
                String desc = (String) it[2];
                if (kw.length() == 0 || code.toLowerCase().contains(kw)
                        || name.toLowerCase().contains(kw) || desc.toLowerCase().contains(kw)) {
                    if (hit == 0) addSection(listBox, SECTIONS[s][0], kw.length() == 0 ? SECTIONS[s][1] : "与「" + keyword + "」相关的条目");
                    hit++;
                    total++;
                    addItem(listBox, code, name, desc);
                }
            }
        }

        if (total == 0) {
            TextView empty = new TextView(this);
            empty.setText("没找到「" + keyword + "」\n换个说法试试：G43、攻丝、刀补、WHILE、M30");
            empty.setTextSize(13);
            empty.setTextColor(MainActivity.C_TEXT2);
            empty.setGravity(Gravity.CENTER);
            empty.setLineSpacing(dp(4), 1f);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(30);
            empty.setLayoutParams(lp);
            listBox.addView(empty);
        }
    }

    private void addTopBar(LinearLayout root) {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);

        TextView back = new TextView(this);
        back.setText("‹ 返回");
        back.setTextSize(15);
        back.setTypeface(Typeface.DEFAULT_BOLD);
        back.setTextColor(MainActivity.C_ACCENT);
        back.setPadding(0, dp(4), dp(10), dp(4));
        back.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                finish();
            }
        });
        bar.addView(back);

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tlp.leftMargin = dp(6);
        texts.setLayoutParams(tlp);

        TextView title = new TextView(this);
        title.setText("编程代码大全");
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(MainActivity.C_TEXT);
        texts.addView(title);

        TextView sub = new TextView(this);
        sub.setText("G / M 代码逐条讲解，新手照着看就会用");
        sub.setTextSize(12);
        sub.setTextColor(MainActivity.C_TEXT2);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        slp.topMargin = dp(2);
        sub.setLayoutParams(slp);
        texts.addView(sub);

        bar.addView(texts);
        LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        blp.bottomMargin = dp(10);
        bar.setLayoutParams(blp);
        root.addView(bar);
    }

    private void addSection(LinearLayout root, String title, String sub) {
        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(14);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(MainActivity.C_TEXT);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(16);
        lp.bottomMargin = dp(6);
        t.setLayoutParams(lp);
        root.addView(t);

        TextView s = new TextView(this);
        s.setText(sub);
        s.setTextSize(11);
        s.setTextColor(MainActivity.C_TEXT2);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        slp.bottomMargin = dp(8);
        s.setLayoutParams(slp);
        root.addView(s);
    }

    private void addItem(LinearLayout root, String code, String name, String desc) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(bg(MainActivity.C_CARD, 12));
        card.setPadding(dp(12), dp(10), dp(12), dp(11));

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(7);
        card.setLayoutParams(lp);

        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);

        TextView c = new TextView(this);
        c.setText(code);
        c.setTextSize(14);
        c.setTypeface(Typeface.DEFAULT_BOLD);
        c.setTextColor(MainActivity.C_ACCENT);
        c.setBackground(bg(0x16FF6B1A, 6));
        c.setPadding(dp(7), dp(2), dp(7), dp(2));
        head.addView(c);

        TextView n = new TextView(this);
        n.setText(name);
        n.setTextSize(13.5f);
        n.setTypeface(Typeface.DEFAULT_BOLD);
        n.setTextColor(MainActivity.C_TEXT);
        LinearLayout.LayoutParams nlp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        nlp.leftMargin = dp(8);
        n.setLayoutParams(nlp);
        head.addView(n);
        card.addView(head);

        TextView d = new TextView(this);
        d.setText(desc);
        d.setTextSize(12);
        d.setTextColor(MainActivity.C_TEXT2);
        d.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        dlp.topMargin = dp(6);
        d.setLayoutParams(dlp);
        card.addView(d);

        root.addView(card);
    }

    private GradientDrawable bg(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    private int dp(float v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
