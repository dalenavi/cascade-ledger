# Background Job System Design

## Core Requirements

**Jobs must:**
1. Continue running when user navigates away
2. Survive app restart (persist state)
3. Be pausable/resumable
4. Show progress anywhere in app
5. Queue multiple jobs
6. Handle rate limits gracefully

## Architecture

### Job Model

```swift
@Model
class BackgroundJob {
    var id: UUID
    var type: JobType
    var status: JobStatus
    var progress: Double  // 0.0 - 1.0

    // State persistence
    var stateData: Data?  // JSON-encoded job-specific state

    // Progress tracking
    var currentStep: String
    var totalSteps: Int
    var completedSteps: Int

    // Error handling
    var errorMessage: String?
    var retryCount: Int
    var maxRetries: Int

    // Timing
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    // Owner
    var accountId: UUID?

    enum JobType: String {
        case categorization = "categorization"
        case priceImport = "price_import"
        case positionRecalc = "position_recalc"
        case export = "export"
    }

    enum JobStatus: String {
        case queued = "queued"
        case running = "running"
        case paused = "paused"
        case waiting = "waiting"        // Rate limit wait
        case completed = "completed"
        case failed = "failed"
        case cancelled = "cancelled"
    }
}
```

### Job Manager (Singleton)

```swift
@MainActor
class JobManager: ObservableObject {
    static let shared = JobManager()

    @Published var activeJobs: [BackgroundJob] = []
    @Published var queuedJobs: [BackgroundJob] = []

    private var modelContext: ModelContext?
    private var jobExecutors: [UUID: any JobExecutor] = [:]

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPersistedJobs()
    }

    func enqueue<T: JobExecutor>(_ job: T) {
        let bgJob = BackgroundJob(type: job.type)
        modelContext.insert(bgJob)

        jobExecutors[bgJob.id] = job
        queuedJobs.append(bgJob)

        processNextJob()
    }

    func pause(_ job: BackgroundJob) {
        if let executor = jobExecutors[job.id] {
            executor.pause()
            job.status = .paused
        }
    }

    func resume(_ job: BackgroundJob) {
        if let executor = jobExecutors[job.id] {
            Task {
                await executor.resume()
            }
        }
    }

    func cancel(_ job: BackgroundJob) {
        if let executor = jobExecutors[job.id] {
            executor.cancel()
            job.status = .cancelled
            jobExecutors.removeValue(forKey: job.id)
        }
    }

    private func processNextJob() {
        guard activeJobs.count < 3 else { return }  // Max 3 concurrent
        guard let next = queuedJobs.first else { return }

        queuedJobs.removeFirst()
        activeJobs.append(next)
        next.status = .running

        Task {
            if let executor = jobExecutors[next.id] {
                await executor.execute()
            }
        }
    }

    private func loadPersistedJobs() {
        // On app start, resume incomplete jobs
        let descriptor = FetchDescriptor<BackgroundJob>(
            predicate: #Predicate { job in
                job.status == .paused || job.status == .waiting
            }
        )

        if let pausedJobs = try? modelContext?.fetch(descriptor) {
            queuedJobs.append(contentsOf: pausedJobs)
        }
    }
}
```

### Job Executor Protocol

```swift
protocol JobExecutor: Actor {
    var type: BackgroundJob.JobType { get }
    var job: BackgroundJob { get }

    func execute() async throws
    func pause()
    func resume() async
    func cancel()
}

// Example: Categorization Job
actor CategorizationJobExecutor: JobExecutor {
    let type: BackgroundJob.JobType = .categorization
    let job: BackgroundJob

    private var isPaused = false
    private var isCancelled = false

    // Job-specific state
    private var csvRows: [[String: String]]
    private var processedRows: Int = 0

    init(job: BackgroundJob, csvRows: [[String: String]]) {
        self.job = job
        self.csvRows = csvRows

        // Restore state if resuming
        if let stateData = job.stateData,
           let state = try? JSONDecoder().decode(State.self, from: stateData) {
            self.processedRows = state.processedRows
        }
    }

    func execute() async throws {
        job.status = .running

        while processedRows < csvRows.count && !isCancelled {
            // Check pause
            if isPaused {
                job.status = .paused
                saveState()
                return
            }

            // Process batch
            let batch = await processBatch(rows: csvRows[processedRows..<min(processedRows + 100, csvRows.count)])

            // Handle rate limit
            if batch.rateLimitHit {
                job.status = .waiting
                saveState()

                // Wait 2 minutes
                try? await Task.sleep(for: .seconds(120))

                job.status = .running
                continue  // Retry
            }

            processedRows += batch.rowsProcessed
            job.progress = Double(processedRows) / Double(csvRows.count)
            job.completedSteps += 1

            saveState()
        }

        job.status = isCancelled ? .cancelled : .completed
    }

    func pause() {
        isPaused = true
    }

    func resume() async {
        isPaused = false
        try? await execute()
    }

    func cancel() {
        isCancelled = true
    }

    private func saveState() {
        let state = State(processedRows: processedRows)
        job.stateData = try? JSONEncoder().encode(state)
    }

    struct State: Codable {
        let processedRows: Int
    }
}
```

### UI Integration

#### Global Job Status Bar

```swift
// In app root, always visible
JobStatusBar()

struct JobStatusBar: View {
    @ObservedObject var jobManager = JobManager.shared

    var body: some View {
        if !jobManager.activeJobs.isEmpty {
            HStack {
                ForEach(jobManager.activeJobs) { job in
                    JobPill(job: job)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
        }
    }
}

struct JobPill: View {
    let job: BackgroundJob

    var body: some View {
        Button(action: { /* Show job detail */ }) {
            HStack {
                ProgressView(value: job.progress)
                    .frame(width: 40)
                Text("\(Int(job.progress * 100))%")
                    .font(.caption)
                Text(job.currentStep)
                    .font(.caption)
            }
            .padding(6)
            .background(Color.purple.opacity(0.2))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
```

## Migration Path

### Phase 1: Extract to Singleton (Now)
- Move `DirectCategorizationService` to app-level
- Use `@EnvironmentObject` instead of view state
- Jobs continue across navigation

### Phase 2: Persistence (Soon)
- Add `BackgroundJob` model
- Save state on each batch
- Resume on app restart

### Phase 3: Queue System (Future)
- Multiple jobs can queue
- Automatic execution
- Priority levels

### Phase 4: Job Types (Future)
- Price data import jobs
- Export jobs
- Position recalculation jobs

## Implementation for Current Categorization

```swift
// In cascade_ledgerApp.swift
@StateObject private var jobManager = JobManager.shared

var body: some Scene {
    WindowGroup {
        ContentView()
            .environmentObject(jobManager)
            .overlay(alignment: .bottom) {
                JobStatusBar()
            }
    }
    .modelContainer(sharedModelContainer)
}

// Change DirectCategorizationService to singleton
class DirectCategorizationService: ObservableObject {
    static let shared = DirectCategorizationService()

    @Published var currentJob: BackgroundJob?

    // Same methods but job state persists
}
```

This allows:
- Navigate away while job runs
- App restart resumes job
- Global visibility of progress
- No "error" dialogs for rate limits
