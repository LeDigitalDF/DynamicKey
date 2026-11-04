// AppLifecycleController.swift
// Bridges NSApplication lifecycle events to the local auth service (M5).
//
// Flow: app finishes launching → activate window → start server; app terminates → stop server.

import AppKit

final class AppLifecycleController: NSObject, NSApplicationDelegate {
    /// Starts services and brings the main window forward when the app is ready.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        Task { @MainActor in
            LaunchAtLoginService.shared.reconcileStoredPreference(
                AppPreferencesStore.shared.launchAtLoginEnabled
            )
            LocalAuthServiceManager.shared.start()

            let credentials = CredentialStore.shared.credentials()
            LeakPeekStore.shared.syncCredentialList(credentials)
            await LeakPeekStore.shared.runWeeklyScanIfNeeded(credentials: credentials)

            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Stops the extension auth service before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            LocalAuthServiceManager.shared.stop()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
    }
}
