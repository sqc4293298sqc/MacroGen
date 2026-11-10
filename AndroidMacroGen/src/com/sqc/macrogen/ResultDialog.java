package com.sqc.macrogen;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public class ResultDialog {

    public static void show(final Activity act, final GCode spec, final String code, final String fileName, final String manual) {
        LinearLayout box = new LinearLayout(act);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(act, 2), dp(act, 2), dp(act, 2), dp(act, 2));

        TextView meta = new TextView(act);
        meta.setText(code.split("\n").length + " 行 · " + code.length() + " 字符");
        meta.setTextSize(11);
        meta.setTextColor(MainActivity.C_TEXT2);
        meta.setPadding(dp(act, 4), 0, 0, dp(act, 6));
        box.addView(meta);

        ScrollView sv = new ScrollView(act);
        sv.setBackground(round(act, 0xFF111A24, 12));

        TextView tv = new TextView(act);
        tv.setText(code);
        tv.setTextSize(11);
        tv.setTextColor(0xFFD6DEE8);
        tv.setTypeface(Typeface.MONOSPACE);
        tv.setTextIsSelectable(true);
        tv.setLineSpacing(dp(act, 2), 1f);
        tv.setPadding(dp(act, 10), dp(act, 10), dp(act, 10), dp(act, 10));
        sv.addView(tv);
        box.addView(sv, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(act, 240)));

        TextView simTitle = new TextView(act);
        simTitle.setText("刀路仿真（俯视 / 立体 / 倍速）");
        simTitle.setTextSize(13);
        simTitle.setTypeface(Typeface.DEFAULT_BOLD);
        simTitle.setTextColor(MainActivity.C_TEXT);
        simTitle.setPadding(dp(act, 4), dp(act, 12), dp(act, 4), dp(act, 4));
        box.addView(simTitle);

        LinearLayout simCard = new LinearLayout(act);
        simCard.setOrientation(LinearLayout.VERTICAL);
        simCard.setBackground(round(act, MainActivity.C_CARD, 12));
        simCard.setPadding(dp(act, 8), dp(act, 6), dp(act, 8), dp(act, 6));
        simCard.addView(ToolpathDialog.build(act, spec));
        box.addView(simCard);

        LinearLayout btnRow = new LinearLayout(act);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        blp.topMargin = dp(act, 12);
        btnRow.setLayoutParams(blp);

        Button copy = styledBtn(act, "复制", 0xFFF1F3F6, MainActivity.C_TEXT);
        copy.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                ClipboardManager cm = (ClipboardManager) act.getSystemService(Context.CLIPBOARD_SERVICE);
                cm.setPrimaryClip(ClipData.newPlainText("gcode", code));
                Toast.makeText(act, "已复制到剪贴板", Toast.LENGTH_SHORT).show();
            }
        });

        Button share = styledBtn(act, "分享", 0xFFF1F3F6, MainActivity.C_TEXT);
        share.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent i = new Intent(Intent.ACTION_SEND);
                i.setType("text/plain");
                i.putExtra(Intent.EXTRA_TEXT, code);
                act.startActivity(Intent.createChooser(i, "发送宏程序"));
            }
        });

        Button save = styledBtn(act, "保存 .nc", MainActivity.C_ACCENT, Color.WHITE);
        save.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                MainActivity.saveFile(act, code, fileName);
            }
        });

        LinearLayout.LayoutParams one = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        one.rightMargin = dp(act, 6);
        btnRow.addView(copy, one);
        LinearLayout.LayoutParams two = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        two.rightMargin = dp(act, 6);
        btnRow.addView(share, two);
        btnRow.addView(save, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));

        box.addView(btnRow);

        Button sim = styledBtn(act, "程序模拟 › 按 G 代码逐段走刀（含 #变量 / WHILE）", MainActivity.C_TEXT, 0xFFEAF0F7);
        LinearLayout.LayoutParams simLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(act, 44));
        simLp.topMargin = dp(act, 8);
        sim.setLayoutParams(simLp);
        sim.setTextSize(12.5f);
        sim.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                SimActivity.code = code;
                SimActivity.spec = spec;
                act.startActivity(new Intent(act, SimActivity.class));
            }
        });
        box.addView(sim);

        final TextView manTitle = new TextView(act);
        manTitle.setText("使用说明（点开看每个变量怎么改）");
        manTitle.setTextSize(13);
        manTitle.setTypeface(Typeface.DEFAULT_BOLD);
        manTitle.setTextColor(MainActivity.C_TEXT);
        manTitle.setPadding(dp(act, 4), dp(act, 12), dp(act, 4), dp(act, 4));

        final ScrollView manBox = new ScrollView(act);
        manBox.setBackground(round(act, 0xFFF7F8FA, 12));
        manBox.setVisibility(View.GONE);
        TextView manTv = new TextView(act);
        manTv.setText(manual);
        manTv.setTextSize(12);
        manTv.setTextColor(0xFF3A4553);
        manTv.setLineSpacing(dp(act, 3), 1f);
        manTv.setPadding(dp(act, 12), dp(act, 12), dp(act, 12), dp(act, 12));
        manTv.setTextIsSelectable(true);
        manBox.addView(manTv);
        manBox.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(act, 260)));

        manTitle.setOnClickListener(new View.OnClickListener() {
            private boolean open = false;
            @Override
            public void onClick(View v) {
                open = !open;
                manBox.setVisibility(open ? View.VISIBLE : View.GONE);
                manTitle.setText(open ? "使用说明（收起）" : "使用说明（点开看每个变量怎么改）");
            }
        });

        box.addView(manTitle);
        box.addView(manBox);

        ScrollView page = new ScrollView(act);
        page.addView(box);

        new AlertDialog.Builder(act)
                .setTitle("生成的宏程序")
                .setView(page)
                .setNegativeButton("关闭", null)
                .show();
    }

    static Button styledBtn(Activity act, String text, int bg, int fg) {
        Button b = new Button(act);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(13);
        b.setTextColor(fg);
        b.setBackground(round(act, bg, 12));
        return b;
    }

    static GradientDrawable round(Activity act, int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.RECTANGLE);
        g.setColor(color);
        g.setCornerRadius(dp(act, radiusDp));
        return g;
    }

    static int dp(Activity a, int v) {
        return (int) (v * a.getResources().getDisplayMetrics().density);
    }
}
