package com.sqc.macrogen;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.MotionEvent;
import android.view.View;

/**
 * 执行结果的轨迹渲染：俯视 / 等轴测立体，支持拖动平移、双指缩放。
 * 已经走过的段用橙色→深红按深度上色，未走的段淡灰做参照。
 */
public class SimView extends View {

    private MacroInterp.Path data;
    private GCode spec;
    private boolean iso = true;
    private double curDist;
    private int curIndex;

    private float scale = 1f;
    private float tx = 0f, ty = 0f;
    private float lastX, lastY;
    private float lastDist;

    private final Paint pRapid = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pRest = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pCut = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pFace = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pEdge = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pTool = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pText = new Paint(Paint.ANTI_ALIAS_FLAG);

    public SimView(Context c) {
        super(c);
        pRapid.setStyle(Paint.Style.STROKE);
        pRapid.setStrokeWidth(1.2f);
        pRapid.setColor(0xFF7C8AA0);
        pRest.setStyle(Paint.Style.STROKE);
        pRest.setStrokeWidth(1f);
        pRest.setColor(0xFFD3DAE3);
        pCut.setStyle(Paint.Style.STROKE);
        pCut.setStrokeWidth(1.8f);
        pCut.setStrokeCap(Paint.Cap.ROUND);
        pFace.setStyle(Paint.Style.FILL);
        pFace.setColor(0xFF3A4553);
        pEdge.setStyle(Paint.Style.STROKE);
        pEdge.setStrokeWidth(1.4f);
        pEdge.setColor(0xFF59616E);
        pTool.setStyle(Paint.Style.STROKE);
        pTool.setStrokeWidth(3f);
        pTool.setColor(0xFFFF6B1A);
        pText.setColor(0xFF8A96A6);
        pText.setTextSize(22f);
        setBackgroundColor(0xFFFAFBFC);
    }

    public void setData(MacroInterp.Path p, GCode s) {
        data = p;
        spec = s;
        curDist = 0;
        curIndex = 0;
        scale = 1f; tx = 0; ty = 0;
        invalidate();
    }

    /** 让外部（播放/拖进度）设置当前弧长位置 */
    public void setProgress(double dist) {
        curDist = Math.max(0, Math.min(dist, data == null ? 0 : data.maxLen));
        curIndex = indexAt(curDist);
        invalidate();
    }

    public void setIso(boolean b) { iso = b; invalidate(); }

    public double getProgressDist() { return curDist; }

    public int lineAt() {
        if (data == null || curIndex >= data.pts.size()) return -1;
        return data.pts.get(curIndex).line;
    }

    public double xAt() { return data == null ? 0 : data.pts.get(Math.min(curIndex, data.pts.size() - 1)).x; }
    public double yAt() { return data == null ? 0 : data.pts.get(Math.min(curIndex, data.pts.size() - 1)).y; }
    public double zAt() { return data == null ? 0 : data.pts.get(Math.min(curIndex, data.pts.size() - 1)).z; }

    private int indexAt(double d) {
        if (data == null) return 0;
        int lo = 0, hi = data.dist.size() - 1;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (data.dist.get(mid) < d) lo = mid + 1; else hi = mid;
        }
        return lo;
    }

    // ---------- 投影 ----------
    private void world(double x, double y, double z, float[] out) {
        if (iso) {
            out[0] = (float) ((x - y) * 0.866);
            out[1] = (float) ((x + y) * 0.5 + z * 1.0);
        } else {
            out[0] = (float) x;
            out[1] = (float) -y;
        }
    }

    @Override
    protected void onDraw(Canvas cv) {
        super.onDraw(cv);
        if (data == null || data.pts.size() < 2) {
            cv.drawText("没有可显示的轨迹", 40, 60, pText);
            return;
        }
        float w = getWidth(), h = getHeight();
        // 世界坐标范围 → 屏幕
        double minX = data.minX, maxX = data.maxX, minY = data.minY, maxY = data.maxY;
        if (spec != null) {   // 把工件也算进视野
            minX = Math.min(minX, -spec.length / 2); maxX = Math.max(maxX, spec.length / 2);
            minY = Math.min(minY, -spec.width / 2); maxY = Math.max(maxY, spec.width / 2);
        }
        float[] a = new float[2], b = new float[2];
        double sx = 1, sy = 1;
        // 用四个角的投影算包围盒
        float bx0 = 1e9f, bx1 = -1e9f, by0 = 1e9f, by1 = -1e9f;
        double zLo = Math.min(0, data.minZ), zHi = Math.max(0, data.maxZ);
        for (int k = 0; k < 4; k++) {
            double px = (k % 2 == 0) ? minX : maxX;
            double py = (k < 2) ? minY : maxY;
            for (int zi = 0; zi < 2; zi++) {            // Z 方向也要进视野，否则画面被顶端切掉
                world(px, py, zi == 0 ? zLo : zHi, a);
                bx0 = Math.min(bx0, a[0]); bx1 = Math.max(bx1, a[0]);
                by0 = Math.min(by0, a[1]); by1 = Math.max(by1, a[1]);
            }
        }
        float pad = 46f;
        float fit = Math.min((w - pad * 2) / Math.max(1f, bx1 - bx0), (h - pad * 2) / Math.max(1f, by1 - by0));
        float s = fit * scale;
        float cxs = w / 2 + tx, cys = h / 2 + ty;

        // 工件毛坯（上表面 + 侧面轮廓）
        if (spec != null) {
            double lx = spec.length / 2, ly = spec.width / 2, lz = -Math.max(1, spec.depth);
            drawBox(cv, lx, ly, lz, s, cxs, cys);
        }

        // 轨迹
        float[] prev = new float[2];
        world(data.pts.get(0).x, data.pts.get(0).y, data.pts.get(0).z, prev);
        project(prev, s, cxs, cys);
        int lastLine = 0;
        for (int k = 1; k < data.pts.size(); k++) {
            MacroInterp.P p = data.pts.get(k);
            world(p.x, p.y, p.z, b);
            project(b, s, cxs, cys);
            boolean done = data.dist.get(k) <= curDist;
            if (done) {
                if (p.rapid) {
                    cv.drawLine(prev[0], prev[1], b[0], b[1], pRapid);
                } else {
                    // 深度越深越红
                    double t = 0;
                    if (spec != null && spec.depth > 0) t = Math.min(1, Math.max(0, -p.z / spec.depth));
                    pCut.setColor(lerp(0xFFFFA25F, 0xFFD2320C, t));
                    cv.drawLine(prev[0], prev[1], b[0], b[1], pCut);
                }
            } else if (p.line != lastLine || true) {
                cv.drawLine(prev[0], prev[1], b[0], b[1], pRest);
            }
            lastLine = p.line;
            prev[0] = b[0]; prev[1] = b[1];
        }

        // 刀尖标记
        MacroInterp.P cur = data.pts.get(Math.min(curIndex, data.pts.size() - 1));
        float[] tip = new float[2];
        world(cur.x, cur.y, cur.z, tip);
        project(tip, s, cxs, cys);
        cv.drawCircle(tip[0], tip[1], 5f, pCutFill());
        cv.drawLine(tip[0], tip[1], tip[0], tip[1] - 26, pTool);
    }

    private Paint cutFillCache;
    private Paint pCutFill() {
        if (cutFillCache == null) {
            cutFillCache = new Paint(Paint.ANTI_ALIAS_FLAG);
            cutFillCache.setStyle(Paint.Style.FILL);
            cutFillCache.setColor(0xFFFF6B1A);
        }
        return cutFillCache;
    }

    private void project(float[] v, float s, float cx, float cy) {
        v[0] = cx + v[0] * s;
        v[1] = cy - v[1] * s;
    }

    private void drawBox(Canvas cv, double lx, double ly, double lz, float s, float cx, float cy) {
        // 上表面
        Path top = new Path();
        float[] v = new float[2];
        double[][] pts = {{-lx, -ly}, {lx, -ly}, {lx, ly}, {-lx, ly}};
        for (int k = 0; k < 4; k++) {
            world(pts[k][0], pts[k][1], 0, v);
            project(v, s, cx, cy);
            if (k == 0) top.moveTo(v[0], v[1]); else top.lineTo(v[0], v[1]);
        }
        top.close();
        cv.drawPath(top, pFace);
        cv.drawPath(top, pEdge);
        if (iso) {
            // 两个侧面
            for (int side = 0; side < 2; side++) {
                Path sp = new Path();
                double[] ax = side == 0 ? new double[]{-lx, lx} : new double[]{lx, lx};
                double[] ay = side == 0 ? new double[]{ly, ly} : new double[]{ly, -ly};
                double[][] poly = {{ax[0], ay[0], 0}, {ax[1], ay[1], 0}, {ax[1], ay[1], lz}, {ax[0], ay[0], lz}};
                for (int k = 0; k < 4; k++) {
                    world(poly[k][0], poly[k][1], poly[k][2], v);
                    project(v, s, cx, cy);
                    if (k == 0) sp.moveTo(v[0], v[1]); else sp.lineTo(v[0], v[1]);
                }
                sp.close();
                Paint pf = new Paint(pFace);
                pf.setColor(side == 0 ? 0xFF2E3743 : 0xFF46505E);
                cv.drawPath(sp, pf);
                cv.drawPath(sp, pEdge);
            }
        }
        // Z 轴指示
        world(-lx, ly, 0, v);
        project(v, s, cx, cy);
        cv.drawLine(v[0], v[1], v[0], v[1] - 40, pEdge);
        cv.drawText("Z", v[0] - 6, v[1] - 46, pText);
    }

    private int lerp(int c0, int c1, double t) {
        int a0 = (c0 >> 24) & 0xFF, r0 = (c0 >> 16) & 0xFF, g0 = (c0 >> 8) & 0xFF, b0 = c0 & 0xFF;
        int r1 = (c1 >> 16) & 0xFF, g1 = (c1 >> 8) & 0xFF, b1 = c1 & 0xFF;
        int r = (int) (r0 + (r1 - r0) * t), g = (int) (g0 + (g1 - g0) * t), b = (int) (b0 + (b1 - b0) * t);
        return Color.argb(255, r, g, b);
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                lastX = e.getX(); lastY = e.getY();
                if (e.getPointerCount() > 1) lastDist = dist(e);
                return true;
            case MotionEvent.ACTION_POINTER_DOWN:
                lastDist = dist(e);
                return true;
            case MotionEvent.ACTION_MOVE:
                if (e.getPointerCount() > 1) {
                    float d = dist(e);
                    if (lastDist > 0) {
                        float f = d / lastDist;
                        scale = Math.max(0.4f, Math.min(8f, scale * f));
                        lastDist = d;
                    }
                } else {
                    tx += e.getX() - lastX;
                    ty += e.getY() - lastY;
                    lastX = e.getX(); lastY = e.getY();
                }
                invalidate();
                return true;
            default:
                return true;
        }
    }

    private float dist(MotionEvent e) {
        float dx = e.getX(0) - e.getX(1), dy = e.getY(0) - e.getY(1);
        return (float) Math.sqrt(dx * dx + dy * dy);
    }
}
