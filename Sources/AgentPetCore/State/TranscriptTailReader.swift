import Foundation

struct TranscriptTail {
    static let noBytes = 0

    let bytes: Data
    let readStartOffset: Int
    let skippedByteCount: Int

    var wasTruncated: Bool {
        skippedByteCount > TranscriptTail.noBytes
    }
}

enum TranscriptTailReader {
    static let maximumReadByteCount = 64 * 1024 * 1024

    static func readUnscannedTail(path: String, scannedOffset: Int) -> TranscriptTail? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            let fileSize = Int(try handle.seekToEnd())
            let resumeOffset = fileSize < scannedOffset ? PetSession.initialTranscriptScanOffset : scannedOffset
            let skippedByteCount = max(TranscriptTail.noBytes, fileSize - resumeOffset - maximumReadByteCount)
            let readStartOffset = resumeOffset + skippedByteCount
            try handle.seek(toOffset: UInt64(readStartOffset))
            let bytes = try handle.read(upToCount: fileSize - readStartOffset) ?? Data()
            return TranscriptTail(bytes: bytes, readStartOffset: readStartOffset, skippedByteCount: skippedByteCount)
        } catch {
            return nil
        }
    }
}
