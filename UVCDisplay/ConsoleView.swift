//
//  ConsoleView.swift
//  UVCDisplay
//

import SwiftUI

struct ConsoleView: View {
    let log: String
    var title: String = "Console"
    var onRetry: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                if let onClose {
                    Button("Close", action: onClose).buttonStyle(.bordered)
                }
                if let onRetry {
                    Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.isEmpty ? "(no output)" : log)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                        .id("logBottom")
                }
                .foregroundStyle(.white.opacity(0.86))
                .onChange(of: log) { _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
            .background(Color.black.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
        .padding()
    }
}
