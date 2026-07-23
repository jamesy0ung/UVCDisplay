//
//  UVCViewModel.swift
//  UVCDisplay
//

import Foundation
import Combine
import MetalKit

enum ConnectionState: Equatable {
    case connecting
    case streaming
    case stopped
    case failed
}

enum VideoScaling: String, CaseIterable, Identifiable {
    case fit = "Fit"
    case fill = "Fill"

    var id: Self { self }
}

@MainActor
final class UVCViewModel: ObservableObject {
    @Published var state: ConnectionState = .connecting
    @Published var log: String = ""
    @Published var showConsole: Bool = false
    @Published private(set) var frameSize: CGSize?
    @Published var videoScaling: VideoScaling = .fit

    let mtkView = MTKView()

    private let bridge = UVCBridge()
    private let renderer: YUY2Renderer?

    init() {
        renderer = YUY2Renderer(mtkView: mtkView)

        bridge.logHandler = { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }

        // Avoid reading main actor state from the libuvc thread.
        let renderer = self.renderer
        bridge.frameHandler = { [weak self] data, width, height, length in
            let sizeChanged = renderer?.update(bytes: data,
                                               width: Int(width),
                                               height: Int(height),
                                               length: length) ?? false

            guard sizeChanged else { return }
            let size = CGSize(width: Int(width), height: Int(height))
            Task { @MainActor [weak self] in
                self?.frameSize = size
            }
        }
    }

    func connect() {
        state = .connecting
        frameSize = nil
        Task.detached { [bridge] in
            let started = bridge.startStreaming()
            var gotFrames = false
            if started {
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if bridge.frameCount > 0 { gotFrames = true; break }
                }
            }

            if started && gotFrames {
                await MainActor.run { self.state = .streaming }
            } else {
                bridge.stopStreaming()
                if started { await MainActor.run { self.append("Opened but no frames arrived.") } }
                bridge.scan()
                await MainActor.run { self.state = .failed }
            }
        }
    }

    func stop() {
        Task.detached { [bridge] in
            bridge.stopStreaming()
            await MainActor.run {
                self.state = .stopped
                self.showConsole = false
            }
        }
    }

    func retry() {
        showConsole = false
        connect()
    }

    private func append(_ line: String) {
        log += line + "\n"
    }
}
