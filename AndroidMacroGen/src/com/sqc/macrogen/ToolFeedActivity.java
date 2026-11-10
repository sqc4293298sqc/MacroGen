package com.sqc.macrogen;

import android.app.Activity;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

/**
 * 刀具转速进给推荐：皇冠钻 / 整体合金钻 / 普通高速钢钻，
 * 输入直径和孔深（倍径），算转速 S 和进给 F，并列出常用直径的推荐值。
 */
public class ToolFeedActivity extends Activity {

    private static final String[] MATERIALS = {"碳钢 / 合金钢", "不锈钢", "铸铁", "铝 / 铜"};
    private static final String[] TOOLS = {"皇冠钻（U 钻 / 可换头）", "整体合金钻", "普通高速钢钻"};

    // 切削速度 Vc（m/min）：[刀具][材料]
    private static final double[][] VC = {
            {130, 80, 150, 250},
            {100, 60, 110, 200},
            {25, 15, 22, 60}
    };
    // 每转进给 = k × 直径（mm/r）
    private static final double[] FREV_K = {0.012, 0.010, 0.008};
    // 常用直径档
    private static final double[] DIA = {3, 5, 6, 8, 10, 12, 16, 20, 25, 30};

    private Spinner spMat, spTool;
    private EditText eDia, eDeep;
    private LinearLayout resBox, tableBox;
    private int mat = 0, tool = 0;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(MainActivity.C_BG);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(24));
        scroll.addView(root);

        addTopBar(root, "刀具转速进给", "皇冠钻 · 合金钻 · 普通钻 → 推荐 S / F");

        // 输入卡
        LinearLayout card = cardBox(root);
        title(card, "选刀具和工况");

        LinearLayout row1 = new LinearLayout(this);
        row1.setOrientation(LinearLayout.VERTICAL);
        row1.setPadding(0, dp(6), 0, 0);
        card.addView(row1);
        label(row1, "刀具类型");
        spTool = spinner(row1, TOOLS);
        spTool.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
                tool = pos;
                calc();
            }

            @Override
            public void onNothingSelected(AdapterView<?> p) { }
        });

        LinearLayout row2 = new LinearLayout(this);
        row2.setOrientation(LinearLayout.VERTICAL);
        row2.setPadding(0, dp(10), 0, 0);
        card.addView(row2);
        label(row2, "工件材料");
        spMat = spinner(row2, MATERIALS);
        spMat.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
                mat = pos;
                calc();
            }

            @Override
            public void onNothingSelected(AdapterView<?> p) { }
        });

        LinearLayout row3 = new LinearLayout(this);
        row3.setOrientation(LinearLayout.HORIZONTAL);
        row3.setPadding(0, dp(10), 0, 0);
        card.addView(row3);
        eDia = numField(row3, "钻头直径 Ø", "10", 1f, dp(0));
        eDeep = numField(row3, "孔深（mm）", "30", 1f, dp(10));

        Button go = new Button(this);
        go.setText("算转速和进给");
        go.setTextSize(15);
        go.setTypeface(Typeface.DEFAULT_BOLD);
        go.setAllCaps(false);
        go.setTextColor(0xFFFFFFFF);
        go.setBackground(bg(MainActivity.C_ACCENT, 12));
        LinearLayout.LayoutParams glp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(46));
        glp.topMargin = dp(12);
        go.setLayoutParams(glp);
        go.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                calc();
            }
        });
        card.addView(go);

        // 结果
        resBox = new LinearLayout(this);
        resBox.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rlp.topMargin = dp(12);
        resBox.setLayoutParams(rlp);
        root.addView(resBox);

        // 常用直径表
        LinearLayout tb = cardBox(root);
        title(tb, "常用直径推荐（3 倍径以内）");
        TextView th = new TextView(this);
        th.setText("直径       转速 S        进给 F（mm/min）");
        th.setTextSize(11.5f);
        th.setTextColor(MainActivity.C_TEXT2);
        th.setPadding(0, dp(6), 0, dp(4));
        tb.addView(th);
        tableBox = new LinearLayout(this);
        tableBox.setOrientation(LinearLayout.VERTICAL);
        tb.addView(tableBox);

        // 新手说明
        LinearLayout note = cardBox(root);
        title(note, "怎么用、怎么微调");
        TextView nb = new TextView(this);
        nb.setText("转速：S = 1000 × Vc ÷ (3.14 × 直径)，Vc 是切削速度（m/min），刀样本上都有\n"
                + "进给：F = S × 每转进给，每转进给大约取 直径 的 0.8%～1.2%\n"
                + "倍径 = 孔深 ÷ 直径。3 倍径以内按表值；3～5 倍降 15%；超过 5 倍降 30%，并且必须分步钻\n"
                + "皇冠钻 / 合金钻：一定要内冷（M8 或内冷刀柄），铁屑能冲出来才不会挤刀\n"
                + "普通高速钢钻：深孔用 G83 啄钻，每次退刀排屑；转速别超 3000\n"
                + "不锈钢：转速再降一档，别让刀在同一个位置磨，容易硬化\n"
                + "铝：转速可以拉高、进给给足，排屑槽要大，别省冷却\n"
                + "表里是起点值：看铁屑颜色（发蓝=偏热）、听声音（尖叫=转速高或让刀），再上下调 10%～20%");
        nb.setTextSize(11.5f);
        nb.setTextColor(MainActivity.C_TEXT2);
        nb.setLineSpacing(dp(3), 1f);
        nb.setPadding(0, dp(6), 0, 0);
        note.addView(nb);

        setContentView(scroll);
        calc();
    }

    /** 核心计算 */
    private void calc() {
        double d = parse(eDia, 10);
        double deep = parse(eDeep, d * 3);
        if (d <= 0) d = 0.1;
        double vc = VC[tool][mat];
        double nRaw = 1000.0 * vc / (Math.PI * d);
        double ratio = deep / d;

        double nFac = ratio <= 3 ? 1.0 : (ratio <= 5 ? 0.85 : 0.7);
        double fFac = ratio <= 3 ? 1.0 : (ratio <= 5 ? 0.9 : 0.75);

        double n = nRaw * nFac;
        double nMax = tool == 2 ? 3000 : 5000;
        if (n > nMax) n = nMax;
        double frev = FREV_K[tool] * d * fFac;
        double f = n * frev;

        resBox.removeAllViews();
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(bg(MainActivity.C_CARD, 14));
        card.setPadding(dp(14), dp(12), dp(14), dp(14));
        resBox.addView(card);

        TextView head = new TextView(this);
        head.setText(TOOLS[tool].replace("（U 钻 / 可换头）", "") + "  Ø" + trim(d) + "  ·  "
                + MATERIALS[mat] + "  ·  " + trim(ratio) + " 倍径");
        head.setTextSize(12.5f);
        head.setTypeface(Typeface.DEFAULT_BOLD);
        head.setTextColor(MainActivity.C_TEXT2);
        card.addView(head);

        LinearLayout nums = new LinearLayout(this);
        nums.setOrientation(LinearLayout.HORIZONTAL);
        nums.setPadding(0, dp(10), 0, 0);
        card.addView(nums);
        bigNum(nums, "转速 S", String.valueOf((int) Math.round(n / 10.0) * 10), "r/min");
        bigNum(nums, "进给 F", String.valueOf((int) Math.round(f)), "mm/min");
        bigNum(nums, "每转进给", String.format("%.2f", frev), "mm/r");

        TextView tip = new TextView(this);
        tip.setText("校验：S×每转进给 = " + (int) Math.round(f) + " mm/min；FANUC 可写 F"
                + (int) Math.round(f) + "（G94）或每转 F" + String.format("%.2f", frev) + "（G95）");
        tip.setTextSize(11.5f);
        tip.setTextColor(MainActivity.C_ACCENT);
        tip.setLineSpacing(dp(2), 1f);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        tlp.topMargin = dp(10);
        tip.setLayoutParams(tlp);
        card.addView(tip);

        TextView warn = new TextView(this);
        warn.setText(advice(tool, mat, ratio, d));
        warn.setTextSize(11.5f);
        warn.setTextColor(MainActivity.C_TEXT2);
        warn.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams wlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        wlp.topMargin = dp(8);
        warn.setLayoutParams(wlp);
        card.addView(warn);

        // 表格
        tableBox.removeAllViews();
        for (int i = 0; i < DIA.length; i++) {
            double dd = DIA[i];
            double nn = 1000.0 * vc / (Math.PI * dd);
            double nmax2 = tool == 2 ? 3000 : 5000;
            if (nn > nmax2) nn = nmax2;
            double ff = nn * FREV_K[tool] * dd;
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setPadding(dp(6), dp(5), dp(6), dp(5));
            row.setBackground(bg(i % 2 == 0 ? MainActivity.C_FIELD : MainActivity.C_CARD, 8));
            cell(row, "Ø" + trim(dd), 1f, true, MainActivity.C_TEXT);
            cell(row, String.valueOf((int) Math.round(nn / 10.0) * 10) + " r/min", 1.3f, false, MainActivity.C_TEXT2);
            cell(row, String.valueOf((int) Math.round(ff)) + " mm/min", 1.4f, true, MainActivity.C_ACCENT);
            tableBox.addView(row);
        }
    }

    private String advice(int tool, int mat, double ratio, double d) {
        StringBuilder sb = new StringBuilder();
        if (ratio > 5) sb.append("• ").append(trim(ratio)).append(" 倍径属于深孔：必须分步钻（G83/Q 每次 2～3mm），并保证内冷\n");
        else if (ratio > 3) sb.append("• ").append(trim(ratio)).append(" 倍径：建议分两步钻，先钻一半深再钻到底\n");
        if (tool == 0) sb.append("• 皇冠钻是单刃可换头：每转进给别小于 ").append(String.format("%.2f", FREV_K[0] * d * 0.6)).append(" mm/r，太小会磨刀头\n");
        if (tool == 1) sb.append("• 合金钻：开始钻时先低速（S 的 50%）接触工件，钻入 1～2mm 再给全速\n");
        if (tool == 2) sb.append("• 普通高速钢钻：深孔一定用 G83 啄钻，转速别超 3000，冷却要足\n");
        if (mat == 1) sb.append("• 不锈钢：切屑容易粘刀，进给别太小，宁可慢一点也不要在原地磨\n");
        if (mat == 3) sb.append("• 铝：转速可以再高 20%，进给给足防止粘刀，注意排屑槽\n");
        sb.append("• 钻头直径大于 20 时优先用皇冠钻或合金钻，普通钻很难给到这个切削速度");
        return sb.toString();
    }

    // ---------- UI helper ----------
    private void addTopBar(LinearLayout root, String title, String sub) {
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
            public void onClick(View v) { finish(); }
        });
        bar.addView(back);

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tlp.leftMargin = dp(6);
        texts.setLayoutParams(tlp);

        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(20);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(MainActivity.C_TEXT);
        texts.addView(t);

        TextView s = new TextView(this);
        s.setText(sub);
        s.setTextSize(12);
        s.setTextColor(MainActivity.C_TEXT2);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        slp.topMargin = dp(2);
        s.setLayoutParams(slp);
        texts.addView(s);

        bar.addView(texts);
        LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        blp.bottomMargin = dp(10);
        bar.setLayoutParams(blp);
        root.addView(bar);
    }

    private LinearLayout cardBox(LinearLayout root) {
        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setBackground(bg(MainActivity.C_CARD, 14));
        c.setPadding(dp(14), dp(12), dp(14), dp(14));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(12);
        c.setLayoutParams(lp);
        root.addView(c);
        return c;
    }

    private void title(LinearLayout parent, String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(13.5f);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(MainActivity.C_TEXT);
        parent.addView(t);
    }

    private void label(LinearLayout parent, String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(11.5f);
        t.setTextColor(MainActivity.C_TEXT2);
        parent.addView(t);
    }

    private Spinner spinner(LinearLayout parent, String[] items) {
        Spinner sp = new Spinner(this);
        ArrayAdapter<String> ad = new ArrayAdapter<String>(this,
                android.R.layout.simple_spinner_item, items);
        ad.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        sp.setAdapter(ad);
        sp.setBackground(bg(MainActivity.C_FIELD, 10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(46));
        lp.topMargin = dp(4);
        sp.setLayoutParams(lp);
        parent.addView(sp);
        return sp;
    }

    private EditText numField(LinearLayout parent, String hint, String def, float weight, int leftMargin) {
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, weight);
        clp.leftMargin = leftMargin;
        col.setLayoutParams(clp);
        label(col, hint);
        EditText e = new EditText(this);
        e.setText(def);
        e.setTextSize(15);
        e.setTextColor(MainActivity.C_TEXT);
        e.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        e.setBackground(bg(MainActivity.C_FIELD, 10));
        e.setPadding(dp(12), dp(8), dp(12), dp(8));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(44));
        lp.topMargin = dp(4);
        e.setLayoutParams(lp);
        col.addView(e);
        parent.addView(col);
        return e;
    }

    private void bigNum(LinearLayout row, String caption, String value, String unit) {
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        col.setLayoutParams(lp);

        TextView v = new TextView(this);
        v.setText(value);
        v.setTextSize(22);
        v.setTypeface(Typeface.DEFAULT_BOLD);
        v.setTextColor(MainActivity.C_ACCENT);
        col.addView(v);

        TextView u = new TextView(this);
        u.setText(unit);
        u.setTextSize(10.5f);
        u.setTextColor(MainActivity.C_TEXT2);
        col.addView(u);

        TextView c = new TextView(this);
        c.setText(caption);
        c.setTextSize(11.5f);
        c.setTextColor(MainActivity.C_TEXT);
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        clp.topMargin = dp(2);
        c.setLayoutParams(clp);
        col.addView(c);

        row.addView(col);
    }

    private void cell(LinearLayout row, String text, float weight, boolean bold, int color) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(12.5f);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(color);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, weight);
        t.setLayoutParams(lp);
        row.addView(t);
    }

    private double parse(EditText e, double def) {
        try {
            String s = e.getText().toString().trim();
            if (s.length() == 0) return def;
            return Double.parseDouble(s);
        } catch (Exception ex) {
            return def;
        }
    }

    private String trim(double v) {
        if (Math.abs(v - Math.rint(v)) < 0.0001) return String.valueOf((long) Math.rint(v));
        return String.format("%.1f", v);
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
