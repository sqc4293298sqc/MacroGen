package com.sqc.macrogen;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.ProgressDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * 启动时检查新版本：有新版本 -> 弹窗 -> 下载 apk -> 拉起系统安装器。
 * 全部用匿名内部类，避免 lambda（手工 javac 环境不支持）。
 */
public class UpdateChecker {

    // 版本信息放在 GitHub 仓库根目录，改这一个文件就能推送新版本
    private static final String VERSION_URL =
            "https://raw.githubusercontent.com/sqc4293298sqc/MacroGen/main/update.json";

    private UpdateChecker() {
    }

    /** 在 Activity.onCreate 末尾调用；每个 Activity 只查一次，失败静默 */
    public static void check(final Activity act) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    String body = getText(VERSION_URL);
                    JSONObject root = new JSONObject(body);
                    JSONObject a = root.optJSONObject("android");
                    if (a == null) return;
                    int remoteCode = a.optInt("versionCode", 0);
                    final String remoteName = a.optString("versionName", "");
                    final String apkUrl = a.optString("url", "");
                    final String changelog = a.optString("changelog", "");
                    int localCode = localVersionCode(act);
                    if (remoteCode <= localCode || apkUrl.length() == 0) return;
                    ui(act, new Runnable() {
                        @Override
                        public void run() {
                            showDialog(act, remoteName, changelog, apkUrl);
                        }
                    });
                } catch (Exception ignored) {
                    // 没网或解析失败：静默，不影响使用
                }
            }
        }).start();
    }

    private static void showDialog(final Activity act, String name, String log, final String apkUrl) {
        if (act.isFinishing()) return;
        StringBuilder msg = new StringBuilder();
        if (log.length() > 0) msg.append(log);
        AlertDialog.Builder b = new AlertDialog.Builder(act);
        b.setTitle("发现新版本 v" + name);
        b.setMessage(msg.length() > 0 ? msg.toString() : "有新版本可以更新");
        b.setPositiveButton("立即更新", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface d, int w) {
                download(act, apkUrl);
            }
        });
        b.setNegativeButton("稍后", null);
        b.show();
    }

    /** 下载到私有缓存目录，避免要存储权限 */
    private static void download(final Activity act, final String apkUrl) {
        if (Build.VERSION.SDK_INT >= 26 && !act.getPackageManager().canRequestPackageInstalls()) {
            Toast.makeText(act, "请先允许安装未知来源应用，再点更新", Toast.LENGTH_LONG).show();
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + act.getPackageName()));
            act.startActivity(i);
            return;
        }
        final ProgressDialog pd = new ProgressDialog(act);
        pd.setTitle("正在下载更新");
        pd.setProgressStyle(ProgressDialog.STYLE_HORIZONTAL);
        pd.setMax(100);
        pd.setCancelable(false);
        pd.show();

        new Thread(new Runnable() {
            @Override
            public void run() {
                File out = new File(act.getCacheDir(), "update.apk");
                if (out.exists()) out.delete();
                try {
                    HttpURLConnection c = (HttpURLConnection) new URL(apkUrl).openConnection();
                    c.setConnectTimeout(15000);
                    c.setReadTimeout(20000);
                    c.setInstanceFollowRedirects(true);
                    c.connect();
                    int total = c.getContentLength();
                    InputStream in = c.getInputStream();
                    FileOutputStream fos = new FileOutputStream(out);
                    byte[] buf = new byte[8192];
                    int n, done = 0, lastPct = -1;
                    while ((n = in.read(buf)) > 0) {
                        fos.write(buf, 0, n);
                        done += n;
                        if (total > 0) {
                            int pct = (int) (done * 100L / total);
                            if (pct != lastPct) {
                                lastPct = pct;
                                setProgress(act, pd, pct);
                            }
                        }
                    }
                    fos.close();
                    in.close();
                    ui(act, new Runnable() {
                        @Override
                        public void run() {
                            pd.dismiss();
                            install(act, out);
                        }
                    });
                } catch (Exception e) {
                    ui(act, new Runnable() {
                        @Override
                        public void run() {
                            pd.dismiss();
                            Toast.makeText(act, "下载失败，请稍后重试", Toast.LENGTH_LONG).show();
                        }
                    });
                }
            }
        }).start();
    }

    private static void install(Activity act, File apk) {
        Uri uri = ApkProvider.uriFor(act);
        Intent i = new Intent(Intent.ACTION_VIEW);
        i.setDataAndType(uri, "application/vnd.android.package-archive");
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        act.startActivity(i);
    }

    private static void setProgress(Activity act, final ProgressDialog pd, final int pct) {
        ui(act, new Runnable() {
            @Override
            public void run() {
                pd.setProgress(pct);
            }
        });
    }

    private static void ui(Activity act, Runnable r) {
        new Handler(Looper.getMainLooper()).post(r);
    }

    private static int localVersionCode(Context ctx) {
        try {
            PackageInfo pi = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0);
            return pi.versionCode;
        } catch (Exception e) {
            return 0;
        }
    }

    private static String getText(String url) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        c.setInstanceFollowRedirects(true);
        InputStream in = c.getInputStream();
        StringBuilder sb = new StringBuilder();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) sb.append(new String(buf, 0, n, "UTF-8"));
        in.close();
        return sb.toString();
    }
}
