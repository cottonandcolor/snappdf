import UIKit
import CoreImage

enum FilterMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case original = "Original"
    case grayscale = "Grayscale"
    case bw = "B&W"

    var id: String { rawValue }
}

struct ManualAdjustments: Equatable {
    var brightness: Double = 0.0   // -0.3 ... 0.3
    var contrast: Double = 1.0     // 0.5 ... 2.0
    var sharpness: Double = 0.0    // 0.0 ... 1.0

    static let `default` = ManualAdjustments()

    var isDefault: Bool {
        brightness == 0.0 && contrast == 1.0 && sharpness == 0.0
    }
}

final class ImageEnhancer {
    static let shared = ImageEnhancer()
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func apply(_ mode: FilterMode, to image: UIImage, adjustments: ManualAdjustments = .default) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        var output: CIImage
        switch mode {
        case .auto:      output = autoEnhance(ciImage)
        case .grayscale: output = grayscale(ciImage)
        case .bw:        output = blackAndWhite(ciImage)
        case .original:  output = ciImage
        }

        if !adjustments.isDefault {
            output = applyManual(output, adjustments: adjustments)
        }

        if mode == .original && adjustments.isDefault { return image }

        guard let cg = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cg)
    }

    private func applyManual(_ image: CIImage, adjustments: ManualAdjustments) -> CIImage {
        var out = image

        if adjustments.brightness != 0.0 || adjustments.contrast != 1.0 {
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(out, forKey: kCIInputImageKey)
                f.setValue(adjustments.brightness, forKey: kCIInputBrightnessKey)
                f.setValue(adjustments.contrast, forKey: kCIInputContrastKey)
                if let r = f.outputImage { out = r }
            }
        }

        if adjustments.sharpness > 0 {
            if let f = CIFilter(name: "CISharpenLuminance") {
                f.setValue(out, forKey: kCIInputImageKey)
                f.setValue(adjustments.sharpness, forKey: kCIInputSharpnessKey)
                if let r = f.outputImage { out = r }
            }
        }

        return out
    }

    // MARK: - Auto Enhance

    private func autoEnhance(_ image: CIImage) -> CIImage {
        var out = image

        // Even out lighting — lift shadows, tame highlights
        if let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(1.0, forKey: "inputShadowAmount")
            f.setValue(0.6, forKey: "inputHighlightAmount")
            if let r = f.outputImage { out = r }
        }

        // Slight brightness bump + contrast boost
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(0.05, forKey: kCIInputBrightnessKey)
            f.setValue(1.2, forKey: kCIInputContrastKey)
            f.setValue(1.0, forKey: kCIInputSaturationKey)
            if let r = f.outputImage { out = r }
        }

        // Sharpen for text clarity
        if let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(0.6, forKey: kCIInputSharpnessKey)
            if let r = f.outputImage { out = r }
        }

        return out
    }

    // MARK: - Grayscale

    private func grayscale(_ image: CIImage) -> CIImage {
        var out = image

        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(0.0, forKey: kCIInputSaturationKey)
            f.setValue(1.15, forKey: kCIInputContrastKey)
            f.setValue(0.05, forKey: kCIInputBrightnessKey)
            if let r = f.outputImage { out = r }
        }

        if let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(0.5, forKey: kCIInputSharpnessKey)
            if let r = f.outputImage { out = r }
        }

        return out
    }

    // MARK: - Black & White (high contrast, ideal for text)

    private func blackAndWhite(_ image: CIImage) -> CIImage {
        var out = image

        // Desaturate + heavy contrast for crisp text
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(0.0, forKey: kCIInputSaturationKey)
            f.setValue(2.0, forKey: kCIInputContrastKey)
            f.setValue(0.1, forKey: kCIInputBrightnessKey)
            if let r = f.outputImage { out = r }
        }

        // Sharpen
        if let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(0.8, forKey: kCIInputSharpnessKey)
            if let r = f.outputImage { out = r }
        }

        return out
    }
}
