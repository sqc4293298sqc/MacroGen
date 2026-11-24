import SwiftUI
import WebKit

/// 加工中心模拟：VMC850 / FANUC 0i-MF 技术样机
/// 3D 场景与 UI 在 machine_sim.html 内，WKWebView 只是原生容器。
struct MachineSimScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MachineSimWebView(onClose: { dismiss() })
            .ignoresSafeArea(edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(red: 0.04, green: 0.06, blue: 0.08))
    }
}

private struct MachineSimWebView: UIViewRepresentable {
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "close")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.isMultipleTouchEnabled = true
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // 让页面自己处理双指 pinch，避免 WKWebView 把整页缩放抢走
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false

        if let url = Bundle.main.url(forResource: "machine_sim", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "close" else { return }
            onClose()
        }
    }
}
