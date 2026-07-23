//
//  MetalVideoView.swift
//  UVCDisplay
//

import SwiftUI
import MetalKit

struct MetalVideoView: UIViewRepresentable {
    let mtkView: MTKView

    func makeUIView(context: Context) -> MTKView { mtkView }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
