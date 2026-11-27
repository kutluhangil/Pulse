import AppKit
import PulseClient
import PulseCore
import SwiftUI

/// Read-only tail of a container's logs.
public struct LogsView: View {
    let client: AgentClient
    let container: Snapshot.Container

    @State private var text = ""
    @State private var error: String?
    @State private var loading = false
    @State private var tail = 200

    public init(client: AgentClient, container: Snapshot.Container) {
        self.client = client
        self.container = container
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StatusDot(level: ContainerStatus(container).level)
                VStack(alignment: .leading, spacing: 1) {
                    Text(container.name).font(.headline)
                    Text(container.image).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(L("Lines"), selection: $tail) {
                    ForEach([100, 200, 500], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help(L("Reload"))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help(L("Copy all"))
            }
            .padding(12)
            Divider()
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        Text(text.isEmpty && !loading ? L("No log output") : text)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .onChange(of: text) { proxy.scrollTo("end", anchor: .bottom) }
                }
                if loading { ProgressView().controlSize(.small) }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .task(id: tail) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            text = try await client.logs(containerID: container.id, tail: tail)
            error = nil
        } catch {
            self.error = Monitor.describe(error)
        }
    }
}
