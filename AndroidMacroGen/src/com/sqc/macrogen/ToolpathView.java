package com.sqc.macrogen;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.View;

import java.util.List;

/** 刀路仿真视图：支持俯视投影 / 等轴测立体 */
public class ToolpathView extends View {
    private List<Toolpath.Seg> segs;
    private List<float[]> outline;
    private List<float[]> bottomOutline;
    private float total = 1f;
    private float playLen = 0f;
    private float toolR = 6f;
    private float cutZ = 0f;
    private float maxDepth = 1f;
    private boolean iso = false;

    private final Paint pGrid = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pGhost = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pCut = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pTool = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pEdge = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pBottom = new Paint(Paint.ANTI_ALIAS_FLAG);

    private float minX, maxX, minY, maxY, scale = 1f, ox = 0f, oy = 0f;
    private final Path path = new Path();

    public ToolpathView(Context c) {
        super(c);
        pGrid.setColor(0xFFEDF0F4);
        pGrid.setStrokeWidth(1f);
        pGhost.setColor(0xFFCFD6DF);
        pGhost.setStyle(Paint.Style.STROKE);
        pGhost.setStrokeWidth(1f);
        pCut.setStyle(Paint.Style.STROKE);
        pCut.setStrokeWidth(1.8f);
        pTool.setStyle(Paint.Style.STROKE);
        pTool.setStrokeWidth(1.3f);
        pEdge.setStyle(Paint.Style.STROKE);
        pEdge.setStrokeWidth(1f);
        pEdge.setPathEffect(new DashPathEffect(new float[]{5f, 4f}, 0f));
        pBottom.setStyle(Paint.Style.STROKE);
        pBottom.setStrokeWidth(1f);
        pBottom.setPathEffect(new DashPathEffect(new float[]{3f, 4f}, 0f));
    }

    public void setData(List<Toolpath.Seg> segs, float toolR, List<float[]> outline, List<float[]> bottomOutline) {
        this.segs = segs;
        this.toolR = toolR;
        this.outline = outline;
        this.bottomOutline = bottomOutline;
        this.total = Math.max(1f, Toolpath.totalLen(segs));
        float d = 1f;
        for (Toolpath.Seg sg : segs) if (-sg.z > d) d = -sg.z;
        this.maxDepth = d;
        computeBounds();
        invalidate();
    }

    public void setIso(boolean iso) {
        this.iso = iso;
        computeBounds();
        invalidate();
    }

    public boolean isIso() { return iso; }

    private float zK() { return 2.0f; }

    /** 三维投影到画布坐标（未缩放） */
    private void proj(float x, float y, float z, float[] out) {
        if (iso) {
            out[0] = (x - y) * 0.866f;
            out[1] = (x + y) * 0.5f + z * zK();
        } else {
            out[0] = x;
            out[1] = y;
        }
    }

    private void computeBounds() {
        if (segs == null || segs.isEmpty()) return;
        minX = Float.MAX_VALUE; maxX = -Float.MAX_VALUE;
        minY = Float.MAX_VALUE; maxY = -Float.MAX_VALUE;
        float[] p = new float[2];
        for (Toolpath.Seg s : segs) {
            for (float[] pt : s.pts) {
                proj(pt[0], pt[1], s.z, p);
                grow(p[0], p[1]);
            }
        }
        if (outline != null) {
            for (float z : new float[]{0f, -maxDepth}) {
                for (float[] pt : outline) {
                    proj(pt[0], pt[1], z, p);
                    grow(p[0], p[1]);
                }
            }
        }
        float pad = toolR + 1f;
        minX -= pad; maxX += pad; minY -= pad; maxY += pad;
    }

    private void grow(float x, float y) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
    }

    public void setProgress(float v) {
        playLen = Math.max(0f, Math.min(1f, v)) * total;
        cutZ = currentZ();
        invalidate();
    }

    public float getCutZ() { return cutZ; }

    private float currentZ() {
        if (segs == null) return 0f;
        float acc = 0f;
        for (Toolpath.Seg s : segs) {
            if (acc + s.len >= playLen) return s.z;
            acc += s.len;
        }
        return segs.isEmpty() ? 0f : segs.get(segs.size() - 1).z;
    }

    @Override
    protected void onDraw(Canvas c) {
        super.onDraw(c);
        c.drawColor(Color.WHITE);
        if (segs == null || segs.isEmpty()) return;

        float w = getWidth(), h = getHeight();
        float pad = 18f;
        float spanX = Math.max(0.001f, maxX - minX);
        float spanY = Math.max(0.001f, maxY - minY);
        scale = Math.min((w - pad * 2) / spanX, (h - pad * 2) / spanY);
        ox = (w - spanX * scale) / 2f - minX * scale;
        oy = (h - spanY * scale) / 2f + maxY * scale;

        drawGrid(c, w, h);

        // 工件轮廓：顶面实线虚线框 + 底面虚线框（立体时再连竖线）
        drawOutline(c, 0f, pEdge);
        if (iso) {
            if (bottomOutline != null) {
                drawOutlineList(c, bottomOutline, -maxDepth, pBottom);
            } else {
                drawOutline(c, -maxDepth, pBottom);
            }
            // 立体时底面轮廓已能表现厚度，不再画竖线，避免圆形/长圆轮廓出现多余星线
        }

        // 预测路径
        pGhost.setPathEffect(null);
        for (Toolpath.Seg s : segs) {
            path.reset();
            boolean st = false;
            float[] p = new float[2];
            for (float[] pt : s.pts) {
                proj(pt[0], pt[1], s.z, p);
                if (!st) { path.moveTo(sx(p[0]), sy(p[1])); st = true; }
                else path.lineTo(sx(p[0]), sy(p[1]));
            }
            c.drawPath(path, pGhost);
        }

        // 已走轨迹（按深度上色）
        float acc = 0f;
        float[] last = null;
        float lastZ = 0f;
        for (Toolpath.Seg s : segs) {
            if (acc > playLen) break;
            float budget = playLen - acc;
            if (s.len <= 0f) { acc += s.len; continue; }
            float frac = Math.min(1f, budget / s.len);
            if (s.cut) {
                float t = Math.min(1f, -s.z / maxDepth);
                pCut.setColor(lerpColor(0xFFFFA25F, 0xFFD2320C, t));
            } else {
                pCut.setColor(0xFFB9C3D0);
            }
            drawSeg(c, s, frac);
            last = pointAt(s, frac);
            lastZ = s.z;
            acc += s.len;
        }

        // 刀具（立体时画成椭圆并带引线）
        if (last != null) {
            float[] p = new float[2];
            proj(last[0], last[1], lastZ, p);
            float cx = sx(p[0]), cy = sy(p[1]);
            float rr = toolR * scale;
            if (iso) {
                c.drawOval(cx - rr, cy - rr * 0.6f, cx + rr, cy + rr * 0.6f, pTool);
                c.drawLine(cx, cy, cx, cy + (-lastZ) * zK() * scale, pTool);
            } else {
                c.drawCircle(cx, cy, rr, pTool);
            }
            c.drawLine(cx - rr, cy, cx + rr, cy, pTool);
            c.drawLine(cx, cy - rr, cx, cy + rr, pTool);
            Paint dot = new Paint(Paint.ANTI_ALIAS_FLAG);
            dot.setColor(0xFFFF6B1A);
            dot.setStyle(Paint.Style.FILL);
            c.drawCircle(cx, cy, 3.6f, dot);
        }
    }

    private void drawGrid(Canvas c, float w, float h) {
        float step = nice(Math.max(1f, (maxX - minX) / 6f));
        float[] p = new float[2];
        for (float gx = (float) Math.floor(minX / step) * step; gx <= maxX; gx += step) {
            float x = ox + gx * scale;
            c.drawLine(x, 0f, x, h, pGrid);
        }
        for (float gy = (float) Math.floor(minY / step) * step; gy <= maxY; gy += step) {
            float y = oy - gy * scale;
            c.drawLine(0f, y, w, y, pGrid);
        }
    }

    private void drawOutline(Canvas c, float z, Paint p) {
        drawOutlineList(c, outline, z, p);
    }

    private void drawOutlineList(Canvas c, List<float[]> list, float z, Paint p) {
        if (list == null || list.size() < 2) return;
        path.reset();
        float[] q = new float[2];
        boolean st = false;
        for (float[] pt : list) {
            proj(pt[0], pt[1], z, q);
            if (!st) { path.moveTo(sx(q[0]), sy(q[1])); st = true; }
            else path.lineTo(sx(q[0]), sy(q[1]));
        }
        c.drawPath(path, p);
    }

    private void drawCorners(Canvas c) {
        if (outline == null) return;
        float[] a = new float[2], b = new float[2];
        // 取轮廓四等分点画竖线，表现立体厚度
        int n = outline.size();
        int[] idx = {0, n / 4, n / 2, n * 3 / 4};
        for (int i : idx) {
            float[] pt = outline.get(Math.min(n - 1, i));
            proj(pt[0], pt[1], 0f, a);
            proj(pt[0], pt[1], -maxDepth, b);
            c.drawLine(sx(a[0]), sy(a[1]), sx(b[0]), sy(b[1]), pBottom);
        }
    }

    private void drawSeg(Canvas c, Toolpath.Seg s, float frac) {
        path.reset();
        boolean started = false;
        float need = s.len * frac;
        float acc = 0f;
        float[] prev = null;
        float[] q = new float[2];
        for (float[] pt : s.pts) {
            if (!started) {
                proj(pt[0], pt[1], s.z, q);
                path.moveTo(sx(q[0]), sy(q[1]));
                started = true;
                prev = pt;
                continue;
            }
            float d = (float) Math.hypot(pt[0] - prev[0], pt[1] - prev[1]);
            if (acc + d <= need) {
                proj(pt[0], pt[1], s.z, q);
                path.lineTo(sx(q[0]), sy(q[1]));
                acc += d;
            } else {
                float t = d > 0 ? (need - acc) / d : 0f;
                float mx = prev[0] + (pt[0] - prev[0]) * t;
                float my = prev[1] + (pt[1] - prev[1]) * t;
                proj(mx, my, s.z, q);
                path.lineTo(sx(q[0]), sy(q[1]));
                break;
            }
            prev = pt;
        }
        c.drawPath(path, pCut);
    }

    private float[] pointAt(Toolpath.Seg s, float frac) {
        float need = s.len * frac;
        float acc = 0f;
        float[] prev = null;
        for (float[] pt : s.pts) {
            if (prev == null) { prev = pt; continue; }
            float d = (float) Math.hypot(pt[0] - prev[0], pt[1] - prev[1]);
            if (acc + d >= need) {
                float t = d > 0 ? (need - acc) / d : 0f;
                return new float[]{prev[0] + (pt[0] - prev[0]) * t, prev[1] + (pt[1] - prev[1]) * t};
            }
            acc += d;
            prev = pt;
        }
        return prev == null ? new float[]{0, 0} : prev;
    }

    private static int lerpColor(int c1, int c2, float t) {
        int r = (int) (((c1 >> 16) & 0xFF) + (((c2 >> 16) & 0xFF) - ((c1 >> 16) & 0xFF)) * t);
        int g = (int) (((c1 >> 8) & 0xFF) + (((c2 >> 8) & 0xFF) - ((c1 >> 8) & 0xFF)) * t);
        int b = (int) ((c1 & 0xFF) + ((c2 & 0xFF) - (c1 & 0xFF)) * t);
        return 0xFF000000 | (r << 16) | (g << 8) | b;
    }

    private float sx(float x) { return ox + x * scale; }
    private float sy(float y) { return oy - y * scale; }

    private static float nice(float v) {
        float p = (float) Math.pow(10, Math.floor(Math.log10(Math.max(1f, v))));
        float n = v / p;
        if (n < 2) return 2 * p;
        if (n < 5) return 5 * p;
        return 10 * p;
    }
}
