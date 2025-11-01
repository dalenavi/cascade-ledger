//
//  CLIMonitorView.swift
//  cascade-ledger
//
//  GUI view that shows CLI activity and enables interaction
//

import SwiftUI
import SwiftData
import Combine

struct CLIMonitorView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var monitor = CLIMonitor()

    @State private var showingCLICommands = false
    @State private var selectedCommand = ""

    var body: some View {
        VStack(spacing: 0) {
            // CLI Activity Header
            if monitor.isCLIActive {
                CLIActivityBar(monitor: monitor)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main Content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Real-time CLI Events
                        CLIEventsList(events: monitor.recentEvents)

                        // Active Operations
                        if !monitor.activeOperations.isEmpty {
                            ActiveOperationsSection(operations: monitor.activeOperations)
                        }

                        // Quick Actions
                        QuickActionsSection(
                            onAction: { action in
                                monitor.requestCLIAction(action)
                            }
                        )
                    }
                    .padding()
                }
                .onChange(of: monitor.recentEvents.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // CLI Control Panel
            CLIControlPanel(
                monitor: monitor,
                selectedCommand: $selectedCommand,
                showingCommands: $showingCLICommands
            )
        }
        .navigationTitle("CLI Monitor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Launch CLI Terminal") {
                        launchCLITerminal()
                    }
                    Button("View CLI Logs") {
                        showingCLICommands = true
                    }
                    Divider()
                    Toggle("Auto-Process", isOn: $monitor.autoProcess)
                } label: {
                    Image(systemName: "terminal")
                }
            }
        }
        .sheet(isPresented: $showingCLICommands) {
            CLICommandsSheet(monitor: monitor)
        }
    }

    private func launchCLITerminal() {
        // Launch Terminal with cascade CLI
        let script = """
        tell application "Terminal"
            activate
            do script "cascade interactive"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
}

// MARK: - CLI Activity Bar

struct CLIActivityBar: View {
    @ObservedObject var monitor: CLIMonitor

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("CLI Active")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Spacer()

            if let operation = monitor.currentOperation {
                Text(operation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let progress = monitor.currentProgress {
                ProgressView(value: progress.percentage)
                    .frame(width: 100)
                Text("\(Int(progress.percentage * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
    }
}

// MARK: - CLI Events List

struct CLIEventsList: View {
    let events: [CLIMonitor.Event]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent CLI Activity", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ForEach(events) { event in
                CLIEventRow(event: event)
            }

            if events.isEmpty {
                Text("No recent CLI activity")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.vertical, 8)
            }

            Spacer()
                .frame(height: 1)
                .id("bottom")
        }
    }
}

struct CLIEventRow: View {
    let event: CLIMonitor.Event

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: event.icon)
                .foregroundColor(event.iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)

                if let detail = event.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Active Operations

struct ActiveOperationsSection: View {
    let operations: [CLIMonitor.Operation]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Active Operations", systemImage: "gearshape.2")
                .font(.headline)

            ForEach(operations) { operation in
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)

                    VStack(alignment: .leading) {
                        Text(operation.name)
                            .font(.caption)
                            .fontWeight(.medium)

                        if let status = operation.status {
                            Text(status)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if operation.canCancel {
                        Button("Cancel") {
                            operation.cancel()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)
            }
        }
    }
}

// MARK: - Quick Actions

struct QuickActionsSection: View {
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Actions", systemImage: "bolt.circle")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                QuickActionButton(
                    title: "Fill Gaps",
                    icon: "square.stack.3d.up.fill",
                    color: .blue
                ) {
                    onAction("fill-gaps")
                }

                QuickActionButton(
                    title: "Sync Data",
                    icon: "arrow.triangle.2.circlepath",
                    color: .green
                ) {
                    onAction("sync")
                }

                QuickActionButton(
                    title: "Run Parse",
                    icon: "doc.text.magnifyingglass",
                    color: .orange
                ) {
                    onAction("parse")
                }

                QuickActionButton(
                    title: "Categorize",
                    icon: "tag.fill",
                    color: .purple
                ) {
                    onAction("categorize")
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CLI Control Panel

struct CLIControlPanel: View {
    @ObservedObject var monitor: CLIMonitor
    @Binding var selectedCommand: String
    @Binding var showingCommands: Bool

    @State private var commandInput = ""

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)

                TextField("Enter CLI command...", text: $commandInput)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        executeCommand()
                    }

                Button("Run") {
                    executeCommand()
                }
                .disabled(commandInput.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func executeCommand() {
        guard !commandInput.isEmpty else { return }
        monitor.executeCLICommand(commandInput)
        commandInput = ""
    }
}

// MARK: - CLI Monitor Model

@MainActor
class CLIMonitor: ObservableObject {
    @Published var isCLIActive = false
    @Published var recentEvents: [Event] = []
    @Published var activeOperations: [Operation] = []
    @Published var currentOperation: String?
    @Published var currentProgress: Progress?
    @Published var autoProcess = false

    private var cancellables = Set<AnyCancellable>()
    private let notificationCenter = DistributedNotificationCenter.default()

    struct Event: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let title: String
        let detail: String?
        let type: EventType

        enum EventType {
            case parse, categorize, sync, error, info
        }

        var icon: String {
            switch type {
            case .parse: return "doc.text"
            case .categorize: return "tag"
            case .sync: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.triangle"
            case .info: return "info.circle"
            }
        }

        var iconColor: Color {
            switch type {
            case .parse: return .blue
            case .categorize: return .purple
            case .sync: return .green
            case .error: return .red
            case .info: return .gray
            }
        }
    }

    struct Operation: Identifiable {
        let id = UUID()
        let name: String
        var status: String?
        let canCancel: Bool
        let cancel: () -> Void
    }

    struct Progress {
        let percentage: Double
        let message: String?
    }

    init() {
        setupListeners()
    }

    private func setupListeners() {
        // Listen for CLI events
        notificationCenter.addObserver(
            forName: Notification.Name("com.cascade.cli.dataChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCLINotification(notification)
        }
    }

    private func handleCLINotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let type = userInfo["type"] as? String else { return }

        isCLIActive = true

        // Add to recent events
        let event = Event(
            title: type.replacingOccurrences(of: ".", with: " ").capitalized,
            detail: userInfo["data"] as? String,
            type: eventTypeFromString(type)
        )
        recentEvents.append(event)

        // Keep only recent 20 events
        if recentEvents.count > 20 {
            recentEvents.removeFirst(recentEvents.count - 20)
        }

        // Update active operations
        if type.contains(".started") {
            let operation = Operation(
                name: type.replacingOccurrences(of: ".started", with: ""),
                status: "Running",
                canCancel: true,
                cancel: { [weak self] in
                    self?.cancelOperation(type)
                }
            )
            activeOperations.append(operation)
        } else if type.contains(".completed") || type.contains(".failed") {
            let operationType = type
                .replacingOccurrences(of: ".completed", with: "")
                .replacingOccurrences(of: ".failed", with: "")
            activeOperations.removeAll { $0.name == operationType }
        }

        // Update progress
        if let data = userInfo["data"] as? [String: Any],
           let progress = data["progress"] as? Double {
            currentProgress = Progress(
                percentage: progress,
                message: data["message"] as? String
            )
        }

        // Clear active state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.activeOperations.isEmpty == true {
                self?.isCLIActive = false
                self?.currentProgress = nil
            }
        }
    }

    private func eventTypeFromString(_ type: String) -> Event.EventType {
        if type.contains("parse") { return .parse }
        if type.contains("categorize") { return .categorize }
        if type.contains("sync") { return .sync }
        if type.contains("error") { return .error }
        return .info
    }

    func requestCLIAction(_ action: String) {
        notificationCenter.post(
            name: Notification.Name("com.cascade.gui.requestsCLI"),
            object: nil,
            userInfo: ["action": action]
        )
    }

    func executeCLICommand(_ command: String) {
        // Execute CLI command via shell
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["cascade"] + command.components(separatedBy: " ")

        let pipe = Pipe()
        task.standardOutput = pipe

        task.launch()
    }

    private func cancelOperation(_ type: String) {
        notificationCenter.post(
            name: Notification.Name("com.cascade.gui.cancelsOperation"),
            object: nil,
            userInfo: ["operation": type]
        )
    }
}

// MARK: - CLI Commands Sheet

struct CLICommandsSheet: View {
    @ObservedObject var monitor: CLIMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Parse Commands") {
                    CommandRow(command: "cascade parse list", description: "List all parse plans")
                    CommandRow(command: "cascade parse run <id> --csv file.csv", description: "Run parse plan")
                }

                Section("Categorization Commands") {
                    CommandRow(command: "cascade categorize <session>", description: "Run categorization")
                    CommandRow(command: "cascade categorize fill-gaps", description: "Fill coverage gaps")
                }

                Section("Monitoring Commands") {
                    CommandRow(command: "cascade monitor", description: "Monitor GUI activity")
                    CommandRow(command: "cascade interactive", description: "Start interactive mode")
                }
            }
            .navigationTitle("CLI Commands")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CommandRow: View {
    let command: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.blue)
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}