import SwiftUI
import Vision
import CoreImage

struct CropView: View {
    let image: UIImage
    let onComplete: (UIImage) -> Void
    let onRetake: () -> Void
    let onCancel: () -> Void

    @State private var corners: [CGPoint] = []
    @State private var activeCorner: Int?
    @State private var isProcessing = false
    @State private var viewSize: CGSize = .zero

    private var imageRect: CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let imgSize = image.size
        let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        return CGRect(
            x: (viewSize.width - w) / 2,
            y: (viewSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            imageArea
            bottomBar
        }
        .background(Color.black)
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .foregroundColor(.white)
            Spacer()
            Text("Adjust Edges")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Button("Retake") { onRetake() }
                .foregroundColor(.white)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.black)
    }

    // MARK: - Image + Overlay

    private var imageArea: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                if !corners.isEmpty {
                    CropOverlay(
                        corners: $corners,
                        activeCorner: $activeCorner,
                        imageRect: imageRect
                    )
                }
            }
            .onAppear {
                viewSize = geo.size
                if corners.isEmpty {
                    setDefaultCorners()
                    autoDetectEdges()
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Button(action: performCrop) {
            Group {
                if isProcessing {
                    ProgressView().tint(.white)
                } else {
                    Label("Create PDF", systemImage: "doc.badge.plus")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .background(Color.blue)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding()
        .disabled(isProcessing)
    }

    // MARK: - Corner Initialization

    private func setDefaultCorners() {
        let r = imageRect
        let inset: CGFloat = 24
        corners = [
            CGPoint(x: r.minX + inset, y: r.minY + inset),
            CGPoint(x: r.maxX - inset, y: r.minY + inset),
            CGPoint(x: r.maxX - inset, y: r.maxY - inset),
            CGPoint(x: r.minX + inset, y: r.maxY - inset)
        ]
    }

    // MARK: - Auto Edge Detection

    private func autoDetectEdges() {
        guard let cgImage = image.cgImage else { return }
        let rect = imageRect

        let request = VNDetectRectanglesRequest { request, _ in
            guard let obs = (request.results as? [VNRectangleObservation])?.first else { return }
            DispatchQueue.main.async {
                corners = [
                    visionToView(obs.topLeft, in: rect),
                    visionToView(obs.topRight, in: rect),
                    visionToView(obs.bottomRight, in: rect),
                    visionToView(obs.bottomLeft, in: rect)
                ]
            }
        }
        request.minimumConfidence = 0.5
        request.maximumObservations = 1
        request.minimumAspectRatio = 0.3

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func visionToView(_ pt: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + pt.x * rect.width,
            y: rect.minY + (1 - pt.y) * rect.height
        )
    }

    // MARK: - Perspective Correction

    private func performCrop() {
        guard corners.count == 4 else { return }
        isProcessing = true

        let imgCorners = corners.map { viewToImage($0) }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = applyPerspectiveCorrection(
                topLeft: imgCorners[0],
                topRight: imgCorners[1],
                bottomRight: imgCorners[2],
                bottomLeft: imgCorners[3]
            )
            DispatchQueue.main.async {
                isProcessing = false
                if let result { onComplete(result) }
            }
        }
    }

    private func viewToImage(_ pt: CGPoint) -> CGPoint {
        let r = imageRect
        guard r.width > 0, r.height > 0 else { return .zero }
        return CGPoint(
            x: (pt.x - r.minX) / r.width * image.size.width,
            y: (pt.y - r.minY) / r.height * image.size.height
        )
    }

    private func applyPerspectiveCorrection(
        topLeft: CGPoint, topRight: CGPoint,
        bottomRight: CGPoint, bottomLeft: CGPoint
    ) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let h = ciImage.extent.height

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: topLeft.x, y: h - topLeft.y), forKey: "inputTopLeft")
        filter.setValue(CIVector(x: topRight.x, y: h - topRight.y), forKey: "inputTopRight")
        filter.setValue(CIVector(x: bottomRight.x, y: h - bottomRight.y), forKey: "inputBottomRight")
        filter.setValue(CIVector(x: bottomLeft.x, y: h - bottomLeft.y), forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Crop Overlay (Canvas + Drag Gesture)

struct CropOverlay: View {
    @Binding var corners: [CGPoint]
    @Binding var activeCorner: Int?
    let imageRect: CGRect

    private let handleRadius: CGFloat = 15

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                guard corners.count == 4 else { return }

                var mask = Path()
                mask.addRect(CGRect(origin: .zero, size: size))
                mask.move(to: corners[0])
                mask.addLine(to: corners[1])
                mask.addLine(to: corners[2])
                mask.addLine(to: corners[3])
                mask.closeSubpath()
                ctx.fill(mask, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))

                var quad = Path()
                quad.move(to: corners[0])
                quad.addLine(to: corners[1])
                quad.addLine(to: corners[2])
                quad.addLine(to: corners[3])
                quad.closeSubpath()
                ctx.stroke(quad, with: .color(.white), style: StrokeStyle(lineWidth: 2.5))

                for (i, corner) in corners.enumerated() {
                    let r = handleRadius
                    let rect = CGRect(x: corner.x - r, y: corner.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white))
                    let inner = rect.insetBy(dx: 3, dy: 3)
                    ctx.fill(Path(ellipseIn: inner), with: .color(activeCorner == i ? .blue : .blue.opacity(0.7)))
                }

                for i in 0..<4 {
                    let a = corners[i]
                    let b = corners[(i + 1) % 4]
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    let dot = CGRect(x: mid.x - 4, y: mid.y - 4, width: 8, height: 8)
                    ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.7)))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if activeCorner == nil {
                        activeCorner = nearest(to: value.startLocation)
                    }
                    guard let idx = activeCorner else { return }
                    var pt = value.location
                    pt.x = max(imageRect.minX, min(imageRect.maxX, pt.x))
                    pt.y = max(imageRect.minY, min(imageRect.maxY, pt.y))
                    corners[idx] = pt
                }
                .onEnded { _ in activeCorner = nil }
        )
    }

    private func nearest(to point: CGPoint) -> Int? {
        var best: (Int, CGFloat)?
        for (i, c) in corners.enumerated() {
            let d = hypot(c.x - point.x, c.y - point.y)
            if d < 55, best == nil || d < best!.1 {
                best = (i, d)
            }
        }
        return best?.0
    }
}
