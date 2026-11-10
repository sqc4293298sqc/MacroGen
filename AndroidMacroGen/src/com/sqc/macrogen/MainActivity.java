package com.sqc.macrogen;

import android.app.Activity;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {

    static final int C_BG = 0xFFF4F6F8;
    static final int C_CARD = 0xFFFFFFFF;
    static final int C_ACCENT = 0xFFFF6B1A;
    static final int C_TEXT = 0xFF1B2431;
    static final int C_TEXT2 = 0xFF7A8595;
    static final int C_FIELD = 0xFFF1F3F6;

    static String pendingCode = null;
    static String pendingName = null;
    private static final int REQ_SAVE = 1001;

    private final GCode spec = new GCode();
    private EditText eLen, eWid, eDep, eCorner, eTool, eAp, eAe, eS, eF, eZ, eCx, eCy, eSpiral, eKeyL, eKeyW, eKeyD;
    private EditText eBig, eSmall, eDepthT, eRatio, eAngle, eToolR, eHNo;
    private int ratioSource = 0;  // 0=小头 1=锥度 2=角度
    private boolean syncing = false;
    private LinearLayout cardSize, cardCorner, cardTaper, cardOut, cardSpiral, cardKey, cardPath, cardChamfer;
    private EditText eChaDia, eChaAngle, eChaDepth, eChaStep;
    private LinearLayout modeGrid;
    private int curMode = GCode.MODE_POCKET;

    // 模式短名 + 副标题（网格里显示）
    private static final String[][] MODES = {
            {"型腔", "R / C 四角"},
            {"锥孔", "1:N 锥面"},
            {"飞面", "往复平面"},
            {"螺旋铣", "圆面螺旋"},
            {"键槽", "直槽 + 两端 R"},
            {"外形", "G41 修外形"},
            {"内圆倒角", "孔口锥面"}
    };
    private ImageView imgPath;
    private TextView lblPath;
    private TextView lblSize, lblDeep;
    private CheckBox compactFlag;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(C_BG);
        scroll.setFillViewport(true);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(root, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        addHeader(root);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(14), dp(14), dp(14), dp(28));
        root.addView(body);

        LinearLayout cardMode = card(body, "加工类型", "点一下选模式，下面的参数会跟着换");
        modeGrid = new LinearLayout(this);
        modeGrid.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams mglp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        mglp.topMargin = dp(8);
        modeGrid.setLayoutParams(mglp);
        cardMode.addView(modeGrid);
        buildModeGrid();

        cardPath = card(body, "刀路示意", "看刀路怎么走，对照检查参数");
        imgPath = new ImageView(this);
        imgPath.setAdjustViewBounds(true);
        imgPath.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams iplp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(190));
        iplp.topMargin = dp(6);
        cardPath.addView(imgPath, iplp);
        lblPath = (TextView) cardPath.getChildAt(1);

        cardSize = card(body, "型腔尺寸", "单位 mm");
        eLen = field(cardSize, "长 L", "120");
        eWid = field(cardSize, "宽 W", "80");
        eDep = field(cardSize, "深 D", "10");
        lblSize = (TextView) cardSize.getChildAt(0);
        lblDeep = (TextView) ((LinearLayout) eDep.getParent()).getChildAt(0);

        cardTaper = card(body, "锥孔参数", "大小头定锥度；锥度与角度也可直接改，其余自动换算");
        eBig = field(cardTaper, "大头 D", "50");
        eSmall = field(cardTaper, "小头 d", "34");
        eDepthT = field(cardTaper, "深度 H", "38");
        eRatio = field(cardTaper, "锥度 1:N", "2.38");
        eAngle = field(cardTaper, "角度 °", "22.83");
        watch(eBig, -1);
        watch(eDepthT, -1);
        watch(eSmall, 0);
        watch(eRatio, 1);
        watch(eAngle, 2);
        ratioSource = 0;
        recalc();

        cardChamfer = card(body, "内圆倒角参数", "孔口锥面：孔径 + 锥角 + 倒角深；每层给 0.1 最稳");
        eChaDia = field(cardChamfer, "孔径 Ø", "14");
        eChaAngle = field(cardChamfer, "锥角 °（全角）", "60");
        eChaDepth = field(cardChamfer, "倒角深 H", "4");
        eChaStep = field(cardChamfer, "每层 mm", "0.1");

        cardKey = card(body, "键槽参数", "槽长含两端圆弧；槽宽大于刀径时自动分行");
        eKeyL = field(cardKey, "槽长 L", "40");
        eKeyW = field(cardKey, "槽宽 W", "12");
        eKeyD = field(cardKey, "总深 H", "5");

        cardSpiral = card(body, "螺旋参数", "一圈一圈螺旋下刀，适合圆面 / 圆孔");
        eSpiral = field(cardSpiral, "圆直径 D", "50");

        cardCorner = card(body, "四角形状", "圆角 R 或 45° 倒角 C");
        Spinner sp = styledSpinner(cardCorner, new String[]{"R 圆角", "C 倒角", "直角"});
        sp.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                spec.cornerType = position;
                if (eCorner != null) {
                    eCorner.setEnabled(position != GCode.CORNER_SQUARE);
                    eCorner.setTextColor(position == GCode.CORNER_SQUARE ? C_TEXT2 : C_TEXT);
                }
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) { }
        });
        eCorner = field(cardCorner, "R / C 值", "8");

        LinearLayout cardCoord = card(body, "坐标系与中心", "型腔中心在所选 G 坐标系下的位置");
        Spinner cs = styledSpinner(cardCoord, new String[]{"G54", "G55", "G56", "G57", "G58", "G59"});
        cs.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                spec.coord = 54 + position;
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) { }
        });
        eCx = field(cardCoord, "中心 X", "0");
        eCy = field(cardCoord, "中心 Y", "0");

        LinearLayout cardTool = card(body, "刀具与切削", "42CrMo 调质件参考值");
        eTool = field(cardTool, "刀具直径", "12");
        eAp = field(cardTool, "每层切深 AP", "3");
        eAe = field(cardTool, "行距 AE", "6");
        eS = field(cardTool, "转速 S", "2000");
        eF = field(cardTool, "进给 F", "400");
        eZ = field(cardTool, "安全高度 Z", "100");
        eToolR = field(cardTool, "刀尖 R（平底刀填 0）", "5");
        eHNo = field(cardTool, "刀补号 H", "13");

        cardOut = card(body, "输出写法", "轮廓压缩方式");
        compactFlag = new CheckBox(this);
        compactFlag.setText("精简写法（用 ,R / ,C 自动倒圆倒角）");
        compactFlag.setChecked(true);
        compactFlag.setTextSize(13);
        compactFlag.setTextColor(C_TEXT);
        compactFlag.setPadding(0, dp(4), 0, 0);
        cardOut.addView(compactFlag);

        TextView hint = new TextView(this);
        hint.setText("0i-MF 需参数 No.3405 第 4 位（CCR）= 1 才认 ,R / ,C；拿不准就取消勾选");
        hint.setTextSize(11);
        hint.setTextColor(C_TEXT2);
        hint.setLineSpacing(dp(2), 1f);
        cardOut.addView(hint);

        Button gen = new Button(this);
        gen.setText("生成宏程序 · 含刀路仿真");
        gen.setTextSize(16);
        gen.setTypeface(Typeface.DEFAULT_BOLD);
        gen.setTextColor(Color.WHITE);
        gen.setAllCaps(false);
        gen.setBackground(ripple(C_ACCENT, 14));
        LinearLayout.LayoutParams glp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(54));
        glp.topMargin = dp(18);
        gen.setLayoutParams(glp);
        gen.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                runGenerate();
            }
        });
        body.addView(gen);


        String[][] tools = {
                {"公差查询", "H7 / H8 / G7 / e7"},
                {"丝锥底孔", "螺距 · 底孔 · 钻头"},
                {"刀具转速", "皇冠钻 / 合金钻 S·F"},
                {"代码大全", "G/M 代码逐条讲"}
        };
        LinearLayout impCard = card(body, "识别 / 导入", "拍照或粘贴别人的程序，直接跑仿真");
        LinearLayout impRow = new LinearLayout(this);
        impRow.setOrientation(LinearLayout.HORIZONTAL);
        Button impBtn = new Button(this);
        impBtn.setText("拍照识别程序 · 导入并模拟");
        impBtn.setTextSize(14);
        impBtn.setAllCaps(false);
        impBtn.setTextColor(Color.WHITE);
        impBtn.setTypeface(Typeface.DEFAULT_BOLD);
        impBtn.setBackground(ripple(0xFF33404F, 12));
        impBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(MainActivity.this, ImportActivity.class));
            }
        });
        impRow.addView(impBtn, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(46)));
        impCard.addView(impRow);

        LinearLayout toolsCard = card(body, "常用查询", "新手最常翻的四张表");
        int rows = tools.length / 2;        // 4 项 = 两行，别跟着模式数量走
        for (int r = 0; r < rows; r++) {
            LinearLayout trow = new LinearLayout(this);
            trow.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams rlp2 = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            if (r > 0) rlp2.topMargin = dp(8);
            trow.setLayoutParams(rlp2);
            toolsCard.addView(trow);
            for (int c = 0; c < 2; c++) {
                final int idx = r * 2 + c;
                LinearLayout cell = new LinearLayout(this);
                cell.setOrientation(LinearLayout.VERTICAL);
                cell.setBackground(ripple(C_FIELD, 12));
                cell.setPadding(dp(12), dp(10), dp(12), dp(10));
                LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
                if (c == 0) clp.rightMargin = dp(6); else clp.leftMargin = dp(6);
                cell.setLayoutParams(clp);

                TextView t1 = new TextView(this);
                t1.setText(tools[idx][0]);
                t1.setTextSize(14);
                t1.setTypeface(Typeface.DEFAULT_BOLD);
                t1.setTextColor(C_TEXT);
                cell.addView(t1);

                TextView t2 = new TextView(this);
                t2.setText(tools[idx][1]);
                t2.setTextSize(10.5f);
                t2.setTextColor(C_TEXT2);
                t2.setPadding(0, dp(3), 0, 0);
                cell.addView(t2);

                cell.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        if (idx == 0) {
                            startActivity(new Intent(MainActivity.this, ToleranceActivity.class));
                        } else if (idx == 1) {
                            startActivity(new Intent(MainActivity.this, ThreadActivity.class));
                        } else if (idx == 2) {
                            startActivity(new Intent(MainActivity.this, ToolFeedActivity.class));
                        } else {
                            startActivity(new Intent(MainActivity.this, CodeRefActivity.class));
                        }
                    }
                });
                trow.addView(cell);
            }
        }

        TextView foot = new TextView(this);
        foot.setText("生成后可直接复制、分享或存成 .nc 文件");
        foot.setTextSize(11);
        foot.setTextColor(C_TEXT2);
        foot.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        flp.topMargin = dp(10);
        foot.setLayoutParams(flp);
        body.addView(foot);

        setContentView(scroll);
        switchMode(GCode.MODE_POCKET);
        // 每次启动查一次新版本（没网就静默跳过）
        UpdateChecker.check(this);
    }

    /** 六宫格模式选择 */
    private void buildModeGrid() {
        modeGrid.removeAllViews();
        int modeRows = (MODES.length + 2) / 3;   // 7 个模式 = 三行
        for (int r = 0; r < modeRows; r++) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            if (r > 0) rlp.topMargin = dp(8);
            row.setLayoutParams(rlp);
            for (int c = 0; c < 3; c++) {
                final int idx = r * 3 + c;
                if (idx >= MODES.length) {          // 最后一行不满时补空位，保持等宽
                    LinearLayout blank = new LinearLayout(this);
                    blank.setLayoutParams(new LinearLayout.LayoutParams(0,
                            ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
                    row.addView(blank);
                    continue;
                }
                boolean on = curMode == idx;

                LinearLayout cell = new LinearLayout(this);
                cell.setOrientation(LinearLayout.VERTICAL);
                cell.setBackground(ripple(on ? C_ACCENT : C_FIELD, 12));
                cell.setPadding(dp(10), dp(9), dp(10), dp(9));
                LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(0,
                        ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
                if (c > 0) clp.leftMargin = dp(6);
                cell.setLayoutParams(clp);

                TextView n = new TextView(this);
                n.setText("0" + (idx + 1));
                n.setTextSize(9.5f);
                n.setTextColor(on ? 0xFFFFD9C2 : C_TEXT2);
                cell.addView(n);

                TextView t = new TextView(this);
                t.setText(MODES[idx][0]);
                t.setTextSize(14);
                t.setTypeface(Typeface.DEFAULT_BOLD);
                t.setTextColor(on ? Color.WHITE : C_TEXT);
                t.setPadding(0, dp(2), 0, 0);
                cell.addView(t);

                TextView d = new TextView(this);
                d.setText(MODES[idx][1]);
                d.setTextSize(10);
                d.setTextColor(on ? 0xFFFFE7DA : C_TEXT2);
                d.setPadding(0, dp(2), 0, 0);
                cell.addView(d);

                cell.setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        selectMode(idx);
                    }
                });
                row.addView(cell);
            }
            modeGrid.addView(row);
        }
    }

    private void selectMode(int mode) {
        curMode = mode;
        spec.mode = mode;
        buildModeGrid();
        switchMode(mode);
    }

    private void switchMode(int mode) {
        boolean taper = mode == GCode.MODE_TAPER;
        boolean face = mode == GCode.MODE_FACE;
        boolean spiral = mode == GCode.MODE_SPIRAL;
        boolean key = mode == GCode.MODE_KEY;
        boolean outer = mode == GCode.MODE_OUTER;
        boolean cham = mode == GCode.MODE_CHAMFER;
        if (cardSize != null) cardSize.setVisibility((taper || spiral || key || cham) ? View.GONE : View.VISIBLE);
        if (cardCorner != null) cardCorner.setVisibility((taper || face || spiral || key || cham) ? View.GONE : View.VISIBLE);
        if (cardOut != null) cardOut.setVisibility((taper || face || spiral || key || cham) ? View.GONE : View.VISIBLE);
        if (cardChamfer != null) cardChamfer.setVisibility(cham ? View.VISIBLE : View.GONE);
        if (cardTaper != null) cardTaper.setVisibility(taper ? View.VISIBLE : View.GONE);
        if (cardSpiral != null) cardSpiral.setVisibility(spiral ? View.VISIBLE : View.GONE);
        if (cardKey != null) cardKey.setVisibility(key ? View.VISIBLE : View.GONE);
        int[] tp = {R.drawable.tp_pocket, R.drawable.tp_taper, R.drawable.tp_face,
                R.drawable.tp_spiral, R.drawable.tp_key, R.drawable.tp_outer,
                R.drawable.tp_chamfer};
        String[] tpText = {
                "外圈一圈圈向内缩，逐层把腔掏空，最后 G41 精修侧壁",
                "一圈圈逐渐缩小的圆弧沿锥面盘旋下到底",
                "Y 向往复走平行线，一层走满整张面再下一层",
                "刀心圆上 G3 连续下降，每圈吃一层",
                "沿槽长来回走，两端由刀径形成圆弧；槽宽大于刀径时自动分行",
                "贴工件轮廓外侧顺时针绕一圈一圈往下，G41 把刀偏在外面",
                "刀心在孔里一圈一圈缩着往下，每层 0.1，把孔口锥面叠出来"};
        if (imgPath != null && mode >= 0 && mode < tp.length) {
            imgPath.setImageResource(tp[mode]);
            lblPath.setText(tpText[mode]);
        }
        if (lblSize != null) lblSize.setText(face ? "平面尺寸（深 = 要去掉的总量）" : (outer ? "工件外形尺寸" : "型腔尺寸"));
        if (lblDeep != null) lblDeep.setText(face ? "去量 H（mm）" : "深 D");
    }

    private void addHeader(LinearLayout root) {
        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.setBackgroundColor(0xFF1B2431);
        head.setPadding(dp(18), dp(20), dp(18), dp(18));

        TextView badge = new TextView(this);
        badge.setText("M");
        badge.setTextSize(18);
        badge.setTypeface(Typeface.DEFAULT_BOLD);
        badge.setTextColor(Color.WHITE);
        badge.setGravity(Gravity.CENTER);
        badge.setBackground(roundFill(C_ACCENT, 12));
        badge.setLayoutParams(new LinearLayout.LayoutParams(dp(42), dp(42)));

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tlp.leftMargin = dp(12);
        texts.setLayoutParams(tlp);

        TextView title = new TextView(this);
        title.setText("宏程序生成器");
        title.setTextSize(19);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(0xFFFFFFFF);

        TextView sub = new TextView(this);
        sub.setText("方形型腔 · R / C 四角 · FANUC 宏程序");
        sub.setTextSize(11);
        sub.setTextColor(0xFF9AA6B6);
        sub.setPadding(0, dp(3), 0, 0);

        texts.addView(title);
        texts.addView(sub);

        head.addView(badge);
        head.addView(texts);
        root.addView(head);
    }

    private LinearLayout card(LinearLayout parent, String title, String subtitle) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(roundFill(C_CARD, 14));
        card.setPadding(dp(16), dp(14), dp(16), dp(14));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(12);
        card.setLayoutParams(lp);

        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(14);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(C_TEXT);
        card.addView(t);

        TextView st = new TextView(this);
        st.setText(subtitle);
        st.setTextSize(11);
        st.setTextColor(C_TEXT2);
        st.setPadding(0, dp(2), 0, dp(4));
        card.addView(st);

        parent.addView(card);
        return card;
    }

    private EditText field(LinearLayout card, String label, String def) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(5), 0, dp(5));

        TextView tv = new TextView(this);
        tv.setText(label);
        tv.setTextSize(14);
        tv.setTextColor(C_TEXT);
        tv.setLayoutParams(new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        EditText et = new EditText(this);
        et.setText(def);
        et.setTextSize(15);
        et.setTextColor(C_TEXT);
        et.setSingleLine(true);
        et.setGravity(Gravity.CENTER_VERTICAL | Gravity.END);
        et.setPadding(dp(10), dp(6), dp(10), dp(6));
        et.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        et.setBackground(roundFill(C_FIELD, 10));
        et.setLayoutParams(new LinearLayout.LayoutParams(dp(122), dp(42)));

        row.addView(tv);
        row.addView(et);
        card.addView(row);
        return et;
    }

    private Spinner styledSpinner(LinearLayout card, String[] items) {
        Spinner sp = new Spinner(this);
        ArrayAdapter<String> ad = new ArrayAdapter<String>(this,
                android.R.layout.simple_spinner_dropdown_item, items) {
            @Override
            public View getView(int position, View convertView, ViewGroup parent) {
                View v = super.getView(position, convertView, parent);
                if (v instanceof TextView) {
                    TextView t = (TextView) v;
                    t.setTextColor(C_TEXT);
                    t.setTextSize(14);
                    t.setPadding(dp(10), dp(6), dp(4), dp(6));
                }
                return v;
            }
        };
        sp.setAdapter(ad);
        sp.setBackground(roundFill(C_FIELD, 10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(44));
        lp.topMargin = dp(4);
        lp.bottomMargin = dp(2);
        sp.setLayoutParams(lp);
        card.addView(sp);
        return sp;
    }

    private GCode collect() {
        try {
            spec.toolCornerR = d(eToolR, 0);
            spec.hNo = (int) d(eHNo, 13);
            spec.taperDia = d(eBig, 50);
            spec.taperDiaSmall = d(eSmall, 34);
            spec.taperDepth = d(eDepthT, 38);
            spec.length = d(eLen, 120);
            spec.width = d(eWid, 80);
            spec.depth = d(eDep, 10);
            spec.cornerValue = d(eCorner, 8);
            spec.toolDia = d(eTool, 12);
            spec.stepDown = d(eAp, 3);
            spec.stepOver = d(eAe, 6);
            spec.spindle = (int) d(eS, 2000);
            spec.feed = (int) d(eF, 400);
            spec.safeZ = d(eZ, 100);
            spec.cx = d(eCx, 0);
            spec.cy = d(eCy, 0);
            spec.compact = compactFlag == null || compactFlag.isChecked();
            if (eSpiral != null) spec.spiralDia = d(eSpiral, 50);
            if (eChaDia != null) {
                spec.chaDia = d(eChaDia, 14);
                spec.chaAngle = d(eChaAngle, 60);
                spec.chaDepth = d(eChaDepth, 4);
                spec.chaStep = d(eChaStep, 0.1);
            }
            if (eKeyL != null) {
                spec.keyLength = d(eKeyL, 40);
                spec.keyWidth = d(eKeyW, 12);
                spec.depth = d(eKeyD, 5);
            }
        } catch (Exception ex) {
            Toast.makeText(this, "输入格式有误，检查数字", Toast.LENGTH_SHORT).show();
            return null;
        }
        return spec;
    }

    private void runGenerate() {
        GCode s = collect();
        if (s == null) return;

        String problem = spec.check();
        if (!problem.isEmpty()) {
            Toast.makeText(this, problem.split("\n")[0], Toast.LENGTH_LONG).show();
            return;
        }

        String code = spec.generate();
        String name;
        if (spec.mode == GCode.MODE_TAPER) {
            name = "taper_D" + (int) spec.taperDia + "d" + (int) spec.taperDiaSmall + "_H" + (int) spec.taperDepth + ".nc";
        } else if (spec.mode == GCode.MODE_FACE) {
            name = "face_L" + (int) spec.length + "_W" + (int) spec.width + "_H" + (int) spec.depth + ".nc";
        } else if (spec.mode == GCode.MODE_SPIRAL) {
            name = "spiral_D" + (int) spec.spiralDia + "_H" + (int) spec.depth + ".nc";
        } else if (spec.mode == GCode.MODE_KEY) {
            name = "key_L" + (int) spec.keyLength + "_W" + (int) spec.keyWidth + "_H" + (int) spec.depth + ".nc";
        } else if (spec.mode == GCode.MODE_CHAMFER) {
            name = "chamfer_D" + (int) spec.chaDia + "_A" + (int) spec.chaAngle + "_H" + (int) spec.chaDepth + ".nc";
        } else if (spec.mode == GCode.MODE_OUTER) {
            name = "outer_L" + (int) spec.length + "_W" + (int) spec.width + "_H" + (int) spec.depth + ".nc";
        } else {
            name = "pocket_L" + (int) spec.length + "_W" + (int) spec.width + ".nc";
        }
        ResultDialog.show(this, spec, code, name, spec.manual());
    }

    private void watch(final EditText et, final int src) {
        et.addTextChangedListener(new android.text.TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int a, int b, int c) { }

            @Override
            public void onTextChanged(CharSequence s, int a, int b, int c) { }

            @Override
            public void afterTextChanged(android.text.Editable e) {
                if (syncing) return;
                if (src >= 0) ratioSource = src;
                recalc();
            }
        });
    }

    private void recalc() {
        if (eBig == null || eSmall == null || eDepthT == null) return;
        try {
            double big = num(eBig, 0);
            double depth = num(eDepthT, 0);
            if (big <= 0 || depth <= 0) return;
            double small;
            if (ratioSource == 0) {
                small = num(eSmall, 0);
            } else if (ratioSource == 1) {
                double n = num(eRatio, 0);
                if (n <= 0) return;
                small = big - depth / n;
            } else {
                double deg = num(eAngle, 0);
                if (deg <= 0 || deg >= 89) return;
                small = big - depth * Math.tan(Math.toRadians(deg));
            }
            if (small <= 0 || big <= small) return;

            syncing = true;
            if (ratioSource != 0) eSmall.setText(fmt(small));
            if (ratioSource != 1) eRatio.setText(fmt(depth / (big - small)));
            if (ratioSource != 2)
                eAngle.setText(fmt(Math.toDegrees(Math.atan((big - small) / depth))));
            syncing = false;
        } catch (Exception ignored) { }
    }

    static String fmt(double v) {
        java.text.DecimalFormat df = new java.text.DecimalFormat("0.00",
                new java.text.DecimalFormatSymbols(java.util.Locale.US));
        df.setGroupingUsed(false);
        return df.format(v);
    }

    static double num(EditText e, double def) {
        String s = e.getText().toString().trim();
        if (s.isEmpty()) return def;
        return Double.parseDouble(s.replace(",", "."));
    }

    static double d(EditText e, double def) {
        String s = e.getText().toString().trim();
        if (s.isEmpty()) return def;
        return Double.parseDouble(s);
    }

    GradientDrawable roundFill(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.RECTANGLE);
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    RippleDrawable ripple(int color, int radiusDp) {
        GradientDrawable fill = roundFill(color, radiusDp);
        GradientDrawable mask = roundFill(Color.WHITE, radiusDp);
        return new RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), fill, mask);
    }

    int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }

    static void saveFile(Activity act, String code, String name) {
        pendingCode = code;
        pendingName = name;
        Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("text/plain");
        i.putExtra(Intent.EXTRA_TITLE, name);
        act.startActivityForResult(i, REQ_SAVE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_SAVE && resultCode == RESULT_OK && data != null) {
            try {
                java.io.OutputStream os = getContentResolver().openOutputStream(data.getData());
                os.write(pendingCode.getBytes("UTF-8"));
                os.close();
                Toast.makeText(this, "已保存 " + pendingName, Toast.LENGTH_SHORT).show();
            } catch (Exception e) {
                Toast.makeText(this, "保存失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        }
    }
}
