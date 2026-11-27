import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, server, menuBar, alerts, about
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("General")
        case .server: L("Server")
        case .menuBar: L("Menu Bar")
        case .alerts: L("Alerts")
        case .about: L("About")
        }
    }
}

public extension Notification.Name {
    /// Posted with a `SettingsTab` object to switch the open settings window.
    static let pulseSelectSettingsTab = Notification.Name("pulseSelectSettingsTab")
}

/// Capsule tab bar: the selected tab is a white pill with dark text.
struct PillTabs: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.black : Color.primary.opacity(0.85))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background {
                            if selection == tab { Capsule().fill(.white) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.09), in: .capsule)
    }
}

/// One settings row: title and explanation on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 11)
    }
}

/// Thin separator between rows.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}

/// Mole-style pop-up: current value with an up/down chevron in a dark capsule.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, title in
                Button {
                    selection = value
                } label: {
                    if value == selection { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(options.first { $0.0 == selection }?.1 ?? "")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.10), in: .capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Green-tinted switch, like Mole's toggles.
struct GreenToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Color(red: 0.36, green: 0.72, blue: 0.55))
            .labelsHidden()
            .controlSize(.small)
    }
}

/// Small capsule action button with green text ("Manage", "Test").
struct PillButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary : Color(red: 0.45, green: 0.85, blue: 0.62))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.10), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// "✓ Granted" style status text.
struct StatusBadge: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ok ? Color(red: 0.45, green: 0.85, blue: 0.62) : Theme.warn)
    }
}

/// Inline text field on the right side of a row.
struct RowField: View {
    @Binding var text: String
    var prompt: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(prompt))
            } else {
                TextField("", text: $text, prompt: Text(prompt))
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 8))
        .frame(width: 250)
        .autocorrectionDisabled()
    }
}
