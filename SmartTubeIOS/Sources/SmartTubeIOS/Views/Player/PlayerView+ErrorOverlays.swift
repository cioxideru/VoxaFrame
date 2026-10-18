import SmartTubeIOSCore
import SwiftUI

// MARK: - Slide transition + toast/error (PlayerView extension)

extension PlayerView {

    // MARK: - Slide transition

    /// Animates the current content off-screen in `direction` (-1 = left, +1 = right),
    /// runs `action` to load the next/previous video, then slides the new content in
    /// from the opposite side.
    func performHorizontalTransition(direction: CGFloat, screenWidth: CGFloat, action: @escaping () -> Void) {
        // Set the re-entry guard synchronously so any concurrent gesture event
        // arriving before the Task runs still sees isTransitioning == true.
        isTransitioning = true
        // Defer ALL SwiftUI state mutations (incl. the initial slide-out animation)
        // into the async Task so none of them execute synchronously inside UIKit's
        // touch-event delivery pass. On iOS 26 the UpdateCycle framework throws when
        // @Observable/@State mutations happen synchronously during event dispatch.
        Task { @MainActor in
            withAnimation(.easeIn(duration: 0.2)) {
                slideOffset = direction * screenWidth
            }
            try? await Task.sleep(for: .milliseconds(220))
            action()  // load new video, clears AVPlayer
            slideOffset = -direction * screenWidth  // snap to opposite side (off-screen)
            withAnimation(.easeOut(duration: 0.25)) {
                slideOffset = 0  // slide new content in
            }
            try? await Task.sleep(for: .milliseconds(270))
            isTransitioning = false
        }
    }

    // MARK: - Toast / error

    var sponsorSkipToast: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let seg = vm.currentToastSegment {
                    Button("Skip \(seg.category.displayName)") {
                        vm.skipToastSegment()
                    }
                    // System style on purpose: the fill is the segment colour, not the accent `.vfProminent` pairs with.
                    .buttonStyle(.borderedProminent)
                    .tint(seg.category.color)
                    #if os(tvOS)
                    // When the skip-toast button is focused, D-pad left/right must still
                    // seek. Without this modifier the move event is consumed by the button
                    // and the ConditionalMoveCommand on the player body never fires
                    // (it is intentionally disabled while the toast is active so that the
                    // focus engine can see the button). Adding onMoveCommand here gives
                    // the button a way to pass the direction through to seeking.
                    .onMoveCommand { direction in
                        switch direction {
                        case .left: vm.seekRelative(seconds: -Double(store.settings.seekBackSeconds))
                        case .right: vm.seekRelative(seconds: Double(store.settings.seekForwardSeconds))
                        default: break
                        }
                    }
                    .focused($skipToastButtonFocused)
                    #endif
                    .padding()
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeInOut, value: vm.currentToastSegment?.id)
    }

    // Returns true when the error is an IP/VPN block (APIError.ipBlocked).
    // Extracted to a separate function so the Swift type-checker does not have to
    // resolve a closure-in-body pattern while simultaneously inferring `some View`.
    private func isIPBlockError(_ err: Error) -> Bool {
        if let apiError = err as? APIError, case .ipBlocked = apiError { return true }
        return false
    }

    // Returns true when the error requires the user to sign in (APIError.signInRequired).
    // Retrying is futile — show a "Sign In" button instead of "Try Again".
    private func isSignInRequiredError(_ err: Error) -> Bool {
        if let apiError = err as? APIError, case .signInRequired = apiError { return true }
        return false
    }

    @ViewBuilder
    func errorBanner(_ err: Error) -> some View {
        // IP-block errors show a specific message and no retry button — retrying
        // with the same IP will also fail and may extend the YouTube block duration.
        // A video error is about this video only: it never signs the user out (P-Player-States).
        let isIPBlock = isIPBlockError(err)
        let isSignInRequired = isSignInRequiredError(err)
        VStack(spacing: VFSpace.s12) {
            // The symbol and the text carry the state; colour is not needed to read it.
            Image(systemName: AppSymbol.warning)
                .font(.title2)
                .accessibilityHidden(true)
            Text(err.localizedDescription)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
            if !isIPBlock && !isSignInRequired {
                PlayerMediaActionButton(title: Text("Try Again")) { vm.retryLoad() }
                    // Its own width, as the Shorts Retry: the card's measuring otherwise truncates the label.
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.playerRetryButton)
            }
            if isSignInRequired {
                SignInButtonView()
            }
        }
        .foregroundStyle(VFColor.onMedia)
        .padding(VFSpace.s20)
        .frame(maxWidth: 420)
        .vfGlass(in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding()
        .accessibilityIdentifier(isIPBlock ? "player.ipBlockBanner" : "player.errorBanner")
    }
}

// MARK: - Sign-in button (age-restricted / login-required errors)
//
// Isolated into its own view so the @State sheet-presentation flag lives in a
// dedicated scope.  PlayerControlsOverlay cannot hold its own mutable @State in
// the extension methods where this is used, so we delegate to this tiny helper.
private struct SignInButtonView: View {
    @State private var showSignIn = false

    var body: some View {
        PlayerMediaActionButton(title: Text("Sign In")) { showSignIn = true }
            .fixedSize()
            .accessibilityIdentifier(AccessibilityID.playerSignInButton)
            .sheet(isPresented: $showSignIn) { SignInView() }
    }
}
