import CoreGraphics
import Foundation

struct ClosedLidBrightnessRecoveryRecord: Codable, Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let brightness: Float
    let lidState: String
    let updatedAtEpochSeconds: Int64
}

protocol ClosedLidBrightnessRecoveryStoring: AnyObject {
    func load() -> ClosedLidBrightnessRecoveryRecord?
    func save(_ record: ClosedLidBrightnessRecoveryRecord) -> Bool
    func clear() -> Bool
}

/// Small atomic recovery journal for the experimental display path.
final class JSONClosedLidBrightnessRecoveryStore: ClosedLidBrightnessRecoveryStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> ClosedLidBrightnessRecoveryRecord? {
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(ClosedLidBrightnessRecoveryRecord.self, from: data),
              record.displayID != 0,
              record.brightness.isFinite,
              (0 ... 1).contains(record.brightness)
        else { return nil }
        return record
    }

    func save(_ record: ClosedLidBrightnessRecoveryRecord) -> Bool {
        guard record.displayID != 0,
              record.brightness.isFinite,
              (0 ... 1).contains(record.brightness)
        else { return false }

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func clear() -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return true }
        do {
            try fileManager.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }
}
