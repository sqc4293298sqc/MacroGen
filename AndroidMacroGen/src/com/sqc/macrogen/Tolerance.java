package com.sqc.macrogen;

/** 尺寸公差计算：按 GB/T 1800.2—2020（ISO 286-2）数值，单位 μm 转 mm */
public final class Tolerance {

    // 公称尺寸分段（大于 ~ 至，mm）
    public static final double[][] RANGES = {
            {0, 3}, {3, 6}, {6, 10}, {10, 18}, {18, 30}, {30, 50}, {50, 80},
            {80, 120}, {120, 180}, {180, 250}, {250, 315}, {315, 400}, {400, 500}
    };

    // 标准公差 IT5~IT16（μm）
    private static final int[][] IT = {
            {4, 5, 6, 8, 9, 11, 13, 15, 18, 20, 23, 25, 27},            // IT5
            {6, 8, 9, 11, 13, 16, 19, 22, 25, 29, 32, 36, 40},          // IT6
            {10, 12, 15, 18, 21, 25, 30, 35, 40, 46, 52, 57, 63},       // IT7
            {14, 18, 22, 27, 33, 39, 46, 54, 63, 72, 81, 89, 97},       // IT8
            {25, 30, 36, 43, 52, 62, 74, 87, 100, 115, 130, 140, 155},  // IT9
            {40, 48, 58, 70, 84, 100, 120, 140, 160, 185, 210, 230, 250},// IT10
            {60, 75, 90, 110, 130, 160, 190, 220, 250, 290, 320, 360, 400},// IT11
            {100, 120, 150, 180, 210, 250, 300, 350, 400, 460, 520, 570, 630},// IT12
            {140, 180, 220, 270, 330, 390, 460, 540, 630, 720, 810, 890, 970},// IT13
            {250, 300, 360, 430, 520, 620, 740, 870, 1000, 1150, 1300, 1400, 1550},// IT14
            {400, 480, 580, 700, 840, 1000, 1200, 1400, 1600, 1850, 2100, 2300, 2500},// IT15
            {640, 750, 900, 1100, 1300, 1600, 1900, 2200, 2500, 2900, 3200, 3600, 4000}// IT16
    };

    // 轴的基本偏差 es（μm，负值）
    private static final int[] D = {-20, -30, -40, -50, -65, -80, -100, -120, -145, -170, -190, -210, -230};
    private static final int[] E = {-14, -20, -25, -32, -40, -50, -60, -72, -85, -100, -110, -125, -135};
    private static final int[] F = {-6, -10, -13, -16, -20, -25, -30, -36, -43, -50, -56, -62, -68};
    private static final int[] G = {-2, -4, -5, -6, -7, -9, -10, -12, -14, -15, -17, -18, -20};

    // 轴的下偏差 ei（μm，k/m/n/p 为正值）
    private static final int[] K_EI = {0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 5};
    private static final int[] M_EI = {2, 4, 6, 7, 8, 9, 11, 13, 15, 17, 20, 21, 23};
    private static final int[] N_EI = {4, 8, 10, 12, 15, 17, 20, 23, 27, 31, 34, 37, 40};
    private static final int[] P_EI = {6, 12, 15, 18, 22, 26, 32, 37, 43, 50, 56, 62, 68};

    public static final String[] HOLE_POS = {"H", "G", "F", "E", "D", "JS"};
    public static final String[] SHAFT_POS = {"h", "g", "f", "e", "d", "js", "k", "m", "n", "p"};
    public static final int MIN_GRADE = 5, MAX_GRADE = 12;

    private Tolerance() { }

    public static int rangeIndex(double d) {
        for (int i = 0; i < RANGES.length; i++) {
            if (d > RANGES[i][0] && d <= RANGES[i][1]) return i;
            if (i == 0 && d <= 3) return 0;
        }
        return -1;
    }

    public static int it(double size, int grade) {
        int i = rangeIndex(size);
        if (i < 0 || grade < MIN_GRADE || grade > MAX_GRADE) return -1;
        return IT[grade - MIN_GRADE][i];
    }

    /** 轴的上/下偏差（μm） */
    public static int[] shaftDev(String pos, double size, int grade) {
        int i = rangeIndex(size);
        if (i < 0) return null;
        int t = IT[grade - MIN_GRADE][i];
        if (pos.equals("js")) return new int[]{t / 2, -t / 2, t};
        if (pos.equals("h")) return new int[]{0, -t, t};
        int es;
        switch (pos) {
            case "g": es = G[i]; break;
            case "f": es = F[i]; break;
            case "e": es = E[i]; break;
            case "d": es = D[i]; break;
            case "k":
                int eiK = grade <= 7 ? K_EI[i] : 0;
                return new int[]{eiK + t, eiK, t};
            case "m": return new int[]{M_EI[i] + t, M_EI[i], t};
            case "n": return new int[]{N_EI[i] + t, N_EI[i], t};
            case "p": return new int[]{P_EI[i] + t, P_EI[i], t};
            default: return null;
        }
        return new int[]{es, es - t, t};
    }

    /** 孔的上/下偏差（μm）：ES, EI, IT */
    public static int[] holeDev(String pos, double size, int grade) {
        int i = rangeIndex(size);
        if (i < 0) return null;
        int t = IT[grade - MIN_GRADE][i];
        if (pos.equals("JS")) return new int[]{t / 2, -t / 2, t};
        if (pos.equals("H")) return new int[]{t, 0, t};
        int[] s = shaftDev(pos.toLowerCase(), size, grade);
        if (s == null) return null;
        int ei = -s[0];
        return new int[]{ei + t, ei, t};
    }

    public static String fmt(int um) {
        return (um >= 0 ? "+" : "") + String.format("%.3f", um / 1000.0);
    }

    /** 带半微米精度的显示（js/JS 用） */
    public static String fmtHalf(int um) {
        double mm = um / 2000.0;
        return (mm >= 0 ? "+" : "") + String.format("%.4f", mm);
    }

    public static String gradeName(String pos, int grade) {
        return pos + grade;
    }

    /** 配合性质说明：间隙 / 过盈 / 过渡 */
    public static String fitType(String hole, String shaft, double size, int hGrade, int sGrade) {
        int[] h = holeDev(hole, size, hGrade);
        int[] s = shaftDev(shaft, size, sGrade);
        if (h == null || s == null) return "";
        int maxGap = h[0] - s[1];   // ES - ei
        int minGap = h[1] - s[0];   // EI - es
        if (minGap > 0) return "间隙配合";
        if (maxGap < 0) return "过盈配合";
        return "过渡配合";
    }
}
