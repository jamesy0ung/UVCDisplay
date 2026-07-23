//
//  ContentView.swift
//  UVCDisplay
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = UVCViewModel()
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .connecting:
                connectingView

            case .streaming:
                streamingView

            case .stopped:
                stoppedView

            case .failed:
                ConsoleView(log: viewModel.log,
                            title: "Connection failed",
                            onRetry: { viewModel.retry() })
                    .background(Color(white: 0.08).ignoresSafeArea())
            }
        }
        .statusBarHidden(viewModel.state == .streaming)
        .task { viewModel.connect() }
    }

    private var stoppedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Display stopped")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Button("Reconnect") { viewModel.retry() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(32)
    }

    private var connectingView: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: "video.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 7) {
                Text("Finding your display")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Connecting to a USB video source…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView()
                .tint(.white)
        }
        .padding(32)
    }

    private var streamingView: some View {
        GeometryReader { proxy in
            ZStack {
                videoSurface(in: proxy.size)

                if showControls {
                    controls(safeAreaInsets: proxy.safeAreaInsets)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { showControls.toggle() } }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $viewModel.showConsole) {
            ConsoleView(log: viewModel.log, title: "Diagnostics")
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func videoSurface(in availableSize: CGSize) -> some View {
        let aspectRatio = max(viewModel.frameSize?.width ?? 16, 1)
            / max(viewModel.frameSize?.height ?? 9, 1)

        MetalVideoView(mtkView: viewModel.mtkView)
            .aspectRatio(aspectRatio,
                         contentMode: viewModel.videoScaling == .fit ? .fit : .fill)
            .frame(width: availableSize.width, height: availableSize.height)
            .clipped()
    }

    private func controls(safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("LIVE", systemImage: "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .red)

                if let size = viewModel.frameSize {
                    Text("\(Int(size.width)) × \(Int(size.height))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                Button {
                    viewModel.showConsole = true
                } label: {
                    Image(systemName: "text.alignleft")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Show diagnostics")
            }
            .padding(.horizontal, 18)
            .padding(.top, safeAreaInsets.top + 12)

            Spacer()

            HStack(spacing: 12) {
                Picker("Scaling", selection: $viewModel.videoScaling) {
                    ForEach(VideoScaling.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)

                Spacer()

                Button(role: .destructive) {
                    viewModel.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
            .padding(.bottom, safeAreaInsets.bottom + 12)
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.62)],
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    ContentView()
}
