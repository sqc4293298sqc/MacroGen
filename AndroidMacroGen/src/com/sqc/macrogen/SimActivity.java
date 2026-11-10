package com.sqc.macrogen;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.style.BackgroundColorSpan;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

/**
 * 程序模拟：用 MacroInterp 真执行 G 代码（含 #变量和 WHILE），
 * 再叠加单步、倍速、DRO 坐标、当前行高亮。
 */
public class SimActivity extends Activity {

    /** 由 ResultDialog 在 startActivity 前设置 */
    public static String code;
    public static GCode spec;

    private SimView view;
    private TextView droX, droY, droZ, lineTv, warnTv;
    private TextView codeTv;
    private SeekBar bar;
    private Button playBtn, speedBtn, viewBtn;
    private MacroInterp.Path data;

    private final Handler h = new Handler(Looper.getMainLooper());
    private boolean playing;
    private double speed = 1;
    private int lastLine = -2;

    private static final int ACC = MainActivity.C_ACCENT;

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            if (!playing || data == null) return;
            double step = data.maxLen / 15.0 * 0.04 * speed;   // 全程序约 15 秒走完
            double cur = curDist() + (step < 1 ? 1 : step);
            if (cur >= data.maxLen) {
                cur = data.maxLen;
                playing = false;
                playBtn.setText("播放");
            }
            setProgress(cur);
            if (playing) h.postDelayed(this, 40);
        }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        String src = code == null ? "" : code;
        data = MacroInterp.run(src);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(MainActivity.C_BG);
        root.setPadding(dp(12), dp(10), dp(12), dp(8));

        // 顶栏
        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);

        Button back = small("‹ 返回", MainActivity.C_FIELD, MainActivity.C_TEXT);
        back.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        });
        head.addView(back);

        TextView title = new TextView(this);
        title.setText("程序模拟 · 按 G 代码执行");
        title.setTextSize(15);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(MainActivity.C_TEXT);
        title.setPadding(dp(10), 0, 0, 0);
        title.setLayoutParams(new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        head.addView(title);

        Button imp = small("识别", MainActivity.C_FIELD, MainActivity.C_TEXT);
        imp.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                startActivity(new Intent(SimActivity.this, ImportActivity.class));
            }
        });
        LinearLayout.LayoutParams impLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        impLp.rightMargin = dp(6);
        imp.setLayoutParams(impLp);
        head.addView(imp);

        viewBtn = small("立体", MainActivity.C_FIELD, MainActivity.C_TEXT);
        viewBtn.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                boolean iso = viewBtn.getText().toString().equals("立体");
                view.setIso(!iso);
                viewBtn.setText(iso ? "俯视" : "立体");
            }
        });
        head.addView(viewBtn);
        root.addView(head);

        // 画布
        view = new SimView(this);
        view.setData(data, spec);
        LinearLayout.LayoutParams vlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1);
        vlp.topMargin = dp(8);
        view.setLayoutParams(vlp);
        root.addView(view);

        // 坐标读数
        LinearLayout dro = new LinearLayout(this);
        dro.setOrientation(LinearLayout.HORIZONTAL);
        dro.setBackground(round(MainActivity.C_CARD, 10));
        dro.setPadding(dp(12), dp(8), dp(12), dp(8));
        LinearLayout.LayoutParams dlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        dlp.topMargin = dp(8);
        dro.setLayoutParams(dlp);
        droX = droCell(dro, "X");
        droY = droCell(dro, "Y");
        droZ = droCell(dro, "Z");
        root.addView(dro);

        warnTv = new TextView(this);
        warnTv.setTextSize(10.5f);
        warnTv.setTextColor(MainActivity.C_TEXT2);
        warnTv.setPadding(dp(4), dp(4), dp(4), 0);
        warnTv.setText(data.error == null
                ? (data.pts.size() + " 个轨迹点 · 切削 "
                   + Math.round(data.totalCut) + " mm · 刀补按程序坐标显示")
                : ("⚠ " + data.error));
        root.addView(warnTv);

        // 进度条
        bar = new SeekBar(this);
        bar.setMax(1000);
        bar.setPadding(0, dp(4), 0, 0);
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean fromUser) {
                if (fromUser && data != null) {
                    playing = false;
                    playBtn.setText("播放");
                    setProgress(data.maxLen * p / 1000.0);
                }
            }
            @Override public void onStartTrackingTouch(SeekBar sb) { }
            @Override public void onStopTrackingTouch(SeekBar sb) { }
        });
        root.addView(bar);

        // 控制条
        LinearLayout ctl = new LinearLayout(this);
        ctl.setOrientation(LinearLayout.HORIZONTAL);
        ctl.setPadding(0, dp(2), 0, 0);

        playBtn = small("播放", ACC, Color.WHITE);
        playBtn.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (data == null) return;
                playing = !playing;
                playBtn.setText(playing ? "暂停" : "播放");
                if (playing) {
                    if (curDist() >= data.maxLen) setProgress(0);
                    h.post(tick);
                }
            }
        });
        ctl.addView(playBtn, weight());

        Button step = small("单步", MainActivity.C_FIELD, MainActivity.C_TEXT);
        step.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (data == null) return;
                playing = false;
                playBtn.setText("播放");
                double cur = curDist();
                int idx = indexAt(cur);
                int next = Math.min(idx + 1, data.pts.size() - 1);
                setProgress(data.dist.get(next));
            }
        });
        ctl.addView(step, weight());

        speedBtn = small("1×", MainActivity.C_FIELD, MainActivity.C_TEXT);
        speedBtn.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (speed == 1) speed = 2;
                else if (speed == 2) speed = 4;
                else if (speed == 4) speed = 0.5;
                else speed = 1;
                speedBtn.setText(speed == 0.5 ? "0.5×" : speed + "×");
            }
        });
        ctl.addView(speedBtn, weight());

        Button reset = small("复位", MainActivity.C_FIELD, MainActivity.C_TEXT);
        reset.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                playing = false;
                playBtn.setText("播放");
                setProgress(0);
            }
        });
        ctl.addView(reset, weight());
        root.addView(ctl);

        // 当前行
        lineTv = new TextView(this);
        lineTv.setTextSize(11);
        lineTv.setTypeface(Typeface.MONOSPACE);
        lineTv.setTextColor(MainActivity.C_TEXT);
        lineTv.setBackground(round(MainActivity.C_CARD, 8));
        lineTv.setPadding(dp(10), dp(6), dp(10), dp(6));
        LinearLayout.LayoutParams llp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        llp.topMargin = dp(6);
        lineTv.setLayoutParams(llp);
        lineTv.setSingleLine(true);
        lineTv.setEllipsize(android.text.TextUtils.TruncateAt.START);
        root.addView(lineTv);

        // 程序正文（高亮当前行）
        ScrollView sv = new ScrollView(this);
        sv.setBackground(round(0xFF111A24, 10));
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(140));
        slp.topMargin = dp(6);
        sv.setLayoutParams(slp);
        codeTv = new TextView(this);
        codeTv.setTextSize(11);
        codeTv.setTextColor(0xFFD6DEE8);
        codeTv.setTypeface(Typeface.MONOSPACE);
        codeTv.setPadding(dp(10), dp(8), dp(10), dp(8));
        codeTv.setLineSpacing(dp(1), 1f);
        sv.addView(codeTv);
        root.addView(sv);

        setContentView(root);
        lineTv.setText("按播放开始，或用 SeekBar / 单步逐段查看");
        highLight(-1);
    }

    private LinearLayout.LayoutParams weight() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        lp.rightMargin = dp(6);
        return lp;
    }

    private TextView droCell(LinearLayout parent, String name) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setLayoutParams(new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        TextView k = new TextView(this);
        k.setText(name);
        k.setTextSize(9.5f);
        k.setTextColor(MainActivity.C_TEXT2);
        box.addView(k);
        TextView v = new TextView(this);
        v.setText("0.000");
        v.setTextSize(14);
        v.setTypeface(Typeface.MONOSPACE);
        v.setTextColor(MainActivity.C_TEXT);
        box.addView(v);
        parent.addView(box);
        return v;
    }

    private double curDist() {
        return data == null ? 0 : view.getProgressDist();
    }

    private int indexAt(double d) {
        if (data == null) return 0;
        int lo = 0, hi = data.dist.size() - 1;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (data.dist.get(mid) < d) lo = mid + 1; else hi = mid;
        }
        return lo;
    }

    private void setProgress(double d) {
        view.setProgress(d);
        if (data == null) return;
        bar.setProgress((int) (d / Math.max(1, data.maxLen) * 1000));
        droX.setText(fmt(view.xAt()));
        droY.setText(fmt(view.yAt()));
        droZ.setText(fmt(view.zAt()));
        int line = view.lineAt();
        if (line != lastLine) {
            lastLine = line;
            highLight(line);
            if (line >= 0) {
                String t = codeLine(line);
                lineTv.setText("行 " + (line + 1) + " › " + t);
            }
        }
    }

    private String fmt(double v) {
        return String.format("%.3f", v);
    }

    private String codeLine(int idx) {
        String[] ls = (code == null ? "" : code).split("\n");
        if (idx < 0 || idx >= ls.length) return "";
        return ls[idx].trim();
    }

    private void highLight(int line) {
        String src = code == null ? "" : code;
        SpannableString sp;
        try {
            String[] ls = src.split("\n");
            StringBuilder sb = new StringBuilder();
            int start = 0, end = 0;
            for (int k = 0; k < ls.length; k++) {
                if (k == line) { start = sb.length(); }
                sb.append(ls[k]);
                if (k == line) { end = sb.length(); }
                if (k < ls.length - 1) sb.append("\n");
            }
            sp = new SpannableString(sb.toString());
            if (line >= 0 && end > start) {
                sp.setSpan(new BackgroundColorSpan(0x66FF6B1A), start, end,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
        } catch (Exception e) {
            sp = new SpannableString(src);
        }
        codeTv.setText(sp);
    }

    @Override
    protected void onPause() {
        playing = false;
        super.onPause();
    }

    private Button small(String t, int bg, int fg) {
        Button b = new Button(this);
        b.setText(t);
        b.setAllCaps(false);
        b.setTextSize(12);
        b.setTextColor(fg);
        b.setBackground(round(bg, 10));
        b.setMinHeight(dp(34));
        b.setMinimumHeight(dp(34));
        b.setPadding(dp(10), 0, dp(10), 0);
        return b;
    }

    private GradientDrawable round(int color, int r) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(r));
        return g;
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density);
    }
}
