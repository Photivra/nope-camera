// A minimal program that links NopeSigning the way the app does (statically, with dead-code
// stripping) and calls its signer and the C2PA reader path, so the linked binary contains
// everything signing can reach. CI builds it for iOS and runs scripts/check-no-networking.sh on
// it (c2pa-lib/README.md, "Proving there is no networking code"). It is never shipped or run.
import Foundation
import NopeCore
import NopeSigning

let signer = ContentCredentialsSigner(keyProvider: platformKeyProvider(), generator: ClaimGenerator(version: "0"))
let input = FileHandle.standardInput.readDataToEndOfFile()
let semaphore = DispatchSemaphore(value: 0)
Task {
    for format in PhotoFormat.allCases {
        for isProcessedByDevice in [false, true] {
            _ = try? await signer.sign(PhotoFile(format: format, data: input, isProcessedByDevice: isProcessedByDevice))
        }
    }
    semaphore.signal()
}
semaphore.wait()
