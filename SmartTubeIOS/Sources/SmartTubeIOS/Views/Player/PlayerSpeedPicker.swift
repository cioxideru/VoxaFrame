import SmartTubeIOSCore
import SwiftUI

/// Shared controls with separate persisted choices for regular videos and Shorts.
struct PlayerSpeedPicker: View {
    let vm: PlaybackViewModel
    @Binding var showSpeedPicker: Bool
    var maxWidth: CGFloat = .infinity
    @Environment(SettingsStore.self) private var store
    #if os(tvOS)
    @Namespace private var speedPickerNamespace
    @FocusState private var speedPickerFocused: Bool
    #endif

    var body: some View {
        let speedKey = vm.isShortsPlayer ? \AppSettings.shortsPlaybackSpeed : \.playbackSpeed
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showSpeedPicker = false }
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { showSpeedPicker = false }
                        #if os(tvOS)
                    .buttonStyle(PickerHeaderButtonStyle())
                        #endif
                        .padding()
                    Spacer()
                    Text("Playback Speed")
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 70, height: 44)
                }
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                            let selected = abs(store.settings[keyPath: speedKey] - speed) < 0.01
                            Button {
                                store.settings[keyPath: speedKey] = speed
                                vm.setPlaybackSpeed(speed)
                                showSpeedPicker = false
                            } label: {
                                HStack {
                                    Text(
                                        speed == 1
                                            ? "Normal (1×)"
                                            : "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
                                    )
                                    .foregroundStyle(.primary)
                                    Spacer()
                                    if selected {
                                        Image(systemName: AppSymbol.checkmark)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityID.playerSpeed(speed))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
                #if os(tvOS)
                .prefersDefaultFocus(in: speedPickerNamespace)
                .focused($speedPickerFocused)
                #endif
            }
            .frame(maxWidth: maxWidth)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier(AccessibilityID.playerSpeedPicker)
            #if os(tvOS)
            .focusScope(speedPickerNamespace)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                speedPickerFocused = true
            }
            .onExitCommand { showSpeedPicker = false }
            #endif
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
    }
}
