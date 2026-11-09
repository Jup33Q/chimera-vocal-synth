import SwiftUI

struct PhaseShellView: View {
    let title: String
    let port: Int
    let message: String
    let engineStatus: String

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .light, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Phosphor.blue)
                Spacer()
                Text("MCP 127.0.0.1:\(port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Phosphor.blue)
                    .textSelection(.enabled)
            }
            Screen(title: "P0 APPLICATION SHELL", subtitle: "LATER-PHASE WORKFLOW") {
                VStack(alignment: .leading, spacing: 18) {
                    Spacer()
                    Text(message)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Phosphor.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This independent target shares the native engine and loopback MCP infrastructure. Its full workflow is intentionally outside P0.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text(engineStatus)
                Spacer()
                Text("STATUS / STOP AVAILABLE OVER MCP")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Phosphor.green)
        }
        .padding(18)
        .background(Color.black)
    }
}
