import AppKit
import PulseCore
import SwiftUI

struct ContainersSection: View {
    let snapshot: Snapshot
    let prefs: Preferences
    let actions: PanelActions
    @State private var expanded = false

    private static let collapsedCount = 5

    var body: some View {
        let all = snapshot.sortedContainers
        let shown = expanded ? all : Array(all.prefix(Self.collapsedCount))
        Section {
            HStack {
                Text(L("Containers"))
                Spacer()
                Text(L("Memory")).frame(width: 62, alignment: .trailing)
                Text("% CPU").frame(width: 48, alignment: .trailing).foregroundStyle(.primary)
                Color.clear.frame(width: 18)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)

            if !snapshot.docker.available {
                Text(snapshot.docker.error.map { L("Docker unreachable: \($0)") } ?? L("Docker monitoring is off"))
                    .font(Theme.caption).foregroundStyle(Theme.warn)
                    .padding(.vertical, 4)
            } else if all.isEmpty {
                Text(L("No containers")).font(Theme.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            }

            ForEach(shown) { c in
                ContainerRow(container: c, prefs: prefs, actions: actions)
            }

            HStack {
                let stopped = snapshot.containers.count - snapshot.runningCount
                Text(L("\(snapshot.runningCount) running · \(stopped) stopped"))
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.primary.opacity(0.8))
                Spacer()
                if all.count > Self.collapsedCount {
                    Button(expanded ? L("Show less") : L("Show all")) {
                        withAnimation(.snappy) { expanded.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.good)
                }
            }
            .padding(.top, 4)
        }
    }
}

struct ContainerRow: View {
    let container: Snapshot.Container
    let prefs: Preferences
    let actions: PanelActions
    @State private var hovering = false

    var body: some View {
        let status = ContainerStatus(container)
        HStack(spacing: 7) {
            StatusDot(level: status.level, size: 5)
            HStack(spacing: 5) {
                Text(displayName(container))
                    .font(Theme.row)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !container.project.isEmpty, displayName(container) != container.project {
                    Text(container.project)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(container.state == "running" ? Format.bytes(container.memBytes).text : stateText(status))
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(container.state == "running" ? Color.primary.opacity(0.85) : Theme.color(status.level))
            Text(container.state == "running" ? Format.cpuPercentPrecise(container.cpu) : "–")
                .frame(width: 48, alignment: .trailing)
                .foregroundStyle(cpuColor)
            Menu {
                Button(L("Show logs")) { actions.showLogs(container) }
                Button(L("Copy name")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(container.name, forType: .string)
                }
                if let portainer = prefs.resolvedPortainer {
                    Button(L("Open Portainer")) { actions.open(portainer) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: 18)
        }
        .font(Theme.rowValue)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hovering ? Color.white.opacity(0.05) : .clear, in: .rect(cornerRadius: 8))
        .padding(.horizontal, -6)
        .onHover { hovering = $0 }
        .contentShape(.rect)
        .onTapGesture(count: 2) { actions.showLogs(container) }
        .help(helpText(status))
    }

    private var cpuColor: Color {
        switch container.cpu {
        case 50...: Theme.critical
        case 20...: Theme.warn
        default: Color.primary.opacity(0.85)
        }
    }

    private func stateText(_ s: ContainerStatus) -> String {
        switch s {
        case .failing: container.state == "exited" ? L("exit \(container.exitCode)") : container.state
        case .stopped: L("stopped")
        default: container.state
        }
    }

    private func helpText(_ s: ContainerStatus) -> String {
        var lines = [container.name, container.image, container.statusText]
        if container.restartCount > 0 { lines.append(L("Restarted \(container.restartCount) times")) }
        if container.memLimit > 0, container.memLimit < (1 << 50) {
            lines.append(L("Memory limit \(Format.bytes(container.memLimit).text)"))
        }
        return lines.joined(separator: "\n")
    }
}
