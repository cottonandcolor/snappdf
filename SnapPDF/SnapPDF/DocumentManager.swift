import SwiftUI
import PDFKit
import Combine

struct ScannedDocument: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    let fileName: String
    let pageCount: Int
}

@MainActor
class DocumentManager: ObservableObject {
    @Published var documents: [ScannedDocument] = []

    private let baseDirectory: URL
    private let manifestURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = docs.appendingPathComponent("SnapPDF", isDirectory: true)
        manifestURL = baseDirectory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        loadDocuments()
    }

    func pdfURL(for document: ScannedDocument) -> URL {
        baseDirectory.appendingPathComponent(document.fileName)
    }

    func thumbnail(for document: ScannedDocument) -> UIImage? {
        let url = pdfURL(for: document)
        guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 200.0 / max(bounds.width, 1)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    func savePDF(from images: [UIImage]) -> ScannedDocument? {
        guard !images.isEmpty else { return nil }

        let id = UUID()
        let fileName = "\(id.uuidString).pdf"
        let url = baseDirectory.appendingPathComponent(fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: images[0].size))
        let data = renderer.pdfData { context in
            for image in images {
                let rect = CGRect(origin: .zero, size: image.size)
                context.beginPage(withBounds: rect, pageInfo: [:])
                image.draw(in: rect)
            }
        }

        do {
            try data.write(to: url)
        } catch {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm a"

        let doc = ScannedDocument(
            id: id,
            name: "Scan \(formatter.string(from: Date()))",
            createdAt: Date(),
            fileName: fileName,
            pageCount: images.count
        )
        documents.insert(doc, at: 0)
        saveManifest()
        return doc
    }

    func delete(_ document: ScannedDocument) {
        try? FileManager.default.removeItem(at: pdfURL(for: document))
        documents.removeAll { $0.id == document.id }
        saveManifest()
    }

    func rename(_ document: ScannedDocument, to newName: String) {
        guard let idx = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[idx].name = newName
        saveManifest()
    }

    private func loadDocuments() {
        guard let data = try? Data(contentsOf: manifestURL),
              let docs = try? JSONDecoder().decode([ScannedDocument].self, from: data) else { return }
        documents = docs
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: manifestURL)
    }
}

extension UIImage {
    func fixOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    func rotated90() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return self }
        ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        ctx.rotate(by: .pi / 2)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        draw(at: .zero)
        let rotated = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return rotated
    }
}
