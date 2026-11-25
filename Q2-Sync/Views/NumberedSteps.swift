//
//  NumberedSteps.swift
//  Q2-Sync
//
//  PURPOSE
//  A numbered list of instructions, one blue circled number per step.
//
//  HOW IT FITS
//  Used by the Sync Complete window and the Install Firmware window, so
//  "what to do next on your Q2" looks the same in both.
//

import SwiftUI

/// Instructions numbered from 1.
struct NumberedSteps: View {

    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Label {
                    Text(step).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "\(index + 1).circle.fill").foregroundStyle(.tint)
                }
            }
        }
    }
}
