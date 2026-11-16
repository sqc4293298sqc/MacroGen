import SwiftUI
import UIKit

/// 拍照/相册后先框住一个视图，避免把整张多视图总图当成一个零件。
struct DrawingCropView: View {
    let image: UIImage
    private let displayImage: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var crop = CGRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88)
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var lastValidCrop = CGRect(x: 0.06, y: 0.06, width: 0.88, height: 0.88)

    init(image: UIImage, onCrop: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.displayImage = DrawingScanner.prepare(image, maxDimension: 3000)
        self.onCrop = onCrop
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("在图纸上拖一个框，只框住一个正视图/俯视图。框得越小，识别越准。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                GeometryReader { geo in
                    let fit = fitRect(imageSize: displayImage.size, in: geo.size)
                    ZStack {
                        Color.black.opacity(0.04)
                        Image(uiImage: displayImage)
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)

                        Canvas { ctx, size in
                            guard fit.width > 1, fit.height > 1 else { return }
                            let r = CGRect(
                                x: fit.minX + crop.minX * fit.width,
                                y: fit.minY + crop.minY * fit.height,
                                width: max(crop.width * fit.width, 1),
                                height: max(crop.height * fit.height, 1))

                            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: r.minY)),
                                     with: .color(.black.opacity(0.42)))
                            ctx.fill(Path(CGRect(x: 0, y: r.maxY, width: size.width, height: size.height - r.maxY)),
                                     with: .color(.black.opacity(0.42)))
                            ctx.fill(Path(CGRect(x: 0, y: r.minY, width: r.minX, height: r.height)),
                                     with: .color(.black.opacity(0.42)))
                            ctx.fill(Path(CGRect(x: r.maxX, y: r.minY, width: size.width - r.maxX, height: r.height)),
                                     with: .color(.black.opacity(0.42)))

                            ctx.stroke(Path(roundedRect: r, cornerRadius: 2),
                                       with: .color(.orange), lineWidth: 2)
                            let handles = [
                                CGPoint(x: r.minX, y: r.minY),
                                CGPoint(x: r.maxX, y: r.minY),
                                CGPoint(x: r.maxX, y: r.maxY),
                                CGPoint(x: r.minX, y: r.maxY)
                            ]
                            for h in handles {
                                ctx.fill(Path(ellipseIn: CGRect(x: h.x - 6, y: h.y - 6, width: 12, height: 12)),
                                         with: .color(.white))
                                ctx.stroke(Path(ellipseIn: CGRect(x: h.x - 6, y: h.y - 6, width: 12, height: 12)),
                                           with: .color(.orange), lineWidth: 1.2)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                let p = normalized(value.location, in: fit)
                                if dragStart == nil {
                                    dragStart = p
                                    dragCurrent = p
                                } else {
                                    dragCurrent = p
                                }
                                guard let a = dragStart, let b = dragCurrent else { return }
                                let rect = CGRect(
                                    x: min(a.x, b.x),
                                    y: min(a.y, b.y),
                                    width: abs(b.x - a.x),
                                    height: abs(b.y - a.y)
                                ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                                if rect.width > 0.01, rect.height > 0.01 {
                                    crop = rect
                                }
                            }
                            .onEnded { _ in
                                dragStart = nil
                                dragCurrent = nil
                                if crop.width < 0.08 || crop.height < 0.08 {
                                    crop = lastValidCrop
                                } else {
                                    lastValidCrop = crop
                                }
                            }
                    )
                }
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button("整张图") {
                        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                        lastValidCrop = crop
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button {
                        guard let cropped = DrawingScanner.crop(image, normalizedRect: crop) else {
                            return
                        }
                        onCrop(cropped)
                        dismiss()
                    } label: {
                        Label("识别框内", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)

                Text("提示：总图里有多个视图、剖视图、局部放大图时，必须只框一个视图；整张图直接识别会把别的视图和文字当成孔。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("框选图纸视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func fitRect(imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 1, imageSize.height > 1, size.width > 1, size.height > 1 else {
            return CGRect(origin: .zero, size: size)
        }
        let s = min(size.width / imageSize.width, size.height / imageSize.height)
        let w = imageSize.width * s
        let h = imageSize.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func normalized(_ p: CGPoint, in fit: CGRect) -> CGPoint {
        CGPoint(
            x: min(1, max(0, (p.x - fit.minX) / max(fit.width, 1))),
            y: min(1, max(0, (p.y - fit.minY) / max(fit.height, 1)))
        )
    }
}
