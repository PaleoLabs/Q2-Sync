//
//  ConnectQ2View.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Connect Your Q2" page: shown from the sidebar's Devices section
//  while no Q2 is connected (and selected on first launch), so a new user
//  knows what to do before the Q2 is plugged in.
//
//  HOW IT FITS
//  `RootView` lists it as the Devices row whenever `DeviceMonitor.connected`
//  is `nil`. When a Q2 connects, the sidebar switches to it.
//

import SwiftUI

/// How to connect the Q2, and what happens next.
struct ConnectQ2View: View {

    /// `true` once a Q2 has been set up on this Mac (changes the wording).
    let hasSetUpBefore: Bool

    /// Names of connected drives waiting in the sidebar with "Set Up…"
    /// (card readers and other drives don't pop up the setup sheet).
    var waitingDrives: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "ipod")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hasSetUpBefore ? "Connect Your Q2" : "Welcome to Q2 Sync")
                            .font(.title.bold())
                        Text(hasSetUpBefore ? "Your Q2 isn't connected right now."
                                            : "Let's connect your Shanling Q2.")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Turn on your Q2.")
                    step(2, "Swipe down from the top of its screen to open the quick-access menu.")
                    step(3, "Set the USB switch to USB Storage (not USB Audio or USB DAC).")
                    step(4, "Connect the Q2 to your Mac with its USB-C cable.")
                }

                if !waitingDrives.isEmpty {
                    Label("Connected: \(waitingDrives.map { "“\($0)”" }.joined(separator: ", ")). If that's your Q2's card, click Set Up… next to it in the sidebar.",
                          systemImage: "externaldrive.badge.questionmark")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("You can also put the Q2's microSD card in a card reader. Only take the card out while the Q2 is fully shut down.",
                      systemImage: "sdcard")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !hasSetUpBefore {
                    Divider()
                    Text("What happens next").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Q2 Sync asks “Is this your Shanling Q2?” and which firmware it runs.")
                        Text("• macOS asks you to grant access to the card, once.")
                        Text("• You choose your music: your entire library, or the artists, albums, genres and playlists you tick.")
                        Text("• You review every change, then click Sync.")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Meanwhile, browse your Music library in the sidebar.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Label(text, systemImage: "\(number).circle.fill")
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    ConnectQ2View(hasSetUpBefore: false)
}
