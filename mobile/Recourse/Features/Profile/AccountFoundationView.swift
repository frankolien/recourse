import SwiftUI

struct AccountFoundationView: View {
    let configuration: AppConfiguration

    var body: some View {
        List {
            Section("Network") {
                LabeledContent("Chain", value: configuration.chainName)
                LabeledContent("Chain ID", value: String(configuration.chainID))
            }

            Section("Deployment") {
                LabeledContent("Escrow", value: configuration.escrowAddress.shortened)
                LabeledContent("USDC", value: configuration.usdcAddress.shortened)
            }

            Section {
                Text("A testnet account will be created on-device in the signing slice. No production funds are supported.")
                    .font(.footnote)
                    .foregroundStyle(RecourseColor.muted)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
