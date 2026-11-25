//
//  NewDeviceSheet.swift
//  Q2-Sync › Views
//
//  PURPOSE
//  The "Is this your Shanling Q2?" sheet shown the first time an eligible
//  drive connects. The user confirms it's their Q2, picks its firmware
//  (neither is preselected), and then grants write access in an Open panel.
//
//  HOW IT FITS
//  Presented by `RootView` whenever `DeviceMonitor.pendingVolume` is set.
//
//  WHY ASK AT ALL
//  A different card or USB stick must never be mistaken for the Q2. Only a
//  drive the user explicitly confirms (remembered by its UUID) is synced.
//
//  CARD FORMAT
//  A card that isn't one volume on Master Boot Record (e.g. a reused
//  Raspberry Pi card: a small boot partition plus a Linux one) is warned
//  about here, where the user decides, with the Disk Utility steps; Later
//  becomes the default button. Continuing is still allowed.
//

import SwiftUI

/// Asks whether a newly connected drive is the user's Q2.
struct NewDeviceSheet: View {

    let volume: VolumeInfo
    let devices: DeviceMonitor

    /// The firmware the user selects. Nothing is preselected: a wrong
    /// guess would name the wrong menus on the Q2 and check the wrong
    /// firmware, so Continue waits for a choice.
    @State private var firmware: FirmwareKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "ipod")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Is this your Shanling Q2?")
                        .font(.title2.bold())
                    Text(volumeDescription)
                        .foregroundStyle(.secondary)
                }
            }

            Label(connectionNote, systemImage: connection == .q2 ? "cable.connector" : "sdcard")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if let advice = formatAdvice {
                formatWarning(advice)
            }

            Text("Q2 Sync will only ever write to a card you confirm here. It remembers this card by its unique ID, so other drives are never mistaken for it.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Picker("Firmware on this Q2:", selection: $firmware) {
                    // Stock first: it’s what the Q2 ships with. The tags are
                    // optional to match the selection, which starts empty.
                    ForEach([FirmwareKind.stock, .q2Pod]) { kind in
                        Text(kind.displayName).tag(Optional(kind))
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Not sure? Q2 Pod looks like an iPod; stock is Shanling’s own look.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Next, macOS will show this card in an Open window. Click Grant Access to let Q2 Sync change files on this card only.",
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Not My Q2") { devices.markNotQ2(volume) }
                    .help("Never ask about this drive again")
                Spacer()
                // With a format warning, Return means Later, so a card that
                // probably needs erasing isn't approved by reflex.
                if formatAdvice == nil {
                    Button("Later") { devices.postpone(volume) }
                        .keyboardShortcut(.cancelAction)
                    Button("Continue…") { confirm() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(firmware == nil)
                } else {
                    Button("Continue Anyway…") { confirm() }
                        .disabled(firmware == nil)
                    Button("Later") { devices.postpone(volume) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Sets the drive up with the chosen firmware.
    private func confirm() {
        guard let firmware else { return }
        devices.confirm(volume, firmware: firmware)
    }

    /// Whether the Disk Utility steps are shown.
    @State private var showsSteps = false

    /// Advice if the card's layout is wrong for the Q2.
    private var formatAdvice: CardFormatAdvice? { devices.formatAdvice(for: volume) }

    /// The format warning, with the Disk Utility steps behind a disclosure.
    private func formatWarning(_ advice: CardFormatAdvice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(advice.problem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text("Erase it in Disk Utility before using it with the Q2. Q2 Sync never erases or formats a card.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("How to Erase It", isExpanded: $showsSteps) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(CardFormatAdvice.diskUtilitySteps.enumerated()), id: \.offset) { index, step in
                        Label(step, systemImage: "\(index + 1).circle")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Open Disk Utility") { CardFormatAdviceSection.openDiskUtility() }
                }
                .font(.callout)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// How the drive is connected.
    private var connection: CardConnection { devices.connection(for: volume) }

    /// Explains what the connection suggests.
    private var connectionNote: String {
        switch connection {
        case .q2: return "This drive looks like a Shanling Q2 connected by USB."
        case .otherDrive: return "This drive is in a card reader or is another kind of drive, not a Q2 on a USB cable. That's fine if it's your Q2's card."
        case .unknown: return "Q2 Sync couldn't tell how this drive is connected."
        }
    }

    /// e.g. "“Q2CARD” · 256 GB · ExFAT".
    private var volumeDescription: String {
        let size = volume.totalCapacity.map { $0.formatted(ByteCountFormatStyle(style: .file)) }
        return ["“\(volume.name)”", size, volume.formatDescription]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

#Preview {
    NewDeviceSheet(
        volume: VolumeInfo(url: URL(filePath: "/Volumes/Q2CARD"), uuid: "X", name: "Q2CARD",
                           isRemovable: true, isEjectable: true, isInternal: false,
                           isRootFileSystem: false, formatDescription: "ExFAT",
                           totalCapacity: 256_000_000_000, availableCapacity: 255_000_000_000),
        devices: DeviceMonitor())
}
