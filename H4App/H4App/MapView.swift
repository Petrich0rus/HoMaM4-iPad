import MetalKit
import SwiftUI

/// Placeholder for the future Metal map renderer: an empty MTKView cleared to a flat colour.
struct MapView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalSurface().ignoresSafeArea()
            HStack {
                Button("Close", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.borderedProminent)
                Text(title).font(.headline).foregroundStyle(.white)
            }
            .padding()
        }
    }
}

private struct MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1)
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}
    func makeCoordinator() -> Clearer { Clearer() }

    final class Clearer: NSObject, MTKViewDelegate {
        private var queue: MTLCommandQueue?

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            queue = queue ?? view.device?.makeCommandQueue()
            guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let buffer = queue?.makeCommandBuffer() else { return }
            buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}
