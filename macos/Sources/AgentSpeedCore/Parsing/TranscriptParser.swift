import Foundation

/// Which family of transcript file a file belongs to. A new file-based source adds a case here, a line extractor and
/// parser (`DecodedLine`, `TranscriptParser`, `TranscriptDecoder`) and its location (`TranscriptLocations`).
enum TranscriptFamily: String, CaseIterable, Sendable {
    case codex
    case claude
    /// DeepSeek Harness (dsh).
    case dsh
    /// Gemini CLI.
    case gemini
    /// omp (oh-my-pi).
    case omp
    /// Antigravity: one SQLite database per conversation, read as a whole unit per change (METRICS 4.8, 5.4).
    case antigravity
    /// WorkBuddy (China edition) and WorkBuddy AI (international edition): one format, one root each (METRICS 4.9).
    case workbuddy
    case workbuddyAi
    case kimi
    case grokBuild
    case pi
    /// Factory Droid: a session transcript read with its settings file (METRICS 4.16).
    case droid
    /// Qoder CLI: Claude Code's transcript format, read by the Claude parser with its own rules (METRICS 4.19).
    case qoderCli
    /// CodeBuddy Code: the WorkBuddy format in the standalone CLI's own folder (METRICS 4.20).
    case codebuddyCode

    /// Nil for sources that are not read from transcript files: OpenCode, ZCode and OpenClaw keep databases
    /// (`OpencodeSource`, `ZcodeSource`, `OpenClawSource`); Hermes Agent's log sets share one state per folder
    /// (`HermesSource`); Devin and Qoder IDE read databases (`DevinSource`, `QoderSource`).
    init?(_ source: SourceKind) {
        switch source {
        case .codex: self = .codex
        case .claudeCode, .claudeDesktop: self = .claude
        case .deepseek: self = .dsh
        case .gemini: self = .gemini
        case .omp: self = .omp
        case .antigravity: self = .antigravity
        case .workbuddy: self = .workbuddy
        case .workbuddyAi: self = .workbuddyAi
        case .kimi: self = .kimi
        case .grokBuild: self = .grokBuild
        case .pi: self = .pi
        case .droid: self = .droid
        case .qoderCli: self = .qoderCli
        case .codebuddyCode: self = .codebuddyCode
        case .opencode, .zcode, .openclaw, .hermes, .devin, .qoder: return nil
        }
    }

    /// Sources whose transcripts belong to this family.
    var sources: [SourceKind] {
        switch self {
        case .codex: [.codex]
        case .claude: [.claudeCode, .claudeDesktop]
        case .dsh: [.deepseek]
        case .gemini: [.gemini]
        case .omp: [.omp]
        case .antigravity: [.antigravity]
        case .workbuddy: [.workbuddy]
        case .workbuddyAi: [.workbuddyAi]
        case .kimi: [.kimi]
        case .grokBuild: [.grokBuild]
        case .pi: [.pi]
        case .droid: [.droid]
        case .qoderCli: [.qoderCli]
        case .codebuddyCode: [.codebuddyCode]
        }
    }

    /// File names (and for Gemini CLI, omp, Antigravity, WorkBuddy and Pi, folder layout) of this family's transcripts
    /// (METRICS 2, 4.6 – 4.13).
    var names: TranscriptNames {
        switch self {
        case .codex: .codexSession
        case .claude, .qoderCli: .jsonl
        case .dsh: .dshSession
        case .gemini: .geminiSession
        case .omp: .ompSession
        case .antigravity: .antigravityDatabase
        case .workbuddy, .workbuddyAi, .codebuddyCode: .workbuddySession
        case .kimi: .kimiSession
        case .grokBuild: .grokBuildSession
        case .pi: .piSession
        case .droid: .droidSession
        }
    }

    /// An Antigravity database is one SQLite file plus its `-wal`; every other family is a single file.
    var isDatabase: Bool { self == .antigravity }

    /// The two WorkBuddy editions.
    var isWorkBuddy: Bool { self == .workbuddy || self == .workbuddyAi }

    /// Families that write the WorkBuddy format (METRICS 4.9): both editions and CodeBuddy Code (4.20).
    var writesWorkBuddyFormat: Bool { isWorkBuddy || self == .codebuddyCode }

    /// The stat that identifies one transcript of this family; nil unless it is a regular file.
    func stat(_ path: String) -> FileStat? {
        if isDatabase { return FileStat.databaseStat(path) }
        if self == .grokBuild { return GrokBuildParser.stat(path) }
        if self == .droid { return DroidPaths.stat(path) }
        guard let stat = FileStat.lstat(path), stat.isRegularFile else { return nil }
        return stat
    }

    /// The transcript a changed path belongs to: an Antigravity `<id>.db-wal` stands for `<id>.db`, a Factory Droid
    /// `<id>.settings.json` for `<id>.jsonl`.
    func transcriptPath(forChanged path: String) -> String {
        if self == .droid { return DroidPaths.transcriptPath(ofSidecar: path) ?? path }
        if self == .grokBuild, (path as NSString).lastPathComponent == "summary.json" {
            return ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent("updates.jsonl")
        }
        guard isDatabase, path.hasSuffix(".db-wal") else { return path }
        return String(path.dropLast(4))
    }
}

enum DecodedLine: Sendable {
    case codex(LineExtraction<CodexLine>)
    case claude(LineExtraction<ClaudeLine>)
    case dsh(LineExtraction<DshLine>)
    case gemini(LineExtraction<GeminiLine>)
    case omp(LineExtraction<OmpLine>)
    case workbuddy(LineExtraction<WorkBuddyLine>)
    case kimi(LineExtraction<KimiLine>)
    case grokBuild(LineExtraction<GrokBuildLine>)
    case pi(LineExtraction<PiLine>)
    case droid(DroidLineRead)
}

/// Lines decoded ahead of time (off the state-machine thread) so seeding can extract in parallel. An Antigravity read
/// is one batch of database rows.
enum DecodedLines: Sendable {
    case codex([LineExtraction<CodexLine>])
    case claude([LineExtraction<ClaudeLine>])
    case dsh([LineExtraction<DshLine>])
    case gemini([LineExtraction<GeminiLine>])
    case omp([LineExtraction<OmpLine>])
    case antigravity(AntigravityBatch?)
    case workbuddy([LineExtraction<WorkBuddyLine>])
    case kimi([LineExtraction<KimiLine>])
    case grokBuild([LineExtraction<GrokBuildLine>])
    case pi([LineExtraction<PiLine>])
    /// With where the reader began (METRICS 4.16 Allocation).
    case droid([DroidLineRead], start: Int64?)
}

/// A family-agnostic per-file parser. Uses a single tagged enum instead of 11 side-by-side Optionals so each
/// `TrackedFile` pays only the size of the largest parser rather than the sum of all eleven.
struct TranscriptParser: Sendable {
    private enum Machine: Sendable {
        case codex(CodexParser)
        case claude(ClaudeParser)
        case dsh(DshParser)
        case gemini(GeminiParser)
        case omp(OmpParser)
        case antigravity(AntigravityParser)
        case workbuddy(WorkBuddyParser)
        case kimi(KimiParser)
        case grokBuild(GrokBuildParser)
        case pi(PiParser)
        case droid(DroidParser)
        case _moving
    }

    let family: TranscriptFamily
    let fileID: FileID
    private var machine: Machine

    /// `root` is the root folder the file was discovered under (omp and WorkBuddy derive `isSubagent` from it,
    /// METRICS 4.7, 4.9).
    init(family: TranscriptFamily, agentId: String, fileID: FileID, root: String? = nil) {
        self.family = family
        self.fileID = fileID
        switch family {
        case .codex: machine = .codex(CodexParser(agentId: agentId, fileID: fileID))
        case .claude: machine = .claude(ClaudeParser(agentId: agentId, fileID: fileID))
        case .qoderCli: machine = .claude(ClaudeParser(agentId: agentId, fileID: fileID, variant: .qoderCli))
        case .dsh: machine = .dsh(DshParser(agentId: agentId, fileID: fileID))
        case .gemini: machine = .gemini(GeminiParser(agentId: agentId, fileID: fileID))
        case .omp: machine = .omp(OmpParser(agentId: agentId, fileID: fileID, root: root))
        case .antigravity: machine = .antigravity(AntigravityParser(agentId: agentId, fileID: fileID))
        case .workbuddy, .workbuddyAi, .codebuddyCode:
            machine = .workbuddy(WorkBuddyParser(source: family.sources[0], agentId: agentId, fileID: fileID, root: root))
        case .kimi: machine = .kimi(KimiParser(agentId: agentId, fileID: fileID))
        case .grokBuild: machine = .grokBuild(GrokBuildParser(agentId: agentId, fileID: fileID))
        case .pi: machine = .pi(PiParser(agentId: agentId, fileID: fileID))
        case .droid: machine = .droid(DroidParser(agentId: agentId, fileID: fileID))
        }
    }

    var state: AgentState {
        switch machine {
        case .codex(let p): p.state
        case .claude(let p): p.state
        case .dsh(let p): p.state
        case .gemini(let p): p.state
        case .omp(let p): p.state
        case .antigravity(let p): p.state
        case .workbuddy(let p): p.state
        case .kimi(let p): p.state
        case .grokBuild(let p): p.state
        case .pi(let p): p.state
        case .droid(let p): p.state
        case ._moving: AgentState(source: family.sources[0])
        }
    }

    /// An Antigravity database without the expected tables (`unsupportedFormat`).
    var isUnsupported: Bool {
        if case .antigravity(let p) = machine { return p.isUnsupported }
        return false
    }

    /// Decodes one unit of input: a line, or a whole document for Gemini CLI legacy `.json` files. Antigravity
    /// databases are never fed bytes; their reads arrive as batches. `offset` is the line's position in the file
    /// (Factory Droid only).
    func decode(_ bytes: UnsafeRawBufferPointer, offset: Int64 = 0) -> DecodedLine? {
        switch family {
        case .codex: .codex(CodexLineExtractor.extract(bytes))
        case .claude, .qoderCli: .claude(ClaudeLineExtractor.extract(bytes))
        case .dsh: .dsh(DshLineExtractor.extract(bytes))
        case .gemini:
            if case .gemini(let p) = machine, p.isDocument {
                .gemini(GeminiLineExtractor.extractDocument(bytes))
            } else {
                .gemini(GeminiLineExtractor.extract(bytes))
            }
        case .omp: .omp(OmpLineExtractor.extract(bytes))
        case .workbuddy, .workbuddyAi, .codebuddyCode: .workbuddy(WorkBuddyLineExtractor.extract(bytes))
        case .antigravity: nil
        case .kimi: .kimi(KimiLineExtractor.extract(bytes))
        case .grokBuild: .grokBuild(GrokBuildLine.extract(bytes))
        case .pi: .pi(PiLineExtractor.extract(bytes))
        case .droid: .droid(DroidLineRead(extraction: DroidLineExtractor.extract(bytes), offset: offset, length: bytes.count))
        }
    }

    var hasPartialHistory: Bool {
        if case .grokBuild(let p) = machine { return p.partialHistory }
        return false
    }

    /// A Codex file's newest account limits (QUOTAS 3).
    var codexQuota: QuotaSnapshot? {
        if case .codex(let p) = machine { return p.quota }
        return nil
    }

    /// A Codex file keeps every token count with limits for the quota estimate until they are taken (QUOTAS 10.4).
    mutating func collectCodexQuotaLines() {
        if case .codex(var p) = machine {
            machine = ._moving
            p.collectQuotaLines()
            machine = .codex(p)
        }
    }

    mutating func takeCodexQuotaLines() -> [QuotaCodexLine] {
        guard case .codex(var p) = machine else { return [] }
        machine = ._moving
        let lines = p.takeQuotaLines()
        machine = .codex(p)
        return lines
    }

    mutating func refreshMetadata(deduper: inout Deduper, emit: (ResponseUpsert) -> Void) -> Bool {
        guard case .grokBuild(var p) = machine else { return false }
        machine = ._moving
        let changed = p.refreshMetadata(deduper: &deduper, emit: emit)
        machine = .grokBuild(p)
        return changed
    }

    /// Counts a unit of input that could not be decoded at all, such as a corrupt zstd frame (METRICS 5.1).
    mutating func noteMalformedLine() {
        switch machine {
        case .codex(var p): machine = ._moving; p.noteMalformedLine(); machine = .codex(p)
        case .claude(var p): machine = ._moving; p.noteMalformedLine(); machine = .claude(p)
        case .dsh(var p): machine = ._moving; p.noteMalformedLine(); machine = .dsh(p)
        case .gemini(var p): machine = ._moving; p.noteMalformedLine(); machine = .gemini(p)
        case .omp(var p): machine = ._moving; p.noteMalformedLine(); machine = .omp(p)
        case .antigravity(var p): machine = ._moving; p.noteMalformedLine(); machine = .antigravity(p)
        case .workbuddy(var p): machine = ._moving; p.noteMalformedLine(); machine = .workbuddy(p)
        case .kimi(var p): machine = ._moving; p.noteMalformedLine(); machine = .kimi(p)
        case .grokBuild(var p): machine = ._moving; p.noteMalformedLine(); machine = .grokBuild(p)
        case .pi(var p): machine = ._moving; p.noteMalformedLine(); machine = .pi(p)
        case .droid(var p): machine = ._moving; p.noteMalformedLine(); machine = .droid(p)
        case ._moving: break
        }
    }

    /// `tools`: the line's tool calls and results (METRICS 6.10).
    mutating func consume(_ line: DecodedLine, tools: [ToolEvent] = [], deduper: inout Deduper, emit: (ResponseUpsert) -> Void) {
        switch (line, machine) {
        case (.codex(let extraction), .codex(var p)):
            machine = ._moving; p.consume(extraction, tools: tools, deduper: &deduper, emit: emit); machine = .codex(p)
        case (.claude(let extraction), .claude(var p)):
            machine = ._moving; p.consume(extraction, tools: tools, deduper: &deduper, emit: emit); machine = .claude(p)
        case (.dsh(let extraction), .dsh(var p)):
            machine = ._moving; p.consume(extraction, deduper: &deduper, emit: emit); machine = .dsh(p)
        case (.gemini(let extraction), .gemini(var p)):
            machine = ._moving; p.consume(extraction, deduper: &deduper, emit: emit); machine = .gemini(p)
        case (.omp(let extraction), .omp(var p)):
            machine = ._moving; p.consume(extraction, tools: tools, deduper: &deduper, emit: emit); machine = .omp(p)
        case (.workbuddy(let extraction), .workbuddy(var p)):
            machine = ._moving; p.consume(extraction, deduper: &deduper, emit: emit); machine = .workbuddy(p)
        case (.kimi(let extraction), .kimi(var p)):
            machine = ._moving; p.consume(extraction, deduper: &deduper, emit: emit); machine = .kimi(p)
        case (.grokBuild(let extraction), .grokBuild(var p)):
            machine = ._moving; p.consume(extraction, deduper: &deduper, emit: emit); machine = .grokBuild(p)
        case (.pi(let extraction), .pi(var p)):
            machine = ._moving; p.consume(extraction, tools: tools, deduper: &deduper, emit: emit); machine = .pi(p)
        case (.droid(let line), .droid(var p)):
            machine = ._moving; p.consume(line, tools: tools, deduper: &deduper); machine = .droid(p)
        default:
            break
        }
    }

    /// A live line: its responses and its tool calls. `onToolResult` receives the calls whose first result it holds
    /// (METRICS 6.10), after its responses. `offset` is the line's position in the file (Factory Droid only).
    mutating func consume(
        rawLine bytes: UnsafeRawBufferPointer,
        offset: Int64 = 0,
        deduper: inout Deduper,
        emit: (ResponseUpsert) -> Void,
        onToolResult: (ToolCompletion) -> Void = { _ in }
    ) {
        guard let line = decode(bytes, offset: offset) else { return }
        let tools = ToolEventExtractor.reads(family) ? ToolEventExtractor.events(family, bytes) : []
        consume(line, tools: tools, deduper: &deduper, emit: emit)
        drainToolCompletions(onToolResult)
    }

    /// Decoded lines with the tool events the decoding thread read for them (`tools[i]` belongs to line `i`; empty
    /// when the family has none). Completions follow each line's responses, in order.
    mutating func consume(
        _ lines: DecodedLines,
        tools: [[ToolEvent]] = [],
        deduper: inout Deduper,
        emit: (ResponseUpsert) -> Void,
        onToolResult: (ToolCompletion) -> Void = { _ in }
    ) {
        func toolsOf(_ index: Int) -> [ToolEvent] { index < tools.count ? tools[index] : [] }
        switch (lines, machine) {
        case (.codex(let extractions), .codex(var p)):
            machine = ._moving
            for (index, extraction) in extractions.enumerated() {
                p.consume(extraction, tools: toolsOf(index), deduper: &deduper, emit: emit)
                for completion in p.takeToolCompletions() { onToolResult(completion) }
            }
            machine = .codex(p)
        case (.claude(let extractions), .claude(var p)):
            machine = ._moving
            for (index, extraction) in extractions.enumerated() {
                p.consume(extraction, tools: toolsOf(index), deduper: &deduper, emit: emit)
                for completion in p.takeToolCompletions() { onToolResult(completion) }
            }
            machine = .claude(p)
        case (.dsh(let extractions), .dsh(var p)):
            machine = ._moving
            for extraction in extractions { p.consume(extraction, deduper: &deduper, emit: emit) }
            machine = .dsh(p)
        case (.gemini(let extractions), .gemini(var p)):
            machine = ._moving
            for extraction in extractions { p.consume(extraction, deduper: &deduper, emit: emit) }
            machine = .gemini(p)
        case (.omp(let extractions), .omp(var p)):
            machine = ._moving
            for (index, extraction) in extractions.enumerated() {
                p.consume(extraction, tools: toolsOf(index), deduper: &deduper, emit: emit)
                for completion in p.takeToolCompletions() { onToolResult(completion) }
            }
            machine = .omp(p)
        case (.antigravity(let batch), .antigravity(var p)):
            machine = ._moving
            if let batch { p.consume(batch, deduper: &deduper, emit: emit) }
            machine = .antigravity(p)
        case (.workbuddy(let extractions), .workbuddy(var p)):
            machine = ._moving
            for extraction in extractions { p.consume(extraction, deduper: &deduper, emit: emit) }
            machine = .workbuddy(p)
        case (.kimi(let extractions), .kimi(var p)):
            machine = ._moving
            for extraction in extractions { p.consume(extraction, deduper: &deduper, emit: emit) }
            machine = .kimi(p)
        case (.grokBuild(let extractions), .grokBuild(var p)):
            machine = ._moving
            for extraction in extractions { p.consume(extraction, deduper: &deduper, emit: emit) }
            machine = .grokBuild(p)
        case (.pi(let extractions), .pi(var p)):
            machine = ._moving
            for (index, extraction) in extractions.enumerated() {
                p.consume(extraction, tools: toolsOf(index), deduper: &deduper, emit: emit)
                for completion in p.takeToolCompletions() { onToolResult(completion) }
            }
            machine = .pi(p)
        case (.droid(let lines, let start), .droid(var p)):
            machine = ._moving
            p.noteReadStart(start)
            for (index, line) in lines.enumerated() {
                p.consume(line, tools: toolsOf(index), deduper: &deduper)
                for completion in p.takeToolCompletions() { onToolResult(completion) }
            }
            machine = .droid(p)
        default:
            break
        }
    }

    // MARK: - Actions (METRICS 6.10)

    /// Lines read while seeding add seeded actions; their results are not live.
    mutating func setSeeding(_ seeding: Bool) {
        switch machine {
        case .codex(var p): machine = ._moving; p.setSeeding(seeding); machine = .codex(p)
        case .claude(var p): machine = ._moving; p.setSeeding(seeding); machine = .claude(p)
        case .omp(var p): machine = ._moving; p.setSeeding(seeding); machine = .omp(p)
        case .pi(var p): machine = ._moving; p.setSeeding(seeding); machine = .pi(p)
        case .droid(var p): machine = ._moving; p.setSeeding(seeding); machine = .droid(p)
        default: break
        }
    }

    /// The history analysis keeps no stored actions, only the completions of whole files.
    mutating func keepCompletionsOnly() {
        switch machine {
        case .codex(var p): machine = ._moving; p.keepCompletionsOnly(); machine = .codex(p)
        case .claude(var p): machine = ._moving; p.keepCompletionsOnly(); machine = .claude(p)
        case .omp(var p): machine = ._moving; p.keepCompletionsOnly(); machine = .omp(p)
        case .pi(var p): machine = ._moving; p.keepCompletionsOnly(); machine = .pi(p)
        case .droid(var p): machine = ._moving; p.keepCompletionsOnly(); machine = .droid(p)
        default: break
        }
    }

    private mutating func drainToolCompletions(_ body: (ToolCompletion) -> Void) {
        let completions: [ToolCompletion]
        switch machine {
        case .codex(var p): machine = ._moving; completions = p.takeToolCompletions(); machine = .codex(p)
        case .claude(var p): machine = ._moving; completions = p.takeToolCompletions(); machine = .claude(p)
        case .omp(var p): machine = ._moving; completions = p.takeToolCompletions(); machine = .omp(p)
        case .pi(var p): machine = ._moving; completions = p.takeToolCompletions(); machine = .pi(p)
        case .droid(var p): machine = ._moving; completions = p.takeToolCompletions(); machine = .droid(p)
        default: return
        }
        for completion in completions { body(completion) }
    }

    // MARK: - Factory Droid read cycles (METRICS 4.16)

    /// Where the reader began, for a live read of new lines.
    mutating func noteReadStart(_ offset: Int64?) {
        guard case .droid(var p) = machine else { return }
        machine = ._moving
        p.noteReadStart(offset)
        machine = .droid(p)
    }

    /// After a read's lines: reads a changed sidecar and emits the calls its growth covers. True when anything changed.
    mutating func finishReadCycle(emit: (ResponseUpsert) -> Void) -> Bool {
        guard case .droid(var p) = machine else { return false }
        machine = ._moving
        let changed = p.finishReadCycle(emit: emit)
        machine = .droid(p)
        return changed
    }

    /// A Factory Droid session whose transcript is read from its end takes its sidecar's counters as a baseline.
    mutating func takeBaseline(_ snapshot: DroidSidecar.Snapshot) {
        guard case .droid(var p) = machine else { return }
        machine = ._moving
        p.takeBaseline(snapshot)
        machine = .droid(p)
    }

    /// History only: a Factory Droid session's counters left without a call.
    mutating func finishHistory(emit: (ResponseUpsert) -> Void) {
        guard case .droid(var p) = machine else { return }
        machine = ._moving
        p.finishHistory(emit: emit)
        machine = .droid(p)
    }

    /// A Factory Droid sidecar that is not the version last looked at.
    var sidecarHasChanged: Bool {
        if case .droid(let p) = machine { return p.sidecarHasChanged }
        return false
    }

    /// A Factory Droid session's counter growth not yet allocated (P).
    var droidPending: DroidCounters? {
        if case .droid(let p) = machine { return p.pending }
        return nil
    }

    /// The last read of a Factory Droid session could not tell its own counters: history does not store it.
    var droidOwnCountersUnknown: Bool {
        if case .droid(let p) = machine { return p.ownCountersUnknown }
        return false
    }

    /// The parent sidecar a Factory Droid session last found unreadable, kept between history analyses.
    var droidUnreadableParent: DroidPaths.Signature? {
        get {
            if case .droid(let p) = machine { return p.unreadableParent }
            return nil
        }
        set {
            guard case .droid(var p) = machine else { return }
            machine = ._moving
            p.unreadableParent = newValue
            machine = .droid(p)
        }
    }
}

/// Reads a whole transcript (from the reader's position) and decodes its lines, off the state-machine thread. With
/// `tools` it also reads each line's tool events without hashing their inputs (METRICS 6.10): `tools[i]` belongs to
/// line `i`.
enum TranscriptDecoder {
    struct Output: Sendable {
        var lines: DecodedLines
        var read: FileTailer.ReadResult
        /// Empty without `tools` or for a family without tool calls.
        var tools: [[ToolEvent]] = []
    }

    static func decode(_ family: TranscriptFamily, reader: inout TranscriptReader) -> (lines: DecodedLines, read: FileTailer.ReadResult) {
        let output = decode(family, reader: &reader, tools: false)
        return (output.lines, output.read)
    }

    static func decode(_ family: TranscriptFamily, reader: inout TranscriptReader, tools: Bool) -> Output {
        let readsTools = tools && ToolEventExtractor.reads(family)
        switch family {
        case .codex:
            return extract(CodexLineExtractor.extract, reader: &reader, family: family, tools: readsTools, wrap: DecodedLines.codex)
        case .claude, .qoderCli:
            return extract(ClaudeLineExtractor.extract, reader: &reader, family: family, tools: readsTools, wrap: DecodedLines.claude)
        case .dsh:
            return extract(DshLineExtractor.extract, reader: &reader, family: family, tools: false, wrap: DecodedLines.dsh)
        case .gemini:
            let extractor = reader.isDocument ? GeminiLineExtractor.extractDocument : GeminiLineExtractor.extract
            return extract(extractor, reader: &reader, family: family, tools: false, wrap: DecodedLines.gemini)
        case .omp:
            return extract(OmpLineExtractor.extract, reader: &reader, family: family, tools: readsTools, wrap: DecodedLines.omp)
        case .antigravity:
            let (batch, read) = reader.readDatabase()
            return Output(lines: .antigravity(batch), read: read)
        case .workbuddy, .workbuddyAi, .codebuddyCode:
            return extract(WorkBuddyLineExtractor.extract, reader: &reader, family: family, tools: false, wrap: DecodedLines.workbuddy)
        case .kimi:
            return extract(KimiLineExtractor.extract, reader: &reader, family: family, tools: false, wrap: DecodedLines.kimi)
        case .grokBuild:
            return extract(GrokBuildLine.extract, reader: &reader, family: family, tools: false, wrap: DecodedLines.grokBuild)
        case .pi:
            return extract(PiLineExtractor.extract, reader: &reader, family: family, tools: readsTools, wrap: DecodedLines.pi)
        case .droid:
            var lines: [DroidLineRead] = []
            var toolLines: [[ToolEvent]] = []
            let read = reader.read(onLineAt: { bytes, offset in
                let extraction = DroidLineExtractor.extract(bytes)
                if case .blank = extraction { return }
                lines.append(DroidLineRead(extraction: extraction, offset: offset, length: bytes.count))
                guard readsTools else { return }
                if case .line = extraction {
                    toolLines.append(ToolEventExtractor.events(.droid, bytes, hashes: false))
                } else {
                    toolLines.append([])
                }
            })
            return Output(lines: .droid(lines, start: read.startOffset), read: read, tools: toolLines)
        }
    }

    private static func extract<Line: Sendable>(
        _ extractor: (UnsafeRawBufferPointer) -> LineExtraction<Line>,
        reader: inout TranscriptReader,
        family: TranscriptFamily,
        tools: Bool,
        wrap: ([LineExtraction<Line>]) -> DecodedLines
    ) -> Output {
        var lines: [LineExtraction<Line>] = []
        var toolLines: [[ToolEvent]] = []
        let read = reader.read(onMalformed: {
            lines.append(.malformed)
            if tools { toolLines.append([]) }
        }) { bytes in
            let extraction = extractor(bytes)
            if case .blank = extraction { return }
            lines.append(extraction)
            guard tools else { return }
            if case .line = extraction {
                toolLines.append(ToolEventExtractor.events(family, bytes, hashes: false))
            } else {
                toolLines.append([])
            }
        }
        return Output(lines: wrap(lines), read: read, tools: toolLines)
    }
}
