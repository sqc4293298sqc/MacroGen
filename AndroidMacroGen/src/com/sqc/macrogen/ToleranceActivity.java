package com.sqc.macrogen;

import android.app.Activity;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/** 尺寸公差查询：H7、H8、g6、e7 等公差带的上下偏差与极限尺寸 */
public class ToleranceActivity extends Activity {

    private EditText eSize;
    private TextView lblResult, lblCode;
    private LinearLayout rowChips;
    private Button btnHole, btnShaft;
    private boolean isHole = true;
    private String pos = "H";
    private int grade = 7;

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

        // 基本尺寸
        card(root, "基本尺寸（mm）", null);
        eSize = new EditText(this);
        eSize.setText("30");
        eSize.setTextSize(15);
        eSize.setSingleLine(true);
        eSize.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        eSize.setTextColor(MainActivity.C_TEXT);
        eSize.setBackground(bg(MainActivity.C_FIELD, 8));
        eSize.setPadding(dp(10), dp(8), dp(10), dp(8));
        root.addView(eSize);

        // 孔 / 轴
        LinearLayout types = new LinearLayout(this);
        types.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        tlp.topMargin = dp(12);
        types.setLayoutParams(tlp);

        btnHole = typeBtn("孔（大写 H7 等）");
        btnShaft = typeBtn("轴（小写 h6 等）");
        types.addView(btnHole);
        types.addView(btnShaft);
        root.addView(types);
        btnHole.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) { isHole = true; pos = "H"; rebuildChips(); calc(); }
        });
        btnShaft.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) { isHole = false; pos = "h"; rebuildChips(); calc(); }
        });

        // 公差带
        card(root, "公差带代号", isHole ? "孔的常用偏差带：H 基孔制，G/F/E/D 为间隙孔" : "轴的常用偏差带：h 基轴制，g/f/e/d 间隙，k/m/n/p 过渡到过盈");
        HorizontalScrollView hs = new HorizontalScrollView(this);
        rowChips = new LinearLayout(this);
        rowChips.setOrientation(LinearLayout.HORIZONTAL);
        hs.addView(rowChips);
        root.addView(hs);

        // 等级
        card(root, "公差等级 IT", null);
        HorizontalScrollView hg = new HorizontalScrollView(this);
        LinearLayout grades = new LinearLayout(this);
        grades.setOrientation(LinearLayout.HORIZONTAL);
        for (int g = Tolerance.MIN_GRADE; g <= Tolerance.MAX_GRADE; g++) {
            final int gg = g;
            Button c = chip("IT" + g, false);
            c.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    grade = gg;
                    for (int i = 0; i < grades.getChildCount(); i++) {
                        Button cb = (Button) grades.getChildAt(i);
                        boolean on = (i + Tolerance.MIN_GRADE) == gg;
                        cb.setBackground(bg(on ? 0x1AFF6B1A : MainActivity.C_CARD, 8));
                        cb.setTextColor(on ? MainActivity.C_ACCENT : MainActivity.C_TEXT);
                    }
                    calc();
                }
            });
            grades.addView(c);
        }
        hg.addView(grades);
        root.addView(hg);

        // 结果
        LinearLayout res = new LinearLayout(this);
        res.setOrientation(LinearLayout.VERTICAL);
        res.setBackground(bg(MainActivity.C_CARD, 14));
        res.setPadding(dp(14), dp(14), dp(14), dp(14));
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rlp.topMargin = dp(16);
        res.setLayoutParams(rlp);

        lblCode = new TextView(this);
        lblCode.setTextSize(22);
        lblCode.setTypeface(Typeface.DEFAULT_BOLD);
        lblCode.setTextColor(MainActivity.C_ACCENT);
        res.addView(lblCode);

        lblResult = new TextView(this);
        lblResult.setTextSize(13);
        lblResult.setTextColor(MainActivity.C_TEXT);
        lblResult.setLineSpacing(dp(5), 1f);
        LinearLayout.LayoutParams txtlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        txtlp.topMargin = dp(8);
        lblResult.setLayoutParams(txtlp);
        res.addView(lblResult);
        root.addView(res);

        Button go = new Button(this);
        go.setText("查 询");
        go.setTextSize(15);
        go.setTypeface(Typeface.DEFAULT_BOLD);
        go.setAllCaps(false);
        go.setTextColor(0xFFFFFFFF);
        go.setBackground(rippleColor(MainActivity.C_ACCENT, 12));
        LinearLayout.LayoutParams glp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(48));
        glp.topMargin = dp(10);
        go.setLayoutParams(glp);
        go.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) { calc(); }
        });
        root.addView(go);

        // 常用配合
        card(root, "常用配合速查（Ø30 例）", "间隙/过渡/过盈一目了然，实际按图纸公称尺寸计算");
        String[][] fits = {{"H7", "g6"}, {"H7", "h6"}, {"H8", "f7"}, {"H7", "k6"},
                {"H7", "n6"}, {"H7", "p6"}, {"H9", "d9"}, {"H11", "d11"}};
        for (int i = 0; i < fits.length; i++) {
            addFit(root, "30", fits[i][0], fits[i][1]);
        }

        TextView tip = new TextView(this);
        tip.setText("说明：本表按 GB/T 1800.2 标准公差与基本偏差计算，单位 mm；数值四舍五入到 0.001mm。"
                + "\n加工时以图纸标注为准，公差带数字（如 H7）与实测尺寸对比即可判断合格。");
        tip.setTextSize(11);
        tip.setTextColor(MainActivity.C_TEXT2);
        tip.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams tpl = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        tpl.topMargin = dp(14);
        tip.setLayoutParams(tpl);
        root.addView(tip);

        setContentView(scroll);
        rebuildChips();
        calc();
    }

    private void rebuildChips() {
        rowChips.removeAllViews();
        btnHole.setBackground(rippleColor(isHole ? MainActivity.C_ACCENT : MainActivity.C_CARD, 10));
        btnHole.setTextColor(isHole ? 0xFFFFFFFF : MainActivity.C_TEXT);
        btnShaft.setBackground(rippleColor(!isHole ? MainActivity.C_ACCENT : MainActivity.C_CARD, 10));
        btnShaft.setTextColor(!isHole ? 0xFFFFFFFF : MainActivity.C_TEXT);

        String[] list = isHole ? Tolerance.HOLE_POS : Tolerance.SHAFT_POS;
        for (int i = 0; i < list.length; i++) {
            final String p = list[i];
            Button c = chip(p, p.equals(pos));
            c.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    pos = p;
                    rebuildChips();
                    calc();
                }
            });
            rowChips.addView(c);
        }
    }

    private void calc() {
        double size;
        try {
            size = Double.parseDouble(eSize.getText().toString().trim());
        } catch (Exception e) {
            Toast.makeText(this, "请输入正确的尺寸数字", Toast.LENGTH_SHORT).show();
            return;
        }
        if (size <= 0 || Tolerance.rangeIndex(size) < 0) {
            Toast.makeText(this, "本表适用 0～500mm", Toast.LENGTH_SHORT).show();
            return;
        }
        int[] d = isHole ? Tolerance.holeDev(pos, size, grade) : Tolerance.shaftDev(pos, size, grade);
        if (d == null) {
            lblCode.setText(pos + grade);
            lblResult.setText("该组合不在本表内");
            return;
        }
        String up = isHole ? "ES" : "es";
        String lo = isHole ? "EI" : "ei";
        boolean half = pos.equals("js") || pos.equals("JS");
        double max = size + (half ? d[2] / 2000.0 : d[0] / 1000.0);
        double min = size - (half ? d[2] / 2000.0 : -d[1] / 1000.0);
        lblCode.setText((isHole ? "Ø" : "Ø") + trim(size) + "  " + pos + grade);
        lblResult.setText(
                "上偏差 " + up + " = " + (half ? Tolerance.fmtHalf(d[2]) : Tolerance.fmt(d[0])) + " mm\n"
                        + "下偏差 " + lo + " = " + (half ? Tolerance.fmtHalf(-d[2]) : Tolerance.fmt(d[1])) + " mm\n"
                        + "公 差 = " + Tolerance.fmt(d[2]) + " mm（IT" + grade + "）\n"
                        + "最大极限 = " + String.format("%.3f", max) + " mm\n"
                        + "最小极限 = " + String.format("%.3f", min) + " mm");
    }

    private void addFit(LinearLayout root, String size, String hole, String shaft) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackground(bg(MainActivity.C_CARD, 12));
        card.setPadding(dp(12), dp(9), dp(12), dp(10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(7);
        card.setLayoutParams(lp);

        int hg = Integer.parseInt(hole.replaceAll("[^0-9]", ""));
        int sg = Integer.parseInt(shaft.replaceAll("[^0-9]", ""));
        TextView t = new TextView(this);
        t.setText("Ø" + size + "  " + hole + "/" + shaft + "  " + Tolerance.fitType(hole, shaft, 30, hg, sg));
        t.setTextSize(13);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(MainActivity.C_TEXT);
        card.addView(t);

        int[] h = Tolerance.holeDev(hole, 30, hg);
        int[] s = Tolerance.shaftDev(shaft, 30, sg);
        if (h != null && s != null) {
            int maxGap = h[0] - s[1];
            int minGap = h[1] - s[0];
            TextView d = new TextView(this);
            d.setText("孔 " + Tolerance.fmt(h[0]) + "/" + Tolerance.fmt(h[1])
                    + "    轴 " + Tolerance.fmt(s[0]) + "/" + Tolerance.fmt(s[1])
                    + "\n最大间隙 " + Tolerance.fmt(maxGap) + "   最小间隙 " + Tolerance.fmt(minGap));
            d.setTextSize(11.5f);
            d.setTextColor(MainActivity.C_TEXT2);
            d.setLineSpacing(dp(2), 1f);
            LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            dlp.topMargin = dp(5);
            d.setLayoutParams(dlp);
            card.addView(d);
        }
        root.addView(card);
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
        title.setText("尺寸公差查询");
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(MainActivity.C_TEXT);
        texts.addView(title);

        TextView sub = new TextView(this);
        sub.setText("H7 / H8 / G7 / e7 …上下偏差与极限尺寸");
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

    private void card(LinearLayout root, String title, String sub) {
        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(13.5f);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(MainActivity.C_TEXT);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(14);
        lp.bottomMargin = dp(6);
        t.setLayoutParams(lp);
        root.addView(t);
        if (sub != null) {
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
    }

    private Button typeBtn(String text) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(13);
        b.setAllCaps(false);
        b.setTextColor(MainActivity.C_TEXT);
        b.setBackground(rippleColor(MainActivity.C_CARD, 10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(42), 1f);
        lp.rightMargin = dp(8);
        b.setLayoutParams(lp);
        return b;
    }

    private Button chip(String text, boolean on) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(14);
        b.setAllCaps(false);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setTextColor(on ? MainActivity.C_ACCENT : MainActivity.C_TEXT);
        b.setBackground(bg(on ? 0x1AFF6B1A : MainActivity.C_CARD, 8));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(48), dp(40));
        lp.rightMargin = dp(6);
        b.setLayoutParams(lp);
        return b;
    }

    private GradientDrawable bg(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    private GradientDrawable rippleColor(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    private int dp(float v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
