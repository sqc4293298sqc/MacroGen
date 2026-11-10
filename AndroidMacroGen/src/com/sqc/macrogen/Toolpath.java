package com.sqc.macrogen;

import java.util.ArrayList;
import java.util.List;

/** 刀路仿真：按各模式宏程序里的循环逻辑，算出真实走刀轨迹（单位 mm，Z 向下为负） */
public class Toolpath {

    public static class Seg {
        public boolean cut;      // 切削 / 快移
        public float z;          // 该段所在 Z
        public float len;        // 段长（用于进度）
        public List<float[]> pts = new ArrayList<>();
        Seg(boolean cut, float z) { this.cut = cut; this.z = z; }
        void add(float x, float y) {
            if (!pts.isEmpty()) {
                float[] p = pts.get(pts.size() - 1);
                len += (float) Math.hypot(x - p[0], y - p[1]);
            }
            pts.add(new float[]{x, y});
        }
    }

    public static float totalLen(List<Seg> segs) {
        float t = 0;
        for (Seg s : segs) t += s.len;
        return t;
    }

    public static List<Seg> build(GCode s) {
        if (s.mode == GCode.MODE_TAPER) return taper(s);
        if (s.mode == GCode.MODE_FACE) return face(s);
        if (s.mode == GCode.MODE_SPIRAL) return spiral(s);
        if (s.mode == GCode.MODE_KEY) return key(s);
        if (s.mode == GCode.MODE_OUTER) return outer(s);
        return pocket(s);
    }


    /** 工件/型腔轮廓参考线（闭合折线） */
    public static List<float[]> outline(GCode s) {
        List<float[]> pts = new ArrayList<>();
        if (s.mode == GCode.MODE_POCKET) {
            double a = s.length / 2, b = s.width / 2, rc = Math.min(s.cornerValue, Math.min(a, b));
            pts.add(new float[]{(float) a, 0f});
            pts.add(new float[]{(float) a, (float) (b - rc)});
            arcInto(pts, a - rc, b - rc, rc, 0, 90, true);
            pts.add(new float[]{(float) (-(a - rc)), (float) b});
            arcInto(pts, -(a - rc), b - rc, rc, 90, 180, true);
            pts.add(new float[]{(float) -a, (float) (-(b - rc))});
            arcInto(pts, -(a - rc), -(b - rc), rc, 180, 270, true);
            pts.add(new float[]{(float) (a - rc), (float) -b});
            arcInto(pts, a - rc, -(b - rc), rc, 270, 360, true);
            pts.add(new float[]{(float) a, 0f});
        } else if (s.mode == GCode.MODE_TAPER) {
            circlePts(pts, (float) (s.taperDia / 2));
        } else if (s.mode == GCode.MODE_FACE) {
            float hl = (float) (s.length / 2), hw = (float) (s.width / 2);
            pts.add(new float[]{-hl, -hw}); pts.add(new float[]{hl, -hw});
            pts.add(new float[]{hl, hw}); pts.add(new float[]{-hl, hw});
            pts.add(new float[]{-hl, -hw});
        } else if (s.mode == GCode.MODE_SPIRAL) {
            circlePts(pts, (float) (s.spiralDia / 2));
        } else if (s.mode == GCode.MODE_OUTER) {
            double a = s.length / 2, b = s.width / 2;
            double rc = (s.cornerType == GCode.CORNER_R) ? Math.min(s.cornerValue, Math.min(a, b)) : 0;
            pts.add(new float[]{(float) -(a - rc), (float) b});
            pts.add(new float[]{(float) (a - rc), (float) b});
            arcInto(pts, a - rc, b - rc, rc, 90, 0, true);
            pts.add(new float[]{(float) a, (float) -(b - rc)});
            arcInto(pts, a - rc, -(b - rc), rc, 0, -90, true);
            pts.add(new float[]{(float) -(a - rc), (float) -b});
            arcInto(pts, -(a - rc), -(b - rc), rc, 270, 180, true);
            pts.add(new float[]{(float) -a, (float) (b - rc)});
            arcInto(pts, -(a - rc), b - rc, rc, 180, 90, true);
            pts.add(new float[]{(float) -(a - rc), (float) b});
        } else {
            float xc = (float) ((s.keyLength - s.keyWidth) / 2);
            float yh = (float) (s.keyWidth / 2);
            pts.add(new float[]{-xc, -yh});
            pts.add(new float[]{xc, -yh});
            arcInto(pts, xc, 0, yh, -90, 90, true);
            pts.add(new float[]{xc, yh});
            pts.add(new float[]{-xc, yh});
            arcInto(pts, -xc, 0, yh, 90, 270, true);
            pts.add(new float[]{-xc, -yh});
        }
        return pts;
    }

    /** 立体视图的底面轮廓：锥孔用小头圆，其他模式沿用顶面轮廓 */
    public static List<float[]> outlineBottom(GCode s) {
        if (s.mode != GCode.MODE_TAPER) return null;
        List<float[]> pts = new ArrayList<>();
        circlePts(pts, (float) (s.taperDiaSmall / 2));
        return pts;
    }

    private static void circlePts(List<float[]> pts, float r) {
        int n = 48;
        for (int i = 0; i <= n; i++) {
            double a = 2 * Math.PI * i / n;
            pts.add(new float[]{(float) (r * Math.cos(a)), (float) (r * Math.sin(a))});
        }
    }

    private static void arcInto(Seg seg, double cx, double cy, double r, double a0, double a1, boolean used) {
        int n = 8;
        for (int i = 1; i <= n; i++) {
            double a = Math.toRadians(a0 + (a1 - a0) * i / n);
            seg.add((float) (cx + r * Math.cos(a)), (float) (cy + r * Math.sin(a)));
        }
    }

    private static void arcInto(List<float[]> pts, double cx, double cy, double r, double a0, double a1, boolean usedByRoundRect) {
        int n = 6;
        for (int i = 1; i <= n; i++) {
            double a = Math.toRadians(a0 + (a1 - a0) * i / n);
            pts.add(new float[]{(float) (cx + r * Math.cos(a)), (float) (cy + r * Math.sin(a))});
        }
    }

    // ---------- 通用：圆 / 圆角矩形 ----------
    private static void circle(Seg seg, float cx, float cy, float r, boolean ccw) {
        int n = 72;
        for (int i = 0; i <= n; i++) {
            double a = (ccw ? 1 : -1) * 2 * Math.PI * i / n;
            seg.add((float) (cx + r * Math.cos(a)), (float) (cy + r * Math.sin(a)));
        }
    }

    private static void roundRect(Seg seg, double a, double b, double rc) {
        // 起点 (a,0)，逆时针绕一圈：(a,b) (-a,b) (-a,-b) (a,-b) 回 (a,0)
        seg.add((float) a, 0f);
        seg.add((float) a, (float) (b - rc));
        corner(seg, a - rc, b - rc, rc, 0, 90);
        seg.add((float) (-(a - rc)), (float) b);
        corner(seg, -(a - rc), b - rc, rc, 90, 180);
        seg.add((float) (-a), (float) (-(b - rc)));
        corner(seg, -(a - rc), -(b - rc), rc, 180, 270);
        seg.add((float) (a - rc), (float) (-b));
        corner(seg, a - rc, -(b - rc), rc, 270, 360);
        seg.add((float) a, 0f);
    }

    private static void corner(Seg seg, double cx, double cy, double r, double a0, double a1) {
        int n = 6;
        for (int i = 1; i <= n; i++) {
            double a = Math.toRadians(a0 + (a1 - a0) * i / n);
            seg.add((float) (cx + r * Math.cos(a)), (float) (cy + r * Math.sin(a)));
        }
    }

    // ---------- 型腔：分层 + 每层从外向内缩的环 ----------
    private static List<Seg> pocket(GCode s) {
        List<Seg> out = new ArrayList<>();
        double a = s.length / 2, b = s.width / 2, r = s.toolDia / 2;
        double rc0 = s.cornerValue;
        for (double z = 0; z > -s.depth - 1e-9; z -= s.stepDown) {
            double zz = Math.max(z - s.stepDown, -s.depth);
            Seg plunge = new Seg(false, (float) zz);
            plunge.add(0f, 0f);
            Seg lead = new Seg(true, (float) zz);
            lead.add(0f, 0f);
            lead.add((float) (a - r), 0f);
            out.add(plunge);
            out.add(lead);
            double inset = r;
            int guard = 0;
            while (inset < Math.min(a, b) - 0.001 && guard++ < 200) {
                double ra = a - inset, rb = b - inset;
                double rc = Math.max(0.002, rc0 - inset);
                rc = Math.min(rc, Math.min(ra, rb));
                Seg seg = new Seg(true, (float) zz);
                roundRect(seg, ra, rb, rc);
                out.add(seg);
                inset += s.stepOver;
            }
            // 精修一圈
            Seg fin = new Seg(true, (float) -s.depth);
            roundRect(fin, a - r, b - r, Math.max(0.002, rc0 - r));
            out.add(fin);
        }
        return out;
    }

    // ---------- 锥孔：每层一个缩小的圆 ----------
    private static List<Seg> taper(GCode s) {
        List<Seg> out = new ArrayList<>();
        double bigR = s.taperDia / 2, r = s.toolDia / 2;
        double halfAngle = Math.toDegrees(Math.atan((s.taperDia / 2 - s.taperDiaSmall / 2) / s.taperDepth));
        double tanA = Math.tan(Math.toRadians(halfAngle));
        for (double z = 0; z < s.taperDepth - 1e-9; z += s.stepDown) {
            double zz = Math.min(z + s.stepDown, s.taperDepth);
            Seg down = new Seg(false, (float) -zz);
            down.add(0f, 0f);
            out.add(down);
            double rad = Math.max(0.01, bigR - r - zz * tanA);
            Seg seg = new Seg(true, (float) -zz);
            seg.add((float) Math.max(0.001, rad), 0f);
            circle(seg, 0f, 0f, (float) Math.max(0.001, rad), true);
            out.add(seg);
        }
        return out;
    }

    // ---------- 飞面：分行往复 ----------
    private static List<Seg> face(GCode s) {
        List<Seg> out = new ArrayList<>();
        double hl = s.length / 2, hw = s.width / 2;
        double row = s.toolDia * 0.75;
        for (double z = 0; z > -s.depth - 1e-9; z -= s.stepDown) {
            double zz = Math.max(z - s.stepDown, -s.depth);
            int dir = 1;
            for (double x = -hl; x <= hl + 1e-9; x += row) {
                Seg up = new Seg(false, (float) zz);
                up.add((float) x, (float) (hw * dir));
                out.add(up);
                Seg cut = new Seg(true, (float) zz);
                cut.add((float) x, (float) (hw * dir));
                cut.add((float) x, (float) (-hw * dir));
                out.add(cut);
                dir = -dir;
            }
        }
        return out;
    }

    // ---------- 螺旋铣：一圈圈连续下降 ----------
    private static List<Seg> spiral(GCode s) {
        List<Seg> out = new ArrayList<>();
        double R = s.spiralDia / 2 - s.toolDia / 2;
        int turns = (int) Math.ceil(s.depth / s.stepDown);
        Seg lead = new Seg(false, 0f);
        lead.add((float) -R, 0f);
        out.add(lead);
        for (int t = 0; t < turns; t++) {
            float z = (float) -Math.min(s.depth, (t + 1) * s.stepDown);
            Seg seg = new Seg(true, z);
            seg.add((float) -R, 0f);
            circle(seg, 0f, 0f, (float) R, true);
            out.add(seg);
        }
        return out;
    }

    // ---------- 键槽：按行、分层来回 ----------

    /** 只铣外方形：每层沿工件外侧顺时针绕一圈（带 R 圆角或 C 倒角） */
    private static List<Seg> outer(GCode s) {
        List<Seg> out = new ArrayList<>();
        double a = s.length / 2 + s.toolDia / 2;   // 刀心轮廓半长
        double b = s.width / 2 + s.toolDia / 2;
        boolean useR = s.cornerType == GCode.CORNER_R;
        double rc = useR ? Math.min(s.cornerValue, Math.min(a, b)) + s.toolDia / 2 : 0;
        double cc = (s.cornerType == GCode.CORNER_C) ? s.cornerValue : 0;
        double z0 = 0;
        while (true) {
            double zz = Math.max(z0 - s.stepDown, -s.depth);
            z0 = zz;
            Seg cut = new Seg(true, (float) zz);
            if (useR) {
                cut.add((float) (-(a - rc)), (float) b);
                cut.add((float) (a - rc), (float) b);
                arcInto(cut, a - rc, b - rc, rc, 90, 0, true);
                cut.add((float) a, (float) -(b - rc));
                arcInto(cut, a - rc, -(b - rc), rc, 0, -90, true);
                cut.add((float) -(a - rc), (float) -b);
                arcInto(cut, -(a - rc), -(b - rc), rc, 270, 180, true);
                cut.add((float) -a, (float) (b - rc));
                arcInto(cut, -(a - rc), b - rc, rc, 180, 90, true);
            } else {
                cut.add((float) (-(a - cc)), (float) b);
                cut.add((float) (a - cc), (float) b);
                cut.add((float) a, (float) (b - cc));
                cut.add((float) a, (float) -(b - cc));
                cut.add((float) (a - cc), (float) -b);
                cut.add((float) (-(a - cc)), (float) -b);
                cut.add((float) -a, (float) -(b - cc));
                cut.add((float) -a, (float) (b - cc));
                cut.add((float) (-(a - cc)), (float) b);
            }
            out.add(cut);
            if (zz <= -s.depth) break;
        }
        return out;
    }



    private static List<Seg> key(GCode s) {
        List<Seg> out = new ArrayList<>();
        double xh = (s.keyLength - s.keyWidth) / 2.0;              // 两端圆弧圆心 X
        double yh = Math.max(0.0, s.keyWidth / 2 - s.toolDia / 2); // 端弧刀心半径
        double z0 = 0;
        while (true) {
            double zz = Math.max(z0 - s.stepDown, -s.depth);
            z0 = zz;
            Seg cut = new Seg(true, (float) zz);
            cut.add((float) -xh, (float) -yh);
            cut.add((float) xh, (float) -yh);
            for (int i = 0; i <= 12; i++) {   // 右端 -90→90
                double a = Math.toRadians(-90 + 180.0 * i / 12);
                cut.add((float) (xh + yh * Math.cos(a)), (float) (yh * Math.sin(a)));
            }
            cut.add((float) -xh, (float) yh);
            for (int i = 0; i <= 12; i++) {   // 左端 90→270
                double a = Math.toRadians(90 + 180.0 * i / 12);
                cut.add((float) (-xh + yh * Math.cos(a)), (float) (yh * Math.sin(a)));
            }
            out.add(cut);
            if (zz <= -s.depth) break;
        }
        return out;
    }
}
