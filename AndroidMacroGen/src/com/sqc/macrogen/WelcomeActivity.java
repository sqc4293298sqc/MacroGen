package com.sqc.macrogen;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

public class WelcomeActivity extends Activity {

    static final int C_ACCENT = 0xFFFF6B1A;
    static final int C_TEXT = 0xFF1B2431;
    static final int C_TEXT2 = 0xFF7A8595;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(dp(28), dp(56), dp(28), dp(36));

        ImageView img = new ImageView(this);
        img.setImageResource(R.drawable.welcome);
        img.setScaleType(ImageView.ScaleType.FIT_CENTER);
        LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        img.setLayoutParams(ip);
        root.addView(img);

        TextView title = new TextView(this);
        title.setText("宏程序生成器");
        title.setTextColor(C_TEXT);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        tp.topMargin = dp(26);
        root.addView(title, tp);

        TextView sub = new TextView(this);
        sub.setText("方形型腔 · 锥孔 · FANUC 宏程序");
        sub.setTextColor(C_TEXT2);
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        sub.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        sp.topMargin = dp(8);
        root.addView(sub, sp);

        Button enter = new Button(this);
        enter.setText("进入程序");
        enter.setTextColor(Color.WHITE);
        enter.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        enter.setTypeface(Typeface.DEFAULT_BOLD);
        enter.setAllCaps(false);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(C_ACCENT);
        bg.setCornerRadius(dp(14));
        RippleDrawable ripple = new RippleDrawable(
                ColorStateList.valueOf(0x33FFFFFF), bg, null);
        enter.setBackground(ripple);
        enter.setPadding(0, dp(14), 0, dp(14));
        LinearLayout.LayoutParams ep = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        ep.topMargin = dp(30);
        enter.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(WelcomeActivity.this, MainActivity.class));
                finish();
            }
        });
        root.addView(enter, ep);

        TextView sign = new TextView(this);
        sign.setText("当里个当制作");
        sign.setTextColor(0xFF33404F);
        sign.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        sign.setTypeface(Typeface.DEFAULT_BOLD);
        sign.setLetterSpacing(0.22f);
        sign.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams gsp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        gsp.topMargin = dp(24);
        root.addView(sign, gsp);

        setContentView(root);
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }
}
