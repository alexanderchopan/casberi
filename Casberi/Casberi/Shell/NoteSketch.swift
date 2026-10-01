import SwiftUI
import PencilKit

/// SKETCH into a note (prd §1023) — Apple's canvas (`PKCanvasView`) with
/// Apple's tool picker (`PKToolPicker`), raised from the note sheet's Attach
/// menu beside Choose a photo and Scan a document. Nothing here draws a tool.
///
/// A note holds ONE picture (§974), and a sketch IS a picture: on close the
/// drawing is flattened over the page's black at the app's one stored size
/// (`NotePicture.prepared`), so the row, the lede, the page and the card draw
/// it with nothing new. The strokes are not kept — a new field would be a
/// separate CloudKit Production ship — and a sketch opened again draws OVER
/// the kept picture, which the canvas takes as its background.
///
/// Pulling the sheet down keeps, as the note sheet's own dismiss keeps (§969);
/// an empty canvas keeps nothing. The canvas is dark, so PencilKit maps the
/// picker's black ink to white on it (the system's own dark-mode rule), and
/// the first tool is a white pen so the first stroke shows.
struct NoteSketchSheet: View {
    /// The picture to draw over, when the note already has one.
    let over: UIImage?
    /// The flattened result, or nil when nothing was drawn.
    let onKeep: (UIImage?) -> Void

    @State private var drawing = PKDrawing()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SketchCanvas(drawing: $drawing, over: over)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.black)
            .onDisappear { onKeep(flattened()) }
    }

    /// The drawing over the page (and over the kept picture, when drawing
    /// again), as one opaque bitmap; nil when no stroke was made and there
    /// was nothing under it to keep.
    private func flattened() -> UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        let page = CGRect(origin: .zero, size: CGSize(width: 480, height: 640))
        let bounds = drawing.bounds.isEmpty ? page : drawing.bounds.union(page)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let strokes = drawing.image(from: bounds, scale: 2)
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            if let over {
                // The kept picture stands where the canvas showed it: top-left, at width.
                let w = bounds.size.width
                let h = w * over.size.height / max(over.size.width, 1)
                over.draw(in: CGRect(x: -bounds.minX, y: -bounds.minY, width: w, height: h))
            }
            strokes.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
    }
}

/// The canvas and its picker. The picker is attached to the canvas as first
/// responder, the way Apple's own apps show it; on the Mac the picker is a
/// floating palette, the pointer draws.
private struct SketchCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let over: UIImage?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .black
        canvas.isOpaque = over == nil
        canvas.overrideUserInterfaceStyle = .dark
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.tool = PKInkingTool(.pen, color: .white, width: 4)
        if let over {
            let image = UIImageView(image: over)
            image.contentMode = .scaleAspectFit
            image.translatesAutoresizingMaskIntoConstraints = false
            canvas.insertSubview(image, at: 0)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: canvas.frameLayoutGuide.leadingAnchor),
                image.trailingAnchor.constraint(equalTo: canvas.frameLayoutGuide.trailingAnchor),
                image.topAnchor.constraint(equalTo: canvas.frameLayoutGuide.topAnchor),
                image.heightAnchor.constraint(equalTo: image.widthAnchor,
                                              multiplier: over.size.height / max(over.size.width, 1)),
            ])
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
        }
        context.coordinator.picker = PKToolPicker()
        context.coordinator.picker?.setVisible(true, forFirstResponder: canvas)
        context.coordinator.picker?.addObserver(canvas)
        context.coordinator.picker?.colorUserInterfaceStyle = .dark
        context.coordinator.picker?.selectedTool = canvas.tool
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: SketchCanvas
        var picker: PKToolPicker?
        init(_ parent: SketchCanvas) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
