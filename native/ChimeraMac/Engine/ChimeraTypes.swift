import Foundation

struct ChimeraError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct BodyMix: Codable, Equatable {
    var female: Double
    var child: Double

    static let male = BodyMix(female: 0, child: 0)
    static let female = BodyMix(female: 1, child: 0)
    static let child = BodyMix(female: 0, child: 1)
}

struct HumanArtic: Codable, Equatable {
    var jaw: Double
    var tbX: Double
    var tbY: Double
    var ttX: Double
    var ttY: Double
    var ttCurl: Double
    var root: Double
    var lipAp: Double
    var lipProt: Double
    var lipWidth: Double
    var labiodental: Double
    var velum: Double
    var larynx: Double
    var epilarynx: Double
    var ventricular: Double
    var lateral: Double
    var dorsum: Double

    static let zero = HumanArtic(
        jaw: 0, tbX: 0, tbY: 0, ttX: 0, ttY: 0, ttCurl: 0, root: 0,
        lipAp: 0, lipProt: 0, lipWidth: 0, labiodental: 0, velum: 0,
        larynx: 0, epilarynx: 0, ventricular: 0, lateral: 0, dorsum: 0
    )

    init(jaw: Double, tbX: Double, tbY: Double, ttX: Double, ttY: Double, ttCurl: Double, root: Double, lipAp: Double, lipProt: Double, lipWidth: Double, labiodental: Double, velum: Double, larynx: Double, epilarynx: Double, ventricular: Double, lateral: Double, dorsum: Double) {
        self.jaw = jaw
        self.tbX = tbX
        self.tbY = tbY
        self.ttX = ttX
        self.ttY = ttY
        self.ttCurl = ttCurl
        self.root = root
        self.lipAp = lipAp
        self.lipProt = lipProt
        self.lipWidth = lipWidth
        self.labiodental = labiodental
        self.velum = velum
        self.larynx = larynx
        self.epilarynx = epilarynx
        self.ventricular = ventricular
        self.lateral = lateral
        self.dorsum = dorsum
    }

    init(values: [Double], fallback: HumanArtic = .zero) {
        self = fallback
        guard values.count >= 17 else { return }
        jaw = values[0]
        tbX = values[1]
        tbY = values[2]
        ttX = values[3]
        ttY = values[4]
        ttCurl = values[5]
        root = values[6]
        lipAp = values[7]
        lipProt = values[8]
        lipWidth = values[9]
        labiodental = values[10]
        velum = values[11]
        larynx = values[12]
        epilarynx = values[13]
        ventricular = values[14]
        lateral = values[15]
        dorsum = values[16]
    }

    var values: [Double] {
        [jaw, tbX, tbY, ttX, ttY, ttCurl, root, lipAp, lipProt, lipWidth, labiodental, velum, larynx, epilarynx, ventricular, lateral, dorsum]
    }
}

struct VoiceSource: Codable {
    var f0: Double
    var glide: Double
    var pressure: Double
    var breathiness: Double
    var tension: Double
    var fry: Double
    var roughness: Double
    var vibratoDepth: Double
    var vibratoRate: Double
    var drift: Double
    var voiced: Bool
    var brightness: Double

    static let placeholder = VoiceSource(f0: 110, glide: 0, pressure: 1, breathiness: 0, tension: 0, fry: 0, roughness: 0, vibratoDepth: 0, vibratoRate: 5, drift: 0, voiced: true, brightness: 0.25)

    var patchValues: [Double] {
        [f0, glide, pressure, breathiness, tension, fry, roughness, vibratoDepth, vibratoRate, drift, voiced ? 1 : 0, brightness]
    }
}

struct ArticSpec: Decodable {
    let min: Double
    let max: Double
    let hz: Double
}

struct VowelReference: Decodable {
    let ipa: String
    let example: String
}

struct VowelTarget: Decodable {
    let artic: [String: Double]
    let formants: [Double]
}

struct VoiceCatalog: Decodable {
    let neutral: HumanArtic
    let articKeys: [String]
    let articSpecs: [String: ArticSpec]
    let defaultSource: VoiceSource
    let bassNote: Double
    let beatSounds: [BeatSound]
    let beatPresets: [BeatPreset]
    let vowelTargets: [String: [String: VowelTarget]]
    let vowels: [VowelReference]
    let demoSongs: [DemoSong]
    let creatures: [CreatureDefinition]
}

struct BeatSound: Decodable, Identifiable {
    let id: String
    let name: String
    let role: String
    let hint: String
}

struct BeatPreset: Decodable, Identifiable {
    let name: String
    let bpm: Double
    let swing: Double
    let text: String

    var id: String { name }
}

struct BeatStep: Codable, Equatable {
    let id: String
    let note: Double?
    let accent: Double?
}

struct ParamDef: Decodable, Identifiable {
    let key: String
    let label: String
    let min: Double
    let max: Double
    let defaultValue: Double
    let unit: String?
    let role: String?
    let digits: Int?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, min, max, unit, role, digits
        case defaultValue = "default"
    }
}

struct CallDef: Decodable, Identifiable {
    let id: String
    let name: String
    let hint: String
}

struct CreatureDefinition: Decodable, Identifiable {
    let id: String
    let name: String
    let latin: String
    let blurb: String
    let role: String
    let params: [ParamDef]
    let calls: [CallDef]
}

struct DemoSong: Codable, Identifiable {
    let name: String
    let bpm: Double
    let lyrics: String
    let notes: [[Double]]
    let octave: [String: Double]

    var id: String { name }
}

struct SingNote: Codable, Equatable, Identifiable {
    var id: UUID
    var midi: Int
    var start: Double
    var duration: Double
    var lyric: String
    var syllable: Syllable?

    init(id: UUID = UUID(), midi: Int = 60, start: Double = 0, duration: Double = 1, lyric: String = "", syllable: Syllable? = nil) {
        self.id = id
        self.midi = midi
        self.start = start
        self.duration = duration
        self.lyric = lyric
        self.syllable = syllable
    }

    static func == (lhs: SingNote, rhs: SingNote) -> Bool {
        lhs.id == rhs.id && lhs.midi == rhs.midi && lhs.start == rhs.start && lhs.duration == rhs.duration && lhs.lyric == rhs.lyric
    }
}

struct Segment: Codable {
    let ipa: String
    let dur: Double?
    let stress: Double?
    let f0: Double?
    let wordEnd: Bool?
}

struct Phrase: Codable {
    let segments: [Segment]
    let intonation: String
    let pause: Double
    let words: [String]
}

struct Gesture: Codable {
    let t0: Double
    let t1: Double
    let rampIn: Double
    let rampOut: Double
    let strength: Double
    let targets: [String: Double]
    let speed: Double?
    let releaseHold: Double?
    let tag: Double?
    let label: String?
}

struct PlannedSegment: Codable {
    let ipa: String
    let t0: Double
    let t1: Double
    let kind: String
}

struct Plan: Decodable {
    let gestures: [Gesture]
    let segments: [PlannedSegment]
    let end: Double
}

struct Syllable: Codable {
    let text: String
    let onset: [Segment]
    let nucleus: Segment
    let coda: [Segment]
    let melisma: Bool?
    let wordEnd: Bool
    let phraseEnd: Bool
}

struct Vec2: Codable {
    let x: Double
    let y: Double
}

struct GridSample: Codable {
    let inner: Vec2
    let outer: Vec2
    let mid: Vec2
    let d: Double
    let s: Double
    let area: Double
}

struct HumanFrame: Codable {
    let outer: [Vec2]
    let inner: [Vec2]
    let tongue: [Vec2]
    let velum: [Vec2]
    let upperLip: [Vec2]
    let lowerLip: [Vec2]
    let upperTeeth: [Vec2]
    let lowerTeeth: [Vec2]
    let jawBone: [Vec2]
    let epiglottis: [Vec2]
    let nasalCavity: [Vec2]
    let glottis: Vec2
    let tip: Vec2
    let grid: [GridSample]
    let length: Double
    let pharynxLength: Double
    let teethS: Double
    let lipS: Double
    let velumPort: Double
}

struct HumanBody: Decodable {
    let scale: Double
    let pharynx: Double
}

struct AirwayModel: Decodable {
    let model: Int
    let body: HumanBody
    let nPh: Int
    let nOr: Int
}

struct Transfer: Decodable {
    let freqs: [Double]
    let db: [Double]
    let formants: [Double]
}

struct CreatureInfo: Decodable {
    struct Tube: Decodable {
        let name: String
        let n: Int
    }

    let id: String
    let params: [String]
    let calls: [String]
    let tubes: [Tube]
    let sources: [String]
}

struct VoiceTelemetry: Codable {
    var artic: [Double] = []
    var phAreas: [Double] = []
    var orAreas: [Double] = []
    var pressure: [Double] = []
    var flow: [Double] = []
    var glottalArea: [Double] = []
    var glottalFlow: [Double] = []
    var phLen: Double = 0
    var orLen: Double = 0
    var velumPort: Double = 0
    var f0: Double = 0
    var voicing: Double = 0
    var lungPressure: Double = 0
    var outRMS: Double = 0
    var gate: Double = 0
    var clock: Double = 0
}

struct CreatureTubeTelemetry {
    let name: String
    let areas: [Double]
    let rms: [Double]
}

struct CreatureTelemetry {
    var gate: Double = 0
    var outRMS: Double = 0
    var clock: Double = 0
    var call: Int = -1
    var params: [Double] = []
    var tubes: [CreatureTubeTelemetry] = []
}
