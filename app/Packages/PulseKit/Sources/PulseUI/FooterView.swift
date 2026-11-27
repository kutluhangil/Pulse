import PulseCore
import SwiftUI

struct FooterView: View {
    let snapshot: Snapshot
    let prefs: Preferences
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                IconButton(icon: "gearshape", help: L("Settings"), action: actions.openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                IconButton(icon: "power", help: L("Quit Pulse"), action: actions.quit)
                Spacer()
                if let ssh = prefs.resolvedSSH {
                    FooterButton(icon: "terminal", title: "SSH") { actions.open(ssh) }
                }
                if let p = prefs.resolvedPortainer {
                    FooterButton(icon: "shippingbox", title: "Portainer") { actions.open(p) }
                }
                if let c = prefs.resolvedCockpit {
                    IconButton(icon: "gauge.with.dots.needle.33percent", help: "Cockpit") { actions.open(c) }
                }
            }
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 2)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            HStack(alignment: .top) {
                Stat(value: "\(snapshot.runningCount)", label: L("Containers"),
                     level: snapshot.failingContainers.isEmpty ? nil : .critical)
                Stat(value: "\(snapshot.system.aptUpdates)", label: L("Updates"),
                     level: snapshot.system.securityUpdates > 0 ? .warn : nil)
                    .help(L("\(snapshot.system.securityUpdates) security"))
                Stat(value: "\(snapshot.attentionCount)", label: L("Alerts"),
                     level: snapshot.attentionCount > 0 ? .critical : nil)
                    .help(snapshot.system.rebootRequired ? L("Restart required") : "")
            }
        }
        .padding(.horizontal, Theme.tilePadding)
        .padding(.vertical, 10)
        .background(Theme.tileFill, in: .rect(cornerRadius: Theme.tileRadius, style: .continuous))
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12.5, weight: .regular)).contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct FooterButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .regular))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }
}

struct Stat: View {
    let value: String
    let label: String
    var level: Level?

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .bold).monospacedDigit())
                .foregroundStyle(level.map(Theme.color) ?? .primary)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let monitor: Monitor
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.good)
                .symbolEffect(.pulse, isActive: monitor.connection == .connecting)
            switch monitor.connection {
            case .notConfigured:
                Text(L("Connect Pulse to your server")).font(.system(size: 16, weight: .semibold))
                Text(L("Enter the agent address and token. Run ./deploy/deploy.sh --copy-token on your Mac to copy the token."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("Open Settings"), action: actions.openSettings).buttonStyle(.glassProminent)
            case .connecting, .live:
                Text(L("Connecting…")).font(.system(size: 16, weight: .semibold))
                ProgressView().controlSize(.small)
            case .unauthorized:
                Text(L("The agent rejected the token")).font(.system(size: 16, weight: .semibold))
                Button(L("Open Settings"), action: actions.openSettings).buttonStyle(.glassProminent)
            case .offline(let reason):
                Text(L("Server unreachable")).font(.system(size: 16, weight: .semibold))
                Text(reason).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button(L("Retry")) { monitor.reconnect() }.buttonStyle(.glass)
                    Button(L("Open Settings"), action: actions.openSettings).buttonStyle(.glass)
                }
            }
            HStack {
                Spacer()
                Button(L("Quit Pulse"), action: actions.quit).buttonStyle(.borderless).font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
