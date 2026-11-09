import Foundation

struct HeadTelemetryFrame: Codable {
    let source: String
    let instanceID: String
    let projectID: String
    let projectName: String
    let timestamp: Double
    let body: BodyMix
    let artic: HumanArtic
    let frame: HumanFrame?
    let voiceTelemetry: VoiceTelemetry
    let playing: Bool
    let active: Bool
    let beatStep: Int
    let beatPlaying: Bool
    let bodyScale: Double
    let engineRunning: Bool
    let renderedFrames: Int
    let whisperEnabled: Bool

    init(
        source: String,
        instanceID: String,
        projectID: String,
        projectName: String,
        timestamp: Double,
        body: BodyMix,
        artic: HumanArtic,
        frame: HumanFrame?,
        voiceTelemetry: VoiceTelemetry,
        playing: Bool,
        active: Bool,
        beatStep: Int,
        beatPlaying: Bool,
        bodyScale: Double,
        engineRunning: Bool,
        renderedFrames: Int,
        whisperEnabled: Bool
    ) {
        self.source = source
        self.instanceID = instanceID
        self.projectID = projectID
        self.projectName = projectName
        self.timestamp = timestamp
        self.body = body
        self.artic = artic
        self.frame = frame
        self.voiceTelemetry = voiceTelemetry
        self.playing = playing
        self.active = active
        self.beatStep = beatStep
        self.beatPlaying = beatPlaying
        self.bodyScale = bodyScale
        self.engineRunning = engineRunning
        self.renderedFrames = renderedFrames
        self.whisperEnabled = whisperEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        instanceID = try values.decode(String.self, forKey: .instanceID)
        projectID = try values.decode(String.self, forKey: .projectID)
        projectName = try values.decode(String.self, forKey: .projectName)
        timestamp = try values.decode(Double.self, forKey: .timestamp)
        body = try values.decode(BodyMix.self, forKey: .body)
        artic = try values.decode(HumanArtic.self, forKey: .artic)
        frame = try values.decodeIfPresent(HumanFrame.self, forKey: .frame)
        voiceTelemetry = try values.decode(VoiceTelemetry.self, forKey: .voiceTelemetry)
        playing = try values.decode(Bool.self, forKey: .playing)
        active = try values.decode(Bool.self, forKey: .active)
        beatStep = try values.decode(Int.self, forKey: .beatStep)
        beatPlaying = try values.decode(Bool.self, forKey: .beatPlaying)
        bodyScale = try values.decode(Double.self, forKey: .bodyScale)
        engineRunning = try values.decodeIfPresent(Bool.self, forKey: .engineRunning) ?? active
        renderedFrames = try values.decodeIfPresent(Int.self, forKey: .renderedFrames) ?? 0
        whisperEnabled = try values.decodeIfPresent(Bool.self, forKey: .whisperEnabled) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case source, instanceID, projectID, projectName, timestamp
        case body = "Body"
        case artic = "HumanArtic"
        case frame = "HumanFrame"
        case voiceTelemetry = "VoiceTelemetry"
        case playing, active, beatStep, beatPlaying, bodyScale, engineRunning, renderedFrames, whisperEnabled
    }
}
