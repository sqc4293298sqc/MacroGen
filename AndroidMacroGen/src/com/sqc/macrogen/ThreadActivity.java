package com.sqc.macrogen;

import android.app.Activity;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** 丝锥底孔查询：螺距、切削丝锥底孔、挤压丝锥底孔、推荐钻头 */
public class ThreadActivity extends Activity {

    // 公制粗牙：规格直径, 螺距
    private static final double[][] M_COARSE = {
            {1, 0.25}, {1.2, 0.25}, {1.4, 0.3}, {1.6, 0.35}, {1.8, 0.35}, {2, 0.4},
            {2.2, 0.45}, {2.5, 0.45}, {3, 0.5}, {3.5, 0.6}, {4, 0.7}, {5, 0.8},
            {6, 1.0}, {7, 1.0}, {8, 1.25}, {10, 1.5}, {12, 1.75}, {14, 2.0},
            {16, 2.0}, {18, 2.5}, {20, 2.5}, {22, 2.5}, {24, 3.0}, {27, 3.0},
            {30, 3.5}, {33, 3.5}, {36, 4.0}, {39, 4.0}, {42, 4.5}, {45, 4.5},
            {48, 5.0}, {52, 5.0}, {56, 5.5}, {60, 5.5}, {64, 6.0}, {68, 6.0},
            {72, 6.0}, {76, 6.0}, {80, 6.0}
    };

    // 公制细牙：直径, 螺距
    private static final double[][] M_FINE = {
            {8, 1.0}, {10, 1.0}, {10, 1.25}, {12, 1.25}, {12, 1.5}, {14, 1.5},
            {15, 1.5}, {16, 1.5}, {18, 1.5}, {18, 2.0}, {20, 1.5}, {20, 2.0},
            {22, 1.5}, {22, 2.0}, {24, 1.5}, {24, 2.0}, {27, 2.0}, {30, 2.0},
            {33, 2.0}, {36, 2.0}, {36, 3.0}, {39, 3.0}, {42, 3.0}, {45, 3.0},
            {48, 3.0}, {52, 4.0}
    };

    // 管螺纹 G（55°）：规格, 每英寸牙数, 螺距mm, 底孔
    private static final String[][] G_THREAD = {
            {"G1/8", "28", "0.907", "8.80"},
            {"G1/4", "19", "1.337", "11.80"},
            {"G3/8", "19", "1.337", "15.25"},
            {"G1/2", "14", "1.814", "18.70"},
            {"G5/8", "14", "1.814", "20.70"},
            {"G3/4", "14", "1.814", "24.50"},
            {"G7/8", "14", "1.814", "28.20"},
            {"G1", "11", "2.309", "30.50"},
            {"G1-1/8", "11", "2.309", "35.00"},
            {"G1-1/4", "11", "2.309", "39.00"},
            {"G1-1/2", "11", "2.309", "45.00"},
            {"G2", "11", "2.309", "57.00"}
    };

    // 美制 NPT 锥管（60°）：规格, 牙数, 螺距mm, 底孔（小端）
    private static final String[][] NPT = {
            {"NPT1/8", "27", "0.941", "8.60"},
            {"NPT1/4", "18", "1.411", "11.10"},
            {"NPT3/8", "18", "1.411", "14.70"},
            {"NPT1/2", "14", "1.814", "18.00"},
            {"NPT3/4", "14", "1.814", "23.40"},
            {"NPT1", "11.5", "2.209", "29.50"},
            {"NPT1-1/4", "11.5", "2.209", "38.50"},
            {"NPT1-1/2", "11.5", "2.209", "44.50"}
    };

    // 美制统一螺纹：规格, 牙数, 螺距mm, 底孔（切削丝锥）
    private static final String[][] UNC = {
            {"1/4-20UNC", "20", "1.270", "5.10"},
            {"5/16-18UNC", "18", "1.411", "6.60"},
            {"3/8-16UNC", "16", "1.588", "8.00"},
            {"7/16-14UNC", "14", "1.814", "9.40"},
            {"1/2-13UNC", "13", "1.954", "10.80"},
            {"5/8-11UNC", "11", "2.309", "13.70"},
            {"3/4-10UNC", "10", "2.540", "16.60"},
            {"7/8-9UNC", "9", "2.822", "19.50"},
            {"1-8UNC", "8", "3.175", "22.20"},
            {"1/4-28UNF", "28", "0.907", "5.50"},
            {"5/16-24UNF", "24", "1.058", "7.00"},
            {"3/8-24UNF", "24", "1.058", "8.60"},
            {"1/2-20UNF", "20", "1.270", "11.50"},
            {"5/8-18UNF", "18", "1.411", "14.50"}
    };

    private static final String[] TABS = {"公制粗牙", "公制细牙", "管螺纹 G", "NPT 锥管", "美制 UNC/UNF"};
    private int tab = 0;
    private LinearLayout listBox, tabRow;
    private TextView lblTitle;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(MainActivity.C_BG);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(24));
        scroll.addView(root);

        addTopBar(root);

        // 丝锥底孔计算公式说明
        LinearLayout formula = new LinearLayout(this);
        formula.setOrientation(LinearLayout.VERTICAL);
        formula.setBackground(bg(MainActivity.C_CARD, 14));
        formula.setPadding(dp(14), dp(12), dp(14), dp(12));
        TextView ft = new TextView(this);
        ft.setText("底孔怎么算");
        ft.setTextSize(13.5f);
        ft.setTypeface(Typeface.DEFAULT_BOLD);
        ft.setTextColor(MainActivity.C_TEXT);
        formula.addView(ft);
        TextView fb = new TextView(this);
        fb.setText("切削丝锥（普通丝锥）：底孔 = 公称直径 − 螺距\n"
                + "挤压丝锥（无屑丝锥）：底孔 ≈ 公称直径 − 螺距/2（表中第 4 列）\n"
                + "攻丝进给：F = 螺距（mm/r），转速×螺距要等于进给，例 M10×1.5、S400 → F1.5\n"
                + "铝/铜等软料取表中值；不锈钢、调质钢底孔取大 0.05～0.1，防止丝锥挤死。\n"
                + "实际按 0.05mm 就近选钻头：M8 算出 6.75 → 用 6.8 钻头。");
        fb.setTextSize(11.5f);
        fb.setTextColor(MainActivity.C_TEXT2);
        fb.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        flp.topMargin = dp(6);
        fb.setLayoutParams(flp);
        formula.addView(fb);
        LinearLayout.LayoutParams boxlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        boxlp.topMargin = dp(12);
        formula.setLayoutParams(boxlp);
        root.addView(formula);

        // 分类切换
        HorizontalScrollView hs = new HorizontalScrollView(this);
        tabRow = new LinearLayout(this);
        tabRow.setOrientation(LinearLayout.HORIZONTAL);
        hs.addView(tabRow);
        LinearLayout.LayoutParams hlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        hlp.topMargin = dp(14);
        hs.setLayoutParams(hlp);
        root.addView(hs);

        lblTitle = new TextView(this);
        lblTitle.setTextSize(12);
        lblTitle.setTextColor(MainActivity.C_TEXT2);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        tlp.topMargin = dp(12);
        tlp.bottomMargin = dp(8);
        lblTitle.setLayoutParams(tlp);
        root.addView(lblTitle);

        listBox = new LinearLayout(this);
        listBox.setOrientation(LinearLayout.VERTICAL);
        root.addView(listBox);

        setContentView(scroll);
        rebuildTabs();
    }

    private void rebuildTabs() {
        tabRow.removeAllViews();
        for (int i = 0; i < TABS.length; i++) {
            final int idx = i;
            Button c = new Button(this);
            c.setText(TABS[i]);
            c.setTextSize(13);
            c.setAllCaps(false);
            c.setTypeface(Typeface.DEFAULT_BOLD);
            boolean on = idx == tab;
            c.setTextColor(on ? 0xFFFFFFFF : MainActivity.C_TEXT);
            c.setBackground(bg(on ? MainActivity.C_ACCENT : MainActivity.C_CARD, 9));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, dp(38));
            lp.rightMargin = dp(8);
            c.setLayoutParams(lp);
            c.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    tab = idx;
                    rebuildTabs();
                }
            });
            tabRow.addView(c);
        }
        renderList();
    }

    private void renderList() {
        listBox.removeAllViews();
        if (tab == 0 || tab == 1) {
            double[][] data = tab == 0 ? M_COARSE : M_FINE;
            lblTitle.setText(tab == 0 ? "公制粗牙螺纹（M）——常用规格"
                    : "公制细牙螺纹（M × 螺距）——常用规格");
            addHeader("规格", "螺距", "切削底孔", "挤压底孔");
            for (int i = 0; i < data.length; i++) {
                double d = data[i][0], p = data[i][1];
                addRow(cutName("M", d, p, tab == 0), trim(p),
                        String.format("%.2f", d - p), String.format("%.2f", d - p / 2.0));
            }
        } else if (tab == 2) {
            lblTitle.setText("55° 圆柱管螺纹（G）——每英寸牙数 / 底孔");
            addHeader("规格", "牙/寸", "螺距", "底孔");
            for (int i = 0; i < G_THREAD.length; i++) {
                addRow(G_THREAD[i][0], G_THREAD[i][1], G_THREAD[i][2], G_THREAD[i][3]);
            }
        } else if (tab == 3) {
            lblTitle.setText("60° 圆锥管螺纹（NPT）——底孔给小端尺寸，攻丝后自然成锥");
            addHeader("规格", "牙/寸", "螺距", "小端底孔");
            for (int i = 0; i < NPT.length; i++) {
                addRow(NPT[i][0], NPT[i][1], NPT[i][2], NPT[i][3]);
            }
        } else {
            lblTitle.setText("美制统一螺纹 UNC（粗牙）/ UNF（细牙）——底孔按切削丝锥");
            addHeader("规格", "牙/寸", "螺距", "底孔");
            for (int i = 0; i < UNC.length; i++) {
                addRow(UNC[i][0], UNC[i][1], UNC[i][2], UNC[i][3]);
            }
        }
    }

    private String cutName(String prefix, double d, double p, boolean coarse) {
        String dia = trim(d);
        if (coarse) return "M" + dia;
        return "M" + dia + "×" + trim(p);
    }

    private void addHeader(String a, String b, String c, String d) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(dp(12), dp(2), dp(12), dp(4));
        addCell(row, a, 1.6f, true, MainActivity.C_TEXT2);
        addCell(row, b, 0.9f, true, MainActivity.C_TEXT2);
        addCell(row, c, 1.2f, true, MainActivity.C_TEXT2);
        addCell(row, d, 1.2f, true, MainActivity.C_TEXT2);
        listBox.addView(row);
    }

    private void addRow(String name, String pitch, String drill, String sq) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setBackground(bg(MainActivity.C_CARD, 10));
        row.setPadding(dp(12), dp(9), dp(12), dp(9));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(6);
        row.setLayoutParams(lp);

        addCell(row, name, 1.6f, true, MainActivity.C_TEXT);
        addCell(row, pitch, 0.9f, false, MainActivity.C_TEXT2);
        addCell(row, drill, 1.2f, true, MainActivity.C_ACCENT);
        addCell(row, sq, 1.2f, false, MainActivity.C_TEXT2);
        listBox.addView(row);
    }

    private void addCell(LinearLayout row, String text, float weight, boolean bold, int color) {
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

    private String trim(double v) {
        if (Math.abs(v - Math.rint(v)) < 0.0001) return String.valueOf((long) Math.rint(v));
        return String.valueOf(v);
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
            public void onClick(View v) { finish(); }
        });
        bar.addView(back);

        LinearLayout texts = new LinearLayout(this);
        texts.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tlp.leftMargin = dp(6);
        texts.setLayoutParams(tlp);

        TextView title = new TextView(this);
        title.setText("丝锥底孔查询");
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(MainActivity.C_TEXT);
        texts.addView(title);

        TextView sub = new TextView(this);
        sub.setText("螺距 · 底孔 · 该用多大的钻头");
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
