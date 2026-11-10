package com.sqc.macrogen;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import java.util.List;
import java.util.Locale;

/** 刀路仿真：既能单独弹窗，也能直接嵌进"生成的宏程序"里 */
public class ToolpathDialog {

    public static void show(final Activity act, final GCode spec) {
        Dialog dlg = new Dialog(act);
        dlg.setTitle("刀路仿真");
        LinearLayout root = new LinearLayout(act);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xFFF4F6F8);
        root.setPadding(dp(act, 14), dp(act, 12), dp(act, 14), dp(act, 12));
        root.addView(build(act, spec));
        dlg.setContentView(root);
        dlg.show();
    }

    /** 返回一块可直接 addView 的仿真面板 */
    public static LinearLayout build(final Activity act, final GCode spec) {
        final List<Toolpath.Seg> segs = Toolpath.build(spec);

        final LinearLayout root = new LinearLayout(act);
        root.setOrientation(LinearLayout.VERTICAL);

        final ToolpathView view = new ToolpathView(act);
        view.setData(segs, (float) (spec.toolDia / 2.0),
                Toolpath.outline(spec), Toolpath.outlineBottom(spec));
        root.addView(view, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(act, 250)));

        final TextView info = new TextView(act);
        info.setTextSize(12);
        info.setTextColor(0xFF1B2431);
        info.setPadding(0, dp(act, 8), 0, dp(act, 4));
        root.addView(info);

        LinearLayout opts = new LinearLayout(act);
        opts.setOrientation(LinearLayout.HORIZONTAL);
        opts.setPadding(0, dp(act, 2), 0, 0);

        final Button isoBtn = new Button(act);
        isoBtn.setText("看立体");
        styleGhost(isoBtn);
        opts.addView(isoBtn, new LinearLayout.LayoutParams(0, dp(act, 40), 1f));

        final Button spdBtn = new Button(act);
        spdBtn.setText("速度 1×");
        styleGhost(spdBtn);
        LinearLayout.LayoutParams o2 = new LinearLayout.LayoutParams(0, dp(act, 40), 1f);
        o2.leftMargin = dp(act, 10);
        opts.addView(spdBtn, o2);
        root.addView(opts);

        final SeekBar bar = new SeekBar(act);
        bar.setMax(1000);
        root.addView(bar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout btns = new LinearLayout(act);
        btns.setOrientation(LinearLayout.HORIZONTAL);
        btns.setGravity(Gravity.CENTER_VERTICAL);
        btns.setPadding(0, dp(act, 4), 0, 0);

        final Button play = new Button(act);
        play.setText("暂停");
        styleBtn(play);
        btns.addView(play, new LinearLayout.LayoutParams(0, dp(act, 42), 1f));

        Button reset = new Button(act);
        reset.setText("重播");
        styleBtn(reset);
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(0, dp(act, 42), 1f);
        rlp.leftMargin = dp(act, 10);
        btns.addView(reset, rlp);

        root.addView(btns);

        final Handler h = new Handler(Looper.getMainLooper());
        final float[] speeds = {1f, 2f, 4f, 0.5f};
        final int[] spdIdx = {0};
        final boolean[] playing = {true};
        final float[] prog = {0f};

        final Runnable tick = new Runnable() {
            @Override
            public void run() {
                if (!playing[0]) return;
                prog[0] += 0.006f * speeds[spdIdx[0]];
                if (prog[0] > 1f) prog[0] = 1f;
                view.setProgress(prog[0]);
                bar.setProgress((int) (prog[0] * 1000));
                info.setText(String.format(Locale.US,
                        "进度 %d%%   当前 Z = %.2f   共 %d 段轨迹",
                        (int) (prog[0] * 100), view.getCutZ(), segs.size()));
                if (prog[0] < 1f) h.postDelayed(this, 40);
                else playing[0] = false;
            }
        };

        isoBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                view.setIso(!view.isIso());
                isoBtn.setText(view.isIso() ? "看俯视" : "看立体");
            }
        });
        spdBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                spdIdx[0] = (spdIdx[0] + 1) % speeds.length;
                spdBtn.setText("速度 " + (speeds[spdIdx[0]] == 0.5f
                        ? "0.5×" : (int) speeds[spdIdx[0]] + "×"));
            }
        });
        play.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                playing[0] = !playing[0];
                if (playing[0] && prog[0] >= 1f) prog[0] = 0f;
                play.setText(playing[0] ? "暂停" : "播放");
                if (playing[0]) h.post(tick);
            }
        });
        reset.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                prog[0] = 0f;
                playing[0] = true;
                play.setText("暂停");
                h.removeCallbacks(tick);
                h.post(tick);
            }
        });
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar sb, int p, boolean fromUser) {
                if (!fromUser) return;
                prog[0] = p / 1000f;
                view.setProgress(prog[0]);
                info.setText(String.format(Locale.US,
                        "进度 %d%%   当前 Z = %.2f   共 %d 段轨迹",
                        (int) (prog[0] * 100), view.getCutZ(), segs.size()));
            }

            @Override public void onStartTrackingTouch(SeekBar sb) { playing[0] = false; play.setText("播放"); }
            @Override public void onStopTrackingTouch(SeekBar sb) { }
        });

        // 挂到窗口才开始跑，离开窗口就停（不会在后台空转）
        root.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(View v) {
                playing[0] = true;
                play.setText("暂停");
                h.removeCallbacks(tick);
                h.post(tick);
            }

            @Override
            public void onViewDetachedFromWindow(View v) {
                playing[0] = false;
                h.removeCallbacksAndMessages(null);
            }
        });
        return root;
    }

    private static void styleGhost(Button b) {
        b.setTextSize(13);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setTextColor(0xFF1B2431);
        GradientDrawable g = new GradientDrawable();
        g.setColor(0xFFFFFFFF);
        g.setCornerRadius(20);
        b.setBackground(g);
    }

    private static void styleBtn(Button b) {
        b.setTextSize(13);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setTextColor(Color.WHITE);
        GradientDrawable g = new GradientDrawable();
        g.setColor(0xFFFF6B1A);
        g.setCornerRadius(22);
        b.setBackground(g);
    }

    private static int dp(Activity a, int v) {
        return (int) (v * a.getResources().getDisplayMetrics().density + 0.5f);
    }
}
