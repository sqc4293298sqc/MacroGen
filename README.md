# MacroGen — 加工中心宏程序生成器（iOS）

输入型腔长宽深、四角 R 或 C、刀具与切削参数，一键生成 FANUC 宏程序。

## 生成的程序包含

- 变量区 `#1–#30`：长/宽/深/角值/刀径/AP/AE/S/F
- 分层粗铣：`WHILE` 循环，逐层下刀，中心斜插进刀
- 环形清腔：从刀半径内缩起，按行距逐圈向内
- 精修壁面：`G41 D_` 刀具半径补偿走完整轮廓
- 四角支持 R 圆弧（G02）与 C 倒角（直线段）

## 目录

```
MacroGen/
├── project.yml                  XcodeGen 工程配置
├── Sources/
│   ├── MacroGenApp.swift        入口
│   ├── ContentView.swift        输入表单 + 结果页
│   └── GCodeGenerator.swift     宏程序生成逻辑
└── .github/workflows/
    └── build-ipa.yml            macOS 构建流水线（产出未签名 ipa）
```

## 构建方式

### A. 云端（无需 Mac）

推到 GitHub 仓库，Actions 自动跑 macOS 构建：

1. 新建仓库，上传本目录全部内容
2. 打开 Actions → build-ipa → Run workflow
3. 等 3–5 分钟，下载 artifact `MacroGen-ipa`

### B. 本地 Mac

```bash
brew install xcodegen
xcodegen generate
open MacroGen.xcodeproj
```

选自己的开发者账号 Run 到手机即可。

## 越狱机安装

未签名 ipa 在越狱设备上：

```bash
# 手机上（装了 Filza）
把 MacroGen-unsigned.ipa 拷到 /var/mobile/Documents，点开直接装
```

或 SSH 后用 `ipainstaller MacroGen-unsigned.ipa`。

## 注意

- 生成的代码默认 `G54`、X0Y0 为型腔中心、Z0 为工件顶面
- 刀补号 `D` 需在机床刀补表里设好刀具半径
- R 小于刀具半径时 App 会告警：壁角一刀切不到，需换小刀清角
- 首件务必空运行 + 单段，Depth 值改了要重新核对 Z 向
