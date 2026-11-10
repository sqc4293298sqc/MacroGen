package com.sqc.macrogen;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;

/**
 * 导入程序：拍照 / 相册 / 文件 / 粘贴 → （可选）OCR 自动识别 → 清洗 → 直接送进模拟。
 * OCR 走 ocr.space（免费 key，一天约 25 次），key 存在本地，不填也能手工粘贴。
 */
public class ImportActivity extends Activity {

    private static final int REQ_CAM = 11, REQ_PICK = 12, REQ_FILE = 13;
    private static final String API = "https://api.ocr.space/parse/image";

    private ImageView thumb;
    private EditText edit;
    private TextView tip;
    private Bitmap bitmap;
    private Uri camUri;
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(MainActivity.C_BG);
        root.setPadding(dp(12), dp(10), dp(12), dp(10));

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
        title.setText("识别 / 导入程序");
        title.setTextSize(15);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(MainActivity.C_TEXT);
        title.setPadding(dp(10), 0, 0, 0);
        title.setLayoutParams(new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        head.addView(title);

        Button key = small("识别 Key", MainActivity.C_FIELD, MainActivity.C_TEXT);
        key.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { askKey(); }
        });
        head.addView(key);
        root.addView(head);

        TextView sub = new TextView(this);
        sub.setText("拍照或截图 → 自动识别成文字 → 一键送进程序模拟");
        sub.setTextSize(11);
        sub.setTextColor(MainActivity.C_TEXT2);
        sub.setPadding(dp(4), dp(6), dp(4), dp(6));
        root.addView(sub);

        // 图片来源
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);

        Button cam = small("拍照", MainActivity.C_CARD, MainActivity.C_TEXT);
        cam.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { shoot(); }
        });
        row.addView(cam, weight());

        Button pick = small("相册选图", MainActivity.C_CARD, MainActivity.C_TEXT);
        pick.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                i.setType("image/*");
                i.addCategory(Intent.CATEGORY_OPENABLE);
                startActivityForResult(i, REQ_PICK);
            }
        });
        row.addView(pick, weight());

        Button file = small("选文件 .txt", MainActivity.C_CARD, MainActivity.C_TEXT);
        file.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                i.setType("*/*");
                i.addCategory(Intent.CATEGORY_OPENABLE);
                startActivityForResult(i, REQ_FILE);
            }
        });
        row.addView(file, weight());
        root.addView(row);

        // 图片预览
        thumb = new ImageView(this);
        thumb.setScaleType(ImageView.ScaleType.FIT_CENTER);
        thumb.setBackgroundColor(0xFF111A24);
        thumb.setVisibility(View.GONE);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(150));
        tlp.topMargin = dp(8);
        thumb.setLayoutParams(tlp);
        root.addView(thumb);

        // 识别 + 粘贴
        LinearLayout act = new LinearLayout(this);
        act.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams alp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(46));
        alp.topMargin = dp(8);
        act.setLayoutParams(alp);

        Button ocr = small("开始识别", MainActivity.C_ACCENT, Color.WHITE);
        ocr.setTextSize(14);
        ocr.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { runOcr(); }
        });
        act.addView(ocr, weight());

        Button paste = small("粘贴", MainActivity.C_CARD, MainActivity.C_TEXT);
        paste.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { pasteClip(); }
        });
        act.addView(paste, weight());
        root.addView(act);

        tip = new TextView(this);
        tip.setTextSize(10.5f);
        tip.setTextColor(MainActivity.C_TEXT2);
        tip.setPadding(dp(4), dp(5), dp(4), dp(4));
        tip.setText(hasKey() ? "已配置识别 Key，拍完点「开始识别」即可"
                : "未配置 Key：可先粘贴文字，或点右上「识别 Key」填一个免费 key");
        root.addView(tip);

        // 文本区
        edit = new EditText(this);
        edit.setHint("识别结果 / 粘贴的程序会显示在这里，可直接改错字");
        edit.setTextSize(11);
        edit.setTypeface(Typeface.MONOSPACE);
        edit.setTextColor(MainActivity.C_TEXT);
        edit.setBackground(round(MainActivity.C_CARD, 10));
        edit.setPadding(dp(10), dp(8), dp(10), dp(8));
        edit.setGravity(Gravity.TOP);
        edit.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        edit.setMinLines(6);
        LinearLayout.LayoutParams elp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1);
        elp.topMargin = dp(6);
        edit.setLayoutParams(elp);
        root.addView(edit);

        // 底部动作
        LinearLayout foot = new LinearLayout(this);
        foot.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(48));
        flp.topMargin = dp(8);
        foot.setLayoutParams(flp);

        Button clean = small("清洗格式", MainActivity.C_FIELD, MainActivity.C_TEXT);
        clean.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                String src = edit.getText().toString();
                String out = clean(src);
                edit.setText(out);
                toast("已清洗，剩 " + out.split("\n").length + " 行");
            }
        });
        foot.addView(clean, weight());

        Button go = small("送去模拟 ›", MainActivity.C_ACCENT, Color.WHITE);
        go.setTextSize(14);
        go.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                String code = edit.getText().toString().trim();
                if (code.isEmpty()) { toast("还没有程序内容"); return; }
                SimActivity.code = code;
                SimActivity.spec = null;
                startActivity(new Intent(ImportActivity.this, SimActivity.class));
            }
        });
        foot.addView(go, weight());
        root.addView(foot);

        setContentView(root);
    }

    // ---------- 拍照 ----------
    private void shoot() {
        File f = new File(getCacheDir(), "ocr_" + System.currentTimeMillis() + ".jpg");
        camUri = PhotoProvider.uriFor(this, f.getName());
        try {
            Intent i = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            i.putExtra(MediaStore.EXTRA_OUTPUT, camUri);
            i.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivityForResult(i, REQ_CAM);
        } catch (Exception e) {
            toast("没有找到相机应用");
        }
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (res != RESULT_OK) return;
        if (req == REQ_CAM) {
            loadFromUri(camUri, 0, 0);
        } else if (req == REQ_PICK && data != null && data.getData() != null) {
            loadFromUri(data.getData(), 90, -90);
        } else if (req == REQ_FILE && data != null && data.getData() != null) {
            readText(data.getData());
        }
    }

    /** rotate：照片拍出来方向可能不对，旋转复选框由用户点两次切换 */
    private void loadFromUri(Uri uri, int o1, int o2) {
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            Bitmap bm = BitmapFactory.decodeStream(is);
            if (is != null) is.close();
            if (bm == null) { toast("图片读取失败"); return; }
            bitmap = bm;
            thumb.setImageBitmap(bm);
            thumb.setVisibility(View.VISIBLE);
            tip.setText("图片已就绪（" + bm.getWidth() + "×" + bm.getHeight()
                    + "），点「开始识别」；识别不准就直接改下面的字");
        } catch (Exception e) {
            toast("图片读取失败：" + e.getMessage());
        }
    }

    // ---------- 选文件 ----------
    private void readText(Uri uri) {
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            BufferedReader r = new BufferedReader(new InputStreamReader(is, "UTF-8"));
            StringBuilder sb = new StringBuilder();
            String l;
            while ((l = r.readLine()) != null) sb.append(l).append('\n');
            r.close();
            edit.setText(clean(sb.toString()));
            tip.setText("已从文件导入 " + edit.getText().toString().split("\n").length + " 行");
        } catch (Exception e) {
            toast("文件读取失败：" + e.getMessage());
        }
    }

    private void pasteClip() {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm == null || !cm.hasPrimaryClip()) { toast("剪贴板是空的"); return; }
        ClipData cd = cm.getPrimaryClip();
        if (cd == null || cd.getItemCount() == 0) return;
        CharSequence txt = cd.getItemAt(0).coerceToText(this);
        edit.setText(clean(txt == null ? "" : txt.toString()));
        tip.setText("已粘贴并清洗，核对一下就可以送去模拟");
    }

    // ---------- OCR ----------
    private boolean hasKey() {
        return !key().isEmpty();
    }

    private String key() {
        SharedPreferences sp = getSharedPreferences("macrogen", MODE_PRIVATE);
        return sp.getString("ocr_key", "").trim();
    }

    private void askKey() {
        final EditText in = new EditText(this);
        in.setText(key());
        in.setHint("粘贴 ocr.space 的免费 key");
        in.setTextSize(13);
        in.setSingleLine(true);
        new AlertDialog.Builder(this)
                .setTitle("OCR 识别 Key")
                .setMessage("去 ocr.space/ocrapi/freekey 领一个免费 key（约 25 次/天），填一次就长期可用。\n没有 key 也能用：把程序粘贴进来一样能模拟。")
                .setView(in)
                .setPositiveButton("保存", new android.content.DialogInterface.OnClickListener() {
                    @Override public void onClick(android.content.DialogInterface d, int w) {
                        getSharedPreferences("macrogen", MODE_PRIVATE)
                                .edit().putString("ocr_key", in.getText().toString().trim()).commit();
                        tip.setText(hasKey() ? "已配置识别 Key，拍完点「开始识别」即可" : "Key 已清空，可继续手工粘贴");
                    }
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void runOcr() {
        if (bitmap == null) { toast("先拍照或从相册选一张程序照片"); return; }
        if (!hasKey()) {
            new AlertDialog.Builder(this)
                    .setTitle("还没有识别 Key")
                    .setMessage("两条路：\n① 点右上「识别 Key」填一个免费 key，之后拍照就能全自动识别；\n② 用手机相册 / 微信的“提取文字”，复制后点「粘贴」，一样能进模拟。")
                    .setPositiveButton("去填 Key", new android.content.DialogInterface.OnClickListener() {
                        @Override public void onClick(android.content.DialogInterface d, int w) { askKey(); }
                    })
                    .setNegativeButton("知道了", null)
                    .show();
            return;
        }
        tip.setText("正在识别，稍等…");
        new Thread(new Runnable() {
            @Override public void run() {
                String err = null, text = null;
                try {
                    byte[] jpg = compress();
                    String body = "apikey=" + enc(key())
                            + "&language=eng&isOverlayRequired=false&scale=true&OCREngine=2"
                            + "&filetype=JPG&detectOrientation=true"
                            + "&base64Image=" + enc("data:image/jpeg;base64," + b64(jpg));
                    HttpURLConnection c = (HttpURLConnection) new URL(API).openConnection();
                    c.setConnectTimeout(20000);
                    c.setReadTimeout(45000);
                    c.setRequestMethod("POST");
                    c.setDoOutput(true);
                    c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
                    OutputStream os = c.getOutputStream();
                    os.write(body.getBytes("UTF-8"));
                    os.flush();
                    os.close();
                    int code = c.getResponseCode();
                    InputStream is = code >= 200 && code < 300 ? c.getInputStream() : c.getErrorStream();
                    String json = readAll(is);
                    if (code == 403 || json.contains("Unauthorized") || json.contains("invalid API key")) {
                        err = "Key 无效或超额，换个 key 再试";
                    } else if (json.contains("\"ParsedResults\"") && !json.contains("\"ParsedResults\": null")) {
                        JSONObject o = new JSONObject(json);
                        JSONArray arr = o.optJSONArray("ParsedResults");
                        StringBuilder sb = new StringBuilder();
                        for (int i = 0; arr != null && i < arr.length(); i++) {
                            sb.append(arr.getJSONObject(i).optString("ParsedText", ""));
                        }
                        text = sb.toString();
                        if (text.trim().isEmpty()) err = "图里没认出文字，拍正一点/离近一点再试";
                    } else {
                        err = "识别服务返回异常（HTTP " + code + "）";
                    }
                } catch (Exception e) {
                    err = "识别失败：" + e.getMessage();
                }
                final String fErr = err, fText = text;
                ui.post(new Runnable() {
                    @Override public void run() {
                        if (fText != null) {
                            String out = clean(fText);
                            edit.setText(out);
                            tip.setText("识别完成，已清洗为 " + out.split("\n").length
                                    + " 行；OCR 一定会认错几个字符，先核对再模拟");
                        } else {
                            tip.setText("识别失败：" + fErr);
                        }
                    }
                });
            }
        }).start();
    }

    private byte[] compress() {
        Bitmap src = bitmap;
        int max = 1600;
        int w = src.getWidth(), h = src.getHeight();
        if (Math.max(w, h) > max) {
            float s = max / (float) Math.max(w, h);
            src = Bitmap.createScaledBitmap(src, Math.max(1, (int) (w * s)),
                    Math.max(1, (int) (h * s)), true);
        }
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        src.compress(Bitmap.CompressFormat.JPEG, 82, bo);
        return bo.toByteArray();
    }

    private String enc(String s) throws Exception {
        return URLEncoder.encode(s, "UTF-8");
    }

    private String b64(byte[] d) {
        return android.util.Base64.encodeToString(d, android.util.Base64.NO_WRAP);
    }

    private String readAll(InputStream is) throws Exception {
        if (is == null) return "";
        BufferedReader r = new BufferedReader(new InputStreamReader(is, "UTF-8"));
        StringBuilder sb = new StringBuilder();
        String l;
        while ((l = r.readLine()) != null) sb.append(l).append('\n');
        r.close();
        return sb.toString();
    }

    // ---------- 清洗 ----------
    /** 把 OCR 脏字符整成机床能跑的样子：全角转半角、去掉行号噪声、修形近字 */
    static String clean(String raw) {
        if (raw == null) return "";
        String s = raw.replace("\r\n", "\n").replace('\r', '\n');
        // 全角 / 中文标点
        s = s.replace('，', ',').replace('。', '.').replace('；', ';')
                .replace('（', '(').replace('）', ')').replace('［', '[').replace('］', ']')
                .replace('＃', '#').replace('＝', '=').replace('＋', '+').replace('－', '-')
                .replace('　', ' ').replace('\u00A0', ' ')
                .replace('／', '/').replace('％', '%').replace('＊', '*')
                .replace('１', '1').replace('２', '2').replace('３', '3').replace('４', '4')
                .replace('５', '5').replace('６', '6').replace('７', '7').replace('８', '8')
                .replace('９', '9').replace('０', '0')
                .replace('．', '.')
                .replace('Ｏ', 'O').replace('Ｌ', 'L').replace('Ｉ', 'I')
                .replace('Ｎ', 'N').replace('Ｗ', 'W').replace('Ｈ', 'H')
                .replace('Ｅ', 'E').replace('Ｔ', 'T').replace('Ｄ', 'D')
                .replace('Ｒ', 'R').replace('Ａ', 'A').replace('Ｂ', 'B')
                .replace('Ｃ', 'C').replace('Ｇ', 'G').replace('Ｍ', 'M')
                .replace('Ｘ', 'X').replace('Ｙ', 'Y').replace('Ｚ', 'Z')
                .replace('Ｐ', 'P').replace('Ｆ', 'F').replace('Ｓ', 'S')
                .replace('Ｋ', 'K').replace('Ｊ', 'J').replace('Ｕ', 'U')
                .replace('Ｖ', 'V');
        StringBuilder out = new StringBuilder();
        for (String line : s.split("\n")) {
            String t = line.trim();
            if (t.isEmpty()) continue;
            // 去掉 OCR 的页码/干扰标记
            if (t.startsWith("*") && !t.contains("G")) continue;
            // 行内空格去掉（FANUC 不认空格的地方也无所谓）
            t = t.replaceAll("\\s+", " ").trim();
            t = fixLooks(t.toUpperCase());
            if (!looksLikeProgram(t)) continue;
            out.append(t).append('\n');
        }
        return out.toString();
    }

    private static final String[] KEYWORDS = {
            "WHILE", "GOTO", "END", "THEN", "SQRT", "ROUND", "ATAN", "SIN", "COS",
            "TAN", "ABS", "FIX", "FUP", "GT", "GE", "LT", "LE", "EQ", "NE", "DO"
    };

    /**
     * G0l / Xl00 / Y5O.5 这类 O 与 0、l 与 1 的混淆。
     * 先把关键字（WHILE / DO / LT …）保护起来，避免把字母当数字改坏；
     * 只在“紧邻数字或紧跟在地址字母后面”的位置替换，纯字母单词不动。
     */
    private static String fixLooks(String t) {
        String work = t;
        for (int k = 0; k < KEYWORDS.length; k++) {
            work = work.replace(KEYWORDS[k], "@" + k + "@");
        }
        StringBuilder sb = new StringBuilder(work.length());
        for (int i = 0; i < work.length(); i++) {
            char c = work.charAt(i);
            char prev = i > 0 ? work.charAt(i - 1) : ' ';
            char next = i + 1 < work.length() ? work.charAt(i + 1) : ' ';
            // 紧跟 [ # - + 的字母是地址字（如 I[-#21]），绝不能当数字改
            if (next == '[' || next == '#' || next == '-' || next == '+') {
                sb.append(c);
                continue;
            }
            if (isLookZero(c) && (Character.isDigit(prev) || prev == '.'
                    || (isAddress(prev) && (Character.isDigit(next) || !Character.isLetter(next))))){
                sb.append('0');
            } else if (isLookOne(c) && (Character.isDigit(prev) || prev == '.'
                    || (isAddress(prev) && (Character.isDigit(next) || !Character.isLetter(next))))) {
                sb.append('1');
            } else {
                sb.append(c);
            }
        }
        String out = sb.toString();
        for (int k = 0; k < KEYWORDS.length; k++) {
            out = out.replace("@" + k + "@", KEYWORDS[k]);
        }
        // 循环体号也必须修：DOL / DOl / ENDl 一律当 1
        out = out.replaceAll("DO[LIO]", "DO1").replaceAll("END[LIO]", "END1");
        return out;
    }

    private static boolean isLookZero(char c) {
        return c == 'O' || c == 'Q' || c == 'D';
    }

    private static boolean isLookOne(char c) {
        return c == 'l' || c == '|' || c == 'L';   // 不含 I：I 是圆弧/参数地址
    }

    private static boolean isAddress(char c) {
        return "ABCFGHIJKMNOPQRSTUVWXYZ".indexOf(c) >= 0;
    }

    /** 丢掉明显的乱码行，保留程序骨架 */
    private static boolean looksLikeProgram(String t) {
        if (t.length() < 2) return false;
        if (t.matches("[0-9]{1,2}")) return false;              // 纯行号残留
        return t.matches(".*[GM#/].*") || t.startsWith("WHILE")
                || t.startsWith("END") || t.startsWith("IF") || t.startsWith("O")
                || t.startsWith("N") || t.startsWith("(");
    }

    // ---------- 小工具 ----------
    private void toast(String m) {
        Toast.makeText(this, m, Toast.LENGTH_SHORT).show();
    }

    private LinearLayout.LayoutParams weight() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.MATCH_PARENT, 1);
        lp.rightMargin = dp(5);
        return lp;
    }

    private Button small(String t, int bg, int fg) {
        Button b = new Button(this);
        b.setText(t);
        b.setAllCaps(false);
        b.setTextSize(12.5f);
        b.setTextColor(fg);
        b.setBackground(round(bg, 10));
        b.setMinHeight(dp(36));
        b.setMinimumHeight(dp(36));
        b.setPadding(dp(8), 0, dp(8), 0);
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
