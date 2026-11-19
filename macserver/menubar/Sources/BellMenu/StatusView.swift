import SwiftUI

struct StatusView: View {
    let monitor: ServerMonitor

    private var summary: String {
        if !monitor.hasChecked { return "Checking servers..." }
        if monitor.pending == true { return "Starting servers..." }
        if monitor.pending == false { return "Stopping servers..." }
        if !monitor.anyUp { return "Servers stopped" }
        let down = monitor.downCount
        return down == 0 ? "All servers running" : "\(down) of \(monitor.visible.count) servers down"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle()
                    .fill(monitor.hasChecked && monitor.downCount == 0 ? green : .yellow)
                    .frame(width: 6, height: 6)
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(secondary)
            }

            VStack(spacing: 10) {
                ForEach(monitor.visible) { server in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(server.isUp ? green : .yellow)
                            .frame(width: 6, height: 6)
                        Text(server.name)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: server.isUp ? "Port \(server.port)" : "Not responding")
                            .font(.caption2)
                            .foregroundStyle(secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(server.name) \(server.isUp ? "running" : "not responding")")
                }
            }

            Spacer(minLength: 0)

            if monitor.canControl {
                Button(monitor.pending != nil ? "Please wait..." : monitor.anyUp ? "Stop servers" : "Start servers") {
                    monitor.toggle()
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(buttonBackground, in: Capsule())
                .disabled(monitor.pending != nil)
            }
        }
    }
}
