import SwiftUI
import PhotosUI
import UIKit

/// 拍照 / 相册 / 文件 / 粘贴 → 自动识别（ocr.space，需自己的免费 key）→ 清洗 → 直接送进模拟
struct ImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var status = "拍照或截图后点「开始识别」，也可以直接粘贴程序"
    @State private var showKey = false
    @State private var keyInput = UserDefaults.standard.string(forKey: "ocr_key") ?? ""
    @State private var busy = false
    @State private var goSim = false

    private var hasKey: Bool { !keyInput.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    action("拍照") { showCamera = true }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text("相册")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    action("粘贴") { paste() }
                    action("识别 Key") { showKey = true }
                }

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    runOcr()
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "识别中…" : "开始识别")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 6) {
                    action("清洗格式") {
                        let out = ProgramCleaner.clean(text)
                        text = out
                        status = "已清洗，剩 \(out.split(separator: "\n").count) 行"
                    }
                    Button {
                        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !code.isEmpty else { status = "还没有程序内容"; return }
                        goSim = true
                    } label: {
                        Text("送去模拟 ›")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .navigationTitle("识别 / 导入程序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { img in
                    image = img
                    status = "图片已就绪，点「开始识别」；认得不准就直接改下面的字"
                }
            }
            .alert("OCR 识别 Key", isPresented: $showKey) {
                TextField("粘贴 ocr.space 免费 key", text: $keyInput)
                Button("保存") {
                    UserDefaults.standard.set(keyInput.trimmingCharacters(in: .whitespaces), forKey: "ocr_key")
                    status = hasKey ? "已保存 Key" : "Key 已清空，可继续手工粘贴"
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("去 ocr.space/ocrapi/freekey 领一个免费 key，填一次长期可用；没有 key 就粘贴程序。")
            }
            .onChange(of: pickerItem) { _ in loadPicker() }
            .navigationDestination(isPresented: $goSim) {
                SimScreen(code: text)
            }
        }
    }

    private func action(_ t: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color(.tertiarySystemFill))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func paste() {
        guard let s = UIPasteboard.general.string else { status = "剪贴板是空的"; return }
        text = ProgramCleaner.clean(s)
        status = "已粘贴并清洗，核对后点「送去模拟」"
    }

    private func loadPicker() {
        guard let item = pickerItem else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                image = img
                status = "图片已就绪，点「开始识别」"
            }
        }
    }

    private func runOcr() {
        guard let img = image else { status = "先拍照或从相册选一张程序照片"; return }
        guard hasKey else {
            status = "还没有 Key：用手机相册/微信「提取文字」复制后点「粘贴」也一样能进模拟"
            return
        }
        busy = true
        status = "正在识别，稍等…"
        let jpeg = resize(img, max: 1600).jpegData(compressionQuality: 0.82) ?? Data()
        let b64 = "data:image/jpeg;base64," + jpeg.base64EncodedString()

        var req = URLRequest(url: URL(string: "https://api.ocr.space/parse/image")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        let body = [
            "apikey=" + keyInput.trimmingCharacters(in: .whitespaces),
            "language=eng",
            "isOverlayRequired=false",
            "scale=true",
            "OCREngine=2",
            "filetype=JPG",
            "base64Image=" + (b64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? b64)
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                busy = false
                if let err = err {
                    status = "识别失败：" + err.localizedDescription
                    return
                }
                guard let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    status = "识别服务返回异常"
                    return
                }
                if let arr = obj["ParsedResults"] as? [[String: Any]] {
                    let raw = arr.map { $0["ParsedText"] as? String ?? "" }.joined()
                    let out = ProgramCleaner.clean(raw)
                    if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        status = "图里没认出文字，拍正一点、离近一点再试"
                    } else {
                        text = out
                        status = "识别完成，剩 \(out.split(separator: "\n").count) 行；OCR 一定会认错几个字符，核对后再模拟"
                    }
                } else {
                    status = "识别失败：Key 无效或今日额度用完，换个 key 再试"
                }
            }
        }.resume()
    }

    private func resize(_ img: UIImage, max: CGFloat) -> UIImage {
        let w = img.size.width, h = img.size.height
        let big = Swift.max(w, h)
        guard big > max else { return img }
        let s = max / big
        let size = CGSize(width: w * s, height: h * s)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        img.draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? img
        UIGraphicsEndImageContext()
        return out
    }
}

/// 系统相机
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// 把 OCR 脏字符整成机床能跑的写法（与安卓端规则一致）
enum ProgramCleaner {
    private static let keywords = ["WHILE", "GOTO", "END", "THEN", "SQRT", "ROUND",
                                   "ATAN", "SIN", "COS", "TAN", "ABS", "FIX", "FUP",
                                   "GT", "GE", "LT", "LE", "EQ", "NE", "DO"]

    static func clean(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        var s = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let fullMap: [(String, String)] = [
            ("，", ","), ("。", "."), ("；", ";"), ("（", "("), ("）", ")"),
            ("［", "["), ("］", "]"), ("＃", "#"), ("＝", "="), ("＋", "+"),
            ("－", "-"), ("　", " "), ("／", "/"), ("＊", "*"), ("．", "."),
            ("Ｏ", "O"), ("Ｌ", "L"), ("Ｉ", "I"), ("Ｎ", "N"), ("Ｗ", "W"),
            ("Ｈ", "H"), ("Ｅ", "E"), ("Ｔ", "T"), ("Ｄ", "D"), ("Ｒ", "R"),
            ("Ａ", "A"), ("Ｂ", "B"), ("Ｃ", "C"), ("Ｇ", "G"), ("Ｍ", "M"),
            ("Ｘ", "X"), ("Ｙ", "Y"), ("Ｚ", "Z"), ("Ｐ", "P"), ("Ｆ", "F"),
            ("Ｓ", "S"), ("Ｋ", "K"), ("Ｊ", "J"), ("０", "0"), ("１", "1"),
            ("２", "2"), ("３", "3"), ("４", "4"), ("５", "5"), ("６", "6"),
            ("７", "7"), ("８", "8"), ("９", "9")
        ]
        for (a, b) in fullMap { s = s.replacingOccurrences(of: a, with: b) }

        var out: [String] = []
        for line in s.components(separatedBy: "\n") {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("*") && !t.contains("G") { continue }
            while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
            t = fixLooks(t.uppercased())
            if looksLikeProgram(t) { out.append(t) }
        }
        return out.joined(separator: "\n")
    }

    private static func fixLooks(_ t: String) -> String {
        var work = t
        for (i, k) in keywords.enumerated() { work = work.replacingOccurrences(of: k, with: "@\(i)@") }
        let chars = Array(work)
        let address = "ABCFGHIJKMNOPQRSTUVWXYZ"
        var out = ""
        for i in 0..<chars.count {
            let c = chars[i]
            let prev: Character = i > 0 ? chars[i - 1] : " "
            let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
            // 紧跟 [ # - + 的字母是地址字（如 I[-#21]），绝不能当数字改
            if next == "[" || next == "#" || next == "-" || next == "+" {
                out.append(c)
                continue
            }
            let prevOk = prev.isNumber || prev == "." ||
                (address.contains(prev) && (next.isNumber || !next.isLetter))
            if "OQD".contains(c) && prevOk {
                out.append("0")
            } else if "l|L".contains(c) && prevOk {   // 不含 I：I 是圆弧/参数地址
                out.append("1")
            } else {
                out.append(c)
            }
        }
        var s = out
        for (i, k) in keywords.enumerated() { s = s.replacingOccurrences(of: "@\(i)@", with: k) }
        s = s.replacingOccurrences(of: "DOl", with: "DO1")
        s = s.replacingOccurrences(of: "DOL", with: "DO1")
        s = s.replacingOccurrences(of: "ENDL", with: "END1")
        return s
    }

    private static func looksLikeProgram(_ t: String) -> Bool {
        if t.count < 2 { return false }
        if t.count <= 2 && t.allSatisfy({ $0.isNumber }) { return false }
        if t.contains("G") || t.contains("M") || t.contains("#") || t.contains("/") { return true }
        for p in ["WHILE", "END", "IF", "O", "N", "("] where t.hasPrefix(p) { return true }
        return false
    }
}
