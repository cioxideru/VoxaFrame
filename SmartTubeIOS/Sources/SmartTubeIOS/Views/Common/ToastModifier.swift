import SmartTubeIOSCore
import SwiftUI

// MARK: - ToastModifier
//
// A lightweight, self-dismissing message pill that floats near the bottom of
// any view.  Designed to be applied once at an appropriate ancestor — the
// modifier owns the show/hide lifecycle so callers only need to write a value.
//
// Usage:
//   .toast(message: $someStringBinding)
//
// The binding is set to nil automatically after 3 seconds so callers never
// have to schedule their own dismissal.
//
// Cards and other short-lived views call `@Environment(\.showToast)` instead: the single
// `toastPresenter()` at the root shows it, so the toast is neither clipped by a small card
// nor removed with a card that the action itself takes away.

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var dismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                toastPill
            }
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard let newValue else { return }
                // The pill is not focusable and leaves on its own, so VoiceOver hears it here.
                AccessibilityNotification.Announcement(newValue).post()
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    message = nil
                }
            }
    }

    @ViewBuilder
    private var toastPill: some View {
        if let text = message {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(.horizontal, VFSpace.s16)
                .padding(.bottom, 32)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                .accessibilityIdentifier(AccessibilityID.playerToast)
        }
    }
}

extension View {
    /// Displays a self-dismissing toast pill when `message` is non-nil.
    /// The binding is automatically cleared after 3 seconds.
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }

    /// The app's one toast for views that use `@Environment(\.showToast)`; applied once at the root.
    func toastPresenter() -> some View {
        modifier(ToastPresenter())
    }
}

/// Shows `message` in the nearest `toastPresenter()`; does nothing without one.
struct ShowToastAction: Sendable {
    fileprivate let show: @MainActor @Sendable (String) -> Void

    @MainActor func callAsFunction(_ message: String) { show(message) }
}

extension EnvironmentValues {
    @Entry var showToast = ShowToastAction { _ in }
}

private struct ToastPresenter: ViewModifier {
    @State private var message: String?

    func body(content: Content) -> some View {
        let binding = $message
        content
            .environment(\.showToast, ShowToastAction { binding.wrappedValue = $0 })
            .toast(message: binding)
    }
}
