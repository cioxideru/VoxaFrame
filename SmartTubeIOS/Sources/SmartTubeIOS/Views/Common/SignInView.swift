import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - SignInView
//
// Google Device Authorization Grant sign-in UI (mirrors Android's equivalent).
// No browser redirect — the user enters a short code at youtube.com/activate.

public struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showError = false

    public init() {}

    public var body: some View {
        #if os(tvOS)
        tvBody
        #else
        NavigationStack {
            Group {
                if let info = auth.pendingActivation {
                    activationView(info: info)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Sign In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        auth.cancelSignIn()
                        dismiss()
                    }
                }
            }
            .alert("Sign-In Failed", isPresented: $showError, presenting: auth.error) { _ in
                Button("Try Again") { Task { await auth.beginSignIn() } }
                Button("Cancel", role: .cancel) { auth.error = nil }
            } message: { err in
                Text(err.localizedDescription)
            }
            .onChange(of: auth.error == nil ? 0 : 1) { _, hasError in
                if hasError == 1 { showError = true }
            }
        }
        .task {
            await auth.beginSignIn()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        #endif
    }

    #if os(tvOS)
    /// Full-screen tvOS sign-in layout — two-column, 10-foot-UI friendly.
    private var tvBody: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.85).ignoresSafeArea()

            if let info = auth.pendingActivation {
                tvActivationView(info: info)
            } else {
                tvLoadingView
            }

            Button {
                auth.cancelSignIn()
                dismiss()
            } label: {
                Label("Cancel", systemImage: "xmark")
                    .font(.headline)
            }
            .padding(40)
        }
        .alert("Sign-In Failed", isPresented: $showError, presenting: auth.error) { _ in
            Button("Try Again") { Task { await auth.beginSignIn() } }
            Button("Cancel", role: .cancel) { auth.error = nil }
        } message: { err in
            Text(err.localizedDescription)
        }
        .onChange(of: auth.error == nil ? 0 : 1) { _, hasError in
            if hasError == 1 { showError = true }
        }
        .task { await auth.beginSignIn() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var tvLoadingView: some View {
        VStack(spacing: 24) {
            ProgressView().controlSize(.large)
            Text("Connecting to Google…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tvActivationView(info: AuthService.ActivationInfo) -> some View {
        HStack(alignment: .center, spacing: 80) {
            // Left column: instructions + code + countdown
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign in to VoxaFrame")
                        .font(.largeTitle).fontWeight(.bold)

                    Text("On any device, open the link below and enter the code.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Go to:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(verbatim: displayAddress(info.verificationURL))  // verbatim: web address
                        .font(.title3).fontWeight(.semibold)
                }

                Text(verbatim: info.userCode)  // verbatim: activation code
                    // The title style (57 pt on Apple TV) scales with the text size, and the padded plate grows.
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .tracking(10)
                    .speechSpellsOutCharacters()
                    .padding(.vertical, VFSpace.s20)
                    .padding(.horizontal, VFSpace.s32)
                    .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))

                CountdownView(expiresAt: info.expiresAt) {
                    Task { await auth.beginSignIn() }
                }

                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for authorisation…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: QR code
            VStack(spacing: 16) {
                QRCodeView(content: activationQRURL(info: info))
                    .frame(width: 280, height: 280)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("Scan to open activation page")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - Loading screen

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to Google…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Activation code screen

    /// Builds the URL that Google accepts to auto-fill the user code:
    /// https://www.google.com/device?user_code=XXXX-XXXX
    private func activationQRURL(info: AuthService.ActivationInfo) -> String {
        guard var components = URLComponents(url: info.verificationURL, resolvingAgainstBaseURL: false) else {
            return info.verificationURL.absoluteString
        }
        let existing = components.queryItems ?? []
        components.queryItems = existing + [URLQueryItem(name: "user_code", value: info.userCode)]
        return components.url?.absoluteString ?? info.verificationURL.absoluteString
    }

    #if os(macOS)
    /// Opens the activation URL in the system default browser.
    ///
    /// `ASWebAuthenticationSession` was tried here but crashes reliably on macOS
    /// when the user closes Safari: the SafariLaunchAgent XPC teardown fires on a
    /// non-main thread and AppKit's sheet dismissal path calls `dispatch_assert_queue`
    /// against the main queue → `_dispatch_assert_queue_fail`.  Since Device
    /// Authorization Grant never needs a redirect callback, a plain browser open is
    /// both simpler and crash-free.
    @MainActor
    private func openActivationPageMac(info: AuthService.ActivationInfo) {
        guard let url = URL(string: activationQRURL(info: info)) else { return }
        NSWorkspace.shared.open(url)
    }
    #endif

    /// Code first, then the two ways to use it (this device, or the QR from another one), then the wait.
    private func activationView(info: AuthService.ActivationInfo) -> some View {
        ScrollView {
            VStack(spacing: VFSpace.s24) {
                VStack(spacing: VFSpace.s8) {
                    Text("Sign in to VoxaFrame", bundle: .module)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("On any device, open the link below and enter the code.", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: displayAddress(info.verificationURL))  // verbatim: web address
                        .font(.headline)
                }
                .multilineTextAlignment(.center)

                Text(verbatim: info.userCode)  // verbatim: activation code
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .tracking(VFSpace.s4)
                    .speechSpellsOutCharacters()
                    .padding(.vertical, VFSpace.s16)
                    .padding(.horizontal, VFSpace.s24)
                    .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))

                ViewThatFits {
                    HStack(spacing: VFSpace.s12) { codeActions(info: info) }
                    VStack(spacing: VFSpace.s12) { codeActions(info: info) }
                }

                VStack(spacing: VFSpace.s8) {
                    // Scanned from another device; opens the page with the code filled in.
                    QRCodeView(content: activationQRURL(info: info))
                        .frame(width: 180, height: 180)
                        .padding(VFSpace.s8)
                        .background(.white, in: RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
                        .accessibilityLabel(Text("Scan to open activation page", bundle: .module))
                    Text("Scan to open activation page", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                VStack(spacing: VFSpace.s8) {
                    HStack(spacing: VFSpace.s8) {
                        ProgressView()
                        Text("Waiting for authorisation…", bundle: .module)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    CountdownView(expiresAt: info.expiresAt) {
                        // Code expired: a new one replaces it.
                        Task { await auth.beginSignIn() }
                    }
                }
                .accessibilityElement(children: .combine)

                Button(role: .cancel) {
                    auth.cancelSignIn()
                } label: {
                    Text("Use a different account", bundle: .module)
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(VFSpace.s16)
        }
    }

    @ViewBuilder
    private func codeActions(info: AuthService.ActivationInfo) -> some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = info.userCode
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(info.userCode, forType: .string)
            #endif
        } label: {
            Label {
                Text("Copy Code", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.copyDoc)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        // Opens the activation page with the code already filled in.
        Button {
            #if os(macOS)
            openActivationPageMac(info: info)
            #else
            openURL(URL(string: activationQRURL(info: info)) ?? info.verificationURL)
            #endif
        } label: {
            Label {
                Text("Open Activation Page", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.openExternal)
            }
        }
        .buttonStyle(.vfProminent)
        .controlSize(.large)
    }

    /// `google.com/device` rather than the full https URL.
    private func displayAddress(_ url: URL) -> String {
        let host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        return host + url.path
    }
}

// MARK: - QRCodeView

struct QRCodeView: View {
    let content: String

    var body: some View {
        if let img = makeQRImage() {
            GeometryReader { geo in
                img
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        } else {
            Image(systemName: AppSymbol.qrcode)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private func makeQRImage() -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.correctionLevel = "M"
        guard let data = content.data(using: .utf8) else { return nil }
        filter.message = data

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up so the QR is crisp at any display size
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = ciImage.transformed(by: scale)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        return Image(nsImage: nsImage)
        #else
        let uiImage = UIImage(cgImage: cgImage)
        return Image(uiImage: uiImage)
        #endif
    }
}

// MARK: - CountdownView

private struct CountdownView: View {
    let expiresAt: Date
    let onExpired: () -> Void

    @State private var remaining: TimeInterval = 0

    var body: some View {
        Group {
            if remaining > 0 {
                Label(timeString, systemImage: AppSymbol.clock)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text("Code expired", bundle: .module)
                } icon: {
                    Image(systemName: AppSymbol.warning)
                }
                .font(.caption)
                .foregroundStyle(VFColor.danger)
            }
        }
        .task {
            remaining = max(0, expiresAt.timeIntervalSinceNow)
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining = max(0, expiresAt.timeIntervalSinceNow)
            }
            // Give an in-flight poll (e.g. fired by handleForeground on app return)
            // a few seconds to complete before creating a new device code.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            onExpired()
        }
    }

    private var timeString: String {
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        let fmt = String(localized: "Code expires in %d:%02d", bundle: .module)
        return String(format: fmt, mins, secs)
    }
}
