import Darwin
import Foundation

/// 重命名错误码。UI 与日志只依赖稳定错误码。
enum FileRenameErrorCode: String, Codable, Sendable, Equatable {
    case invalidPath
    case crossDirectory
    case extensionChanged
    case sourceMissing
    case targetMissing
    case targetExists
    case notRegularFile
    case symbolicLinkUnsupported
    case fileChanged
    case permissionDenied
    case crossDevice
    case journalWriteFailed
    case journalReadFailed
    case undoConflict
    case renameFailed
}

struct FileRenameError: Error, Codable, Sendable, Equatable {
    let code: FileRenameErrorCode
    let detail: String

    init(_ code: FileRenameErrorCode, detail: String = "") {
        self.code = code
        self.detail = detail
    }
}

extension FileRenameError: LocalizedError {
    var errorDescription: String? {
        switch code {
        case .invalidPath: "The path is invalid."
        case .crossDirectory: "The target is not in the same directory."
        case .extensionChanged: "The target extension differs from the source."
        case .sourceMissing: "The source file no longer exists."
        case .targetMissing: "The renamed file no longer exists."
        case .targetExists: "The target already exists."
        case .notRegularFile: "The source is not a regular file."
        case .symbolicLinkUnsupported: "Symbolic links are not supported."
        case .fileChanged: "The file changed after preview."
        case .permissionDenied: "Permission was denied."
        case .crossDevice: "The source and target are on different volumes."
        case .journalWriteFailed: "The undo journal could not be written."
        case .journalReadFailed: "The undo journal could not be read."
        case .undoConflict: "Undo would overwrite or restore a changed file."
        case .renameFailed: "The file could not be renamed."
        }
    }
}

/// 文件身份。重命名前后应保持不变。
struct FileIdentity: Codable, Sendable, Equatable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64

    static func read(_ url: URL) throws -> FileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw posixError(errno, missingCode: .sourceMissing)
        }
        let fileType = info.st_mode & mode_t(S_IFMT)
        if fileType == mode_t(S_IFLNK) {
            throw FileRenameError(.symbolicLinkUnsupported, detail: url.lastPathComponent)
        }
        guard fileType == mode_t(S_IFREG) else {
            throw FileRenameError(.notRegularFile, detail: url.lastPathComponent)
        }
        return FileIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modificationSeconds: Int64(info.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec)
        )
    }
}

struct FileRenameCandidate: Codable, Sendable, Equatable {
    let candidateId: String
    let sourcePath: String
    let targetPath: String
    let identity: FileIdentity

    init(candidateId: String, sourceURL: URL, targetURL: URL, identity: FileIdentity) {
        self.candidateId = candidateId
        sourcePath = sourceURL.path
        targetPath = targetURL.path
        self.identity = identity
    }

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var targetURL: URL { URL(fileURLWithPath: targetPath) }
}

struct FileRenamePlan: Codable, Sendable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let runId: String
    let createdAtEpochSeconds: Int64
    let items: [FileRenameCandidate]

    init(runId: String, createdAtEpochSeconds: Int64, items: [FileRenameCandidate]) {
        schemaVersion = Self.schemaVersion
        self.runId = runId
        self.createdAtEpochSeconds = createdAtEpochSeconds
        self.items = items
    }
}

enum FileRenameItemStatus: String, Codable, Sendable, Equatable {
    case renamed
    case failed
    case alreadyOriginal
    case undone
}

struct FileRenameItemResult: Codable, Sendable, Equatable {
    let candidateId: String
    let originalName: String
    let targetName: String
    let status: FileRenameItemStatus
    let error: FileRenameError?
}

struct FileRenameRunResult: Codable, Sendable, Equatable {
    let runId: String
    let items: [FileRenameItemResult]

    var successCount: Int {
        items.count { $0.status == .renamed || $0.status == .undone || $0.status == .alreadyOriginal }
    }

    var failureCount: Int {
        items.count { $0.status == .failed }
    }
}

protocol FileRenameJournaling: Sendable {
    func save(_ plan: FileRenamePlan) throws
    func load(runId: String) throws -> FileRenamePlan
}

struct FileRenameJournalStore: FileRenameJournaling {
    let directory: URL

    init(directory: URL = AppPaths.renameUndoDirectory) {
        self.directory = directory
    }

    func save(_ plan: FileRenamePlan) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(plan)
            try data.write(to: fileURL(for: plan.runId), options: .atomic)
        } catch {
            throw FileRenameError(.journalWriteFailed, detail: error.localizedDescription)
        }
    }

    func load(runId: String) throws -> FileRenamePlan {
        do {
            let data = try Data(contentsOf: fileURL(for: runId))
            return try JSONDecoder().decode(FileRenamePlan.self, from: data)
        } catch {
            throw FileRenameError(.journalReadFailed, detail: error.localizedDescription)
        }
    }

    private func fileURL(for runId: String) -> URL {
        directory.appendingPathComponent("\(safeRunID(runId)).json")
    }
}

struct FileRenameService: Sendable {
    let journal: any FileRenameJournaling

    init(journal: any FileRenameJournaling = FileRenameJournalStore()) {
        self.journal = journal
    }

    func apply(_ plan: FileRenamePlan) throws -> FileRenameRunResult {
        guard !plan.items.isEmpty else {
            throw FileRenameError(.invalidPath, detail: "Empty rename plan")
        }
        guard Set(plan.items.map(\.candidateId)).count == plan.items.count else {
            throw FileRenameError(.invalidPath, detail: "Duplicate candidate ID")
        }
        try journal.save(plan)

        var results: [FileRenameItemResult] = []
        for item in plan.items {
            do {
                try Self.validate(item, requireExpectedIdentity: true)
                try Self.renameExclusive(from: item.sourceURL, to: item.targetURL)
                results.append(
                    FileRenameItemResult(
                        candidateId: item.candidateId,
                        originalName: item.sourceURL.lastPathComponent,
                        targetName: item.targetURL.lastPathComponent,
                        status: .renamed,
                        error: nil
                    )
                )
            } catch let error as FileRenameError {
                results.append(
                    FileRenameItemResult(
                        candidateId: item.candidateId,
                        originalName: item.sourceURL.lastPathComponent,
                        targetName: item.targetURL.lastPathComponent,
                        status: .failed,
                        error: error
                    )
                )
            } catch {
                results.append(
                    FileRenameItemResult(
                        candidateId: item.candidateId,
                        originalName: item.sourceURL.lastPathComponent,
                        targetName: item.targetURL.lastPathComponent,
                        status: .failed,
                        error: FileRenameError(.renameFailed, detail: error.localizedDescription)
                    )
                )
            }
        }
        return FileRenameRunResult(runId: plan.runId, items: results)
    }

    func undo(runId: String) throws -> FileRenameRunResult {
        let plan = try journal.load(runId: runId)
        var results: [FileRenameItemResult] = []

        for item in plan.items.reversed() {
            let originalURL = item.sourceURL
            let targetURL = item.targetURL
            do {
                if FileManager.default.fileExists(atPath: originalURL.path) {
                    let current = try FileIdentity.read(originalURL)
                    if current != item.identity {
                        throw FileRenameError(.undoConflict, detail: originalURL.lastPathComponent)
                    }
                    guard !FileManager.default.fileExists(atPath: targetURL.path) else {
                        throw FileRenameError(.undoConflict, detail: originalURL.lastPathComponent)
                    }
                    results.append(
                        FileRenameItemResult(
                            candidateId: item.candidateId,
                            originalName: originalURL.lastPathComponent,
                            targetName: targetURL.lastPathComponent,
                            status: .alreadyOriginal,
                            error: nil
                        )
                    )
                    continue
                }

                guard FileManager.default.fileExists(atPath: targetURL.path) else {
                    throw FileRenameError(.undoConflict, detail: targetURL.lastPathComponent)
                }
                let current = try FileIdentity.read(targetURL)
                guard current == item.identity else {
                    throw FileRenameError(.undoConflict, detail: targetURL.lastPathComponent)
                }
                try Self.renameExclusive(from: targetURL, to: originalURL)
                results.append(
                    FileRenameItemResult(
                        candidateId: item.candidateId,
                        originalName: originalURL.lastPathComponent,
                        targetName: targetURL.lastPathComponent,
                        status: .undone,
                        error: nil
                    )
                )
            } catch let error as FileRenameError {
                results.append(
                    FileRenameItemResult(
                        candidateId: item.candidateId,
                        originalName: originalURL.lastPathComponent,
                        targetName: targetURL.lastPathComponent,
                        status: .failed,
                        error: error
                    )
                )
            } catch {
                results.append(
                    FileRenameItemResult(
                        candidateId: item.candidateId,
                        originalName: originalURL.lastPathComponent,
                        targetName: targetURL.lastPathComponent,
                        status: .failed,
                        error: FileRenameError(.undoConflict, detail: error.localizedDescription)
                    )
                )
            }
        }
        return FileRenameRunResult(runId: runId, items: results)
    }

    static func capture(
        candidateId: String,
        sourceURL: URL,
        targetName: String
    ) throws -> FileRenameCandidate {
        let targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(targetName)
        let identity = try FileIdentity.read(sourceURL)
        return FileRenameCandidate(
            candidateId: candidateId,
            sourceURL: sourceURL,
            targetURL: targetURL,
            identity: identity
        )
    }

    private static func validate(
        _ item: FileRenameCandidate,
        requireExpectedIdentity: Bool
    ) throws {
        let source = item.sourceURL.standardizedFileURL
        let target = item.targetURL.standardizedFileURL
        guard source.lastPathComponent != ".", source.lastPathComponent != "..",
              target.lastPathComponent != ".", target.lastPathComponent != "..",
              !target.lastPathComponent.isEmpty
        else {
            throw FileRenameError(.invalidPath)
        }
        guard source.deletingLastPathComponent() == target.deletingLastPathComponent() else {
            throw FileRenameError(.crossDirectory)
        }
        guard source.pathExtension.caseInsensitiveCompare(target.pathExtension) == .orderedSame else {
            throw FileRenameError(.extensionChanged)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FileRenameError(.sourceMissing, detail: source.lastPathComponent)
        }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw FileRenameError(.targetExists, detail: target.lastPathComponent)
        }
        if requireExpectedIdentity {
            let current = try FileIdentity.read(source)
            guard current == item.identity else {
                throw FileRenameError(.fileChanged, detail: source.lastPathComponent)
            }
        }
    }

    private static func renameExclusive(from source: URL, to target: URL) throws {
        let result = source.path.withCString { oldPath in
            target.path.withCString { newPath in
                renameatx_np(
                    AT_FDCWD,
                    oldPath,
                    AT_FDCWD,
                    newPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw posixRenameError(errno)
        }
    }
}

private func safeRunID(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let filtered = value.unicodeScalars
        .filter { allowed.contains($0) }
        .map(String.init)
        .joined()
    return filtered.isEmpty ? UUID().uuidString : filtered
}

private func posixError(_ code: Int32, missingCode: FileRenameErrorCode) -> FileRenameError {
    if code == ENOENT { return FileRenameError(missingCode) }
    return posixRenameError(code)
}

private func posixRenameError(_ code: Int32) -> FileRenameError {
    switch code {
    case EEXIST: return FileRenameError(.targetExists)
    case ENOENT: return FileRenameError(.sourceMissing)
    case EACCES, EPERM: return FileRenameError(.permissionDenied)
    case EXDEV: return FileRenameError(.crossDevice)
    default: return FileRenameError(.renameFailed, detail: String(cString: strerror(code)))
    }
}
