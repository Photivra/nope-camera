import Foundation
import NopeCore

/// The manifest nope. writes for one file, as the JSON manifest definition the C2PA library takes.
///
/// It says only what nope. knows to be true (AGENTS.md, "Honesty"; issue #1, "Signing"):
/// - one `c2pa.created` action, with the IPTC digital source type `digitalCapture` (the image
///   was captured from real life by a digital camera) and a plain description of what happened
///   to the file;
/// - who generated the claim: ``ClaimGenerator`` (Photivra Nope Camera and its version).
///
/// Privacy rule: no time (`when`), creator, location, device, title, thumbnail or ingredient is
/// written, and the instance ID is a random UUID made for this file alone
/// (docs/PRIVACY.md, "Content Credentials").
struct ContentCredentialsManifest: Encodable, Equatable {
    /// The IPTC digital source type for a photo captured from real life by a digital camera.
    ///
    /// From the IPTC Digital Source Type vocabulary:
    /// <https://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture>.
    static let digitalCapture = "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"

    /// The `c2pa.actions.v2` assertion label (C2PA 2.2, §18.15).
    static let actionsLabel = "c2pa.actions.v2"

    /// The `c2pa.created` action (C2PA 2.2, §18.15.4.1).
    static let createdAction = "c2pa.created"

    /// The claim generator, in the library's `claim_generator_info` form.
    struct GeneratorInfo: Encodable, Equatable {
        /// The generator's name.
        let name: String
        /// The generator's version.
        let version: String

        /// Creates the generator information.
        ///
        /// - Parameters:
        ///   - name: The generator's name.
        ///   - version: The generator's version.
        init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    /// One action in the actions assertion.
    struct Action: Encodable, Equatable {
        /// The action's label, `c2pa.created`.
        let action: String
        /// The IPTC digital source type URI.
        let digitalSourceType: String
        /// The plain-English description of what happened to the file.
        let description: String

        /// Creates an action.
        ///
        /// - Parameters:
        ///   - action: The action's label.
        ///   - digitalSourceType: The IPTC digital source type URI.
        ///   - description: What happened to the file.
        init(action: String, digitalSourceType: String, description: String) {
            self.action = action
            self.digitalSourceType = digitalSourceType
            self.description = description
        }
    }

    /// The actions assertion's data.
    struct Actions: Encodable, Equatable {
        /// The actions, in order.
        let actions: [Action]

        /// Creates the assertion's data.
        ///
        /// - Parameter actions: The actions, in order.
        init(actions: [Action]) {
            self.actions = actions
        }
    }

    /// One assertion in the manifest definition.
    struct Assertion: Encodable, Equatable {
        /// The assertion label.
        let label: String
        /// The assertion's data.
        let data: Actions

        /// Creates an assertion.
        ///
        /// - Parameters:
        ///   - label: The assertion label.
        ///   - data: The assertion's data.
        init(label: String, data: Actions) {
            self.label = label
            self.data = data
        }
    }

    /// The claim version: 2, the current version (C2PA 2.2, §10.2).
    let claimVersion = 2

    /// The file's media type.
    let format: String

    /// A random instance ID for this file alone, `xmp:iid:` followed by a UUID.
    let instanceID: String

    /// Photivra Nope Camera and its version.
    let claimGeneratorInfo: [GeneratorInfo]

    /// The single actions assertion.
    let assertions: [Assertion]

    /// The JSON keys the C2PA library's manifest definition uses.
    enum CodingKeys: String, CodingKey {
        /// `claim_version`.
        case claimVersion = "claim_version"
        /// `format`.
        case format
        /// `instance_id`.
        case instanceID = "instance_id"
        /// `claim_generator_info`.
        case claimGeneratorInfo = "claim_generator_info"
        /// `assertions`.
        case assertions
    }

    /// Creates the manifest for one file.
    ///
    /// - Parameters:
    ///   - file: What the file is.
    ///   - generator: Photivra Nope Camera and its version.
    ///   - instanceID: A UUID made for this file alone.
    init(file: SignableFile, generator: ClaimGenerator, instanceID: UUID) {
        self.format = file.mediaType
        self.instanceID = "xmp:iid:\(instanceID.uuidString.lowercased())"
        self.claimGeneratorInfo = [GeneratorInfo(name: generator.name, version: generator.version)]
        self.assertions = [
            Assertion(
                label: Self.actionsLabel,
                data: Actions(actions: [
                    Action(
                        action: Self.createdAction, digitalSourceType: Self.digitalCapture,
                        description: Self.description(of: file))
                ]))
        ]
    }

    /// The description of what happened to a file, in the manifest's own words.
    ///
    /// The manifest is part of the file, not the interface, so this English text isn't localized.
    /// It claims no more than nope. does: "as little processing as the phone allows", never "no
    /// processing".
    ///
    /// - Parameter file: What the file is.
    /// - Returns: One or two plain sentences.
    static func description(of file: SignableFile) -> String {
        switch file {
        case .singleFrameRAW:
            "Captured by Photivra Nope Camera as a single frame of RAW sensor data, with as little "
                + "processing as the phone allows."
        case .developedHEIF, .developedJPEG:
            "Developed by Photivra Nope Camera on the phone from a single frame of RAW sensor data."
        case .deviceProcessedHEIF, .deviceProcessedJPEG:
            "Captured by Photivra Nope Camera and processed by the phone's camera, because this lens "
                + "can't save RAW."
        }
    }

    /// The manifest as JSON, for `Builder(context:manifestJSON:)`.
    ///
    /// - Returns: The JSON text, with sorted keys.
    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Encoding these plain strings and integers can't fail.
        let data = try! encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
