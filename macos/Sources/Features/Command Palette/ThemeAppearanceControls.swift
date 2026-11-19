import SwiftUI

/// Controls for the app-wide background opacity and acrylic blur, shown in
/// the theme picker footer.
struct ThemeAppearanceControls: View {
    let ghostty: Ghostty.App
    @ObservedObject var config: Ghostty.Config

    @State private var opacity: Double
    @State private var blurEnabled: Bool
    @State private var applyWorkItem: DispatchWorkItem?

    init(ghostty: Ghostty.App, config: Ghostty.Config) {
        self.ghostty = ghostty
        self.config = config
        _opacity = State(initialValue: config.backgroundOpacity)
        _blurEnabled = State(initialValue: config.backgroundBlur.isEnabled)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Opacity")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Slider(value: $opacity, in: 0...1) { editing in
                if !editing {
                    applyWorkItem?.cancel()
                    applyOpacity()
                }
            }
            .accessibilityLabel("Opacity")

            Text("\(Int((opacity * 100).rounded()))%")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Toggle(isOn: $blurEnabled) {
                Text("Acrylic Blur")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(opacity >= 0.999)
            .help("Blur requires opacity below 100%.")
            .onChange(of: blurEnabled) { newValue in
                ghostty.setBackgroundBlurEnabled(newValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: opacity) { _ in
            scheduleApply()
        }
        .onChange(of: config.backgroundOpacity) { newValue in
            if abs(newValue - opacity) > 0.005 {
                opacity = newValue
            }
        }
        .onChange(of: config.backgroundBlur) { newValue in
            let enabled = newValue.isEnabled
            if enabled != blurEnabled {
                blurEnabled = enabled
            }
        }
        .onDisappear {
            applyWorkItem?.cancel()
        }
    }

    private func scheduleApply() {
        guard abs(opacity - config.backgroundOpacity) > 0.005 else { return }

        applyWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            applyOpacity()
        }
        applyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func applyOpacity() {
        let value = min(max(opacity, 0), 1)
        guard abs(value - config.backgroundOpacity) > 0.005 else { return }
        ghostty.setBackgroundOpacity(value)
    }
}
