// FlyGymBridge.swift — localhost TCP bridge between the Metal brain and a
// Python FlyGym body. Swift is the CLIENT, Python `bridge.py` is the SERVER.
//
// Design constraints (see docs/plans/PLAN_FLYGYM.md):
// - The Metal brain stays authoritative at 1 kHz. Only compact population
//   signals cross the process boundary (~50-100 Hz BrainSignals).
// - Socket I/O NEVER runs on the render thread. A sender thread ships the
//   latest BrainSignals; a receiver thread parses body feedback. Bounded
//   buffers everywhere (latest-packet-wins); disconnect never crashes the sim.
// - Body->brain mapping is a MODELING ASSUMPTION, centralized in
//   FlyGymSensoryMap, reusing the existing ascend/sens input paths.

import Foundation
import Darwin

// MARK: - Packets (mirror flygym_bridge/protocol.py)

/// Brain -> body. Compact population readout, ~50-100 Hz.
struct FlyGymBrainPacket: Codable {
    var type: String = "brain"
    var t: Double = 0            // sim seconds
    var walk: Double = 0         // walkDrive 0..1.3
    var turn: Double = 0         // turnBias -1..1
    var escape: Bool = false
    var backward: Bool = false
    var groom: Double = 0
    var wing: Double = 0
    var arousal: Double = 0
    var tempo: Double = 1
    var sleep: Bool = false
    var nervous: Double = 0

    init(signals: BrainSignals, simMs: Int) {
        t = Double(simMs) / 1000.0
        walk = Double(signals.walkDrive)
        turn = Double(signals.turnBias)
        escape = signals.escape
        backward = signals.backward
        groom = Double(signals.groomDrive)
        wing = Double(signals.wingDrive)
        arousal = Double(signals.arousal)
        tempo = Double(signals.tempo)
        sleep = signals.sleep
        nervous = Double(signals.nervous)
    }
    init() {}
}

/// Body -> brain. Tolerant parse: unknown fields ignored, missing fields get
/// defaults, out-of-range values clamped. Never throws out of the bridge.
struct FlyGymBodyPacket: Decodable {
    var t: Double = 0
    var simDt: Double = 0
    var wallDt: Double = 0
    var simWallRatio: Double = 0
    var controllerLeft: Double = 0
    var controllerRight: Double = 0
    var windStrength: Double = 0
    var windDirectionDeg: Double = 0
    var windSensory: Bool = false
    var touchStrength: Double = 0
    var touchSensory: Bool = false
    var vx: Double = 0           // forward velocity m/s
    var yawRate: Double = 0      // rad/s
    var contacts: [Double] = [0, 0, 0, 0, 0, 0]
    var leftContact: Double = 0
    var rightContact: Double = 0
    var gaitPhase: Double?       // optional 0..1
    var loomLeft: Double = 0
    var loomRight: Double = 0
    var brightness: Double = 0
    var brightnessLeft: Double = 0
    var brightnessRight: Double = 0
    var occupancyLeft: Double = 0
    var occupancyRight: Double = 0
    var opticExpansionLeft: Double = 0
    var opticExpansionRight: Double = 0
    var flashLeft: Double = 0
    var flashRight: Double = 0
    var odorLeft: Double = 0
    var odorRight: Double = 0
    var nearestFoodDistanceMm: Double?
    var headingRad: Double = 0
    var bearing: Double = 0

    enum Keys: String, CodingKey {
        case type, t, vx, yawRate = "yaw_rate", contacts
        case simDt = "sim_dt", wallDt = "wall_dt", simWallRatio = "sim_wall_ratio"
        case controllerLeft = "controller_left", controllerRight = "controller_right"
        case windStrength = "wind_strength", windDirectionDeg = "wind_direction_deg"
        case windSensory = "wind_sensory", touchStrength = "touch_strength", touchSensory = "touch_sensory"
        case leftContact = "left_contact", rightContact = "right_contact"
        case gaitPhase = "gait_phase"
        case loomLeft = "loom_left", loomRight = "loom_right", brightness, bearing
        case brightnessLeft = "brightness_left", brightnessRight = "brightness_right"
        case occupancyLeft = "occupancy_left", occupancyRight = "occupancy_right"
        case opticExpansionLeft = "optic_expansion_left", opticExpansionRight = "optic_expansion_right"
        case flashLeft = "flash_left", flashRight = "flash_right"
        case odorLeft = "odor_left", odorRight = "odor_right"
        case nearestFoodDistanceMm = "nearest_food_distance_mm"
        case headingRad = "heading_rad"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let tRaw = (try? c.decodeIfPresent(Double.self, forKey: .t)) ?? 0
        t = tRaw.isFinite ? max(0, tRaw) : 0
        let simDtRaw = (try? c.decodeIfPresent(Double.self, forKey: .simDt)) ?? 0
        simDt = simDtRaw.isFinite ? max(0, min(10, simDtRaw)) : 0
        let wallDtRaw = (try? c.decodeIfPresent(Double.self, forKey: .wallDt)) ?? 0
        wallDt = wallDtRaw.isFinite ? max(0, min(10, wallDtRaw)) : 0
        let ratioRaw = (try? c.decodeIfPresent(Double.self, forKey: .simWallRatio)) ?? 0
        simWallRatio = ratioRaw.isFinite ? max(0, min(1000, ratioRaw)) : 0
        let ctlLRaw = (try? c.decodeIfPresent(Double.self, forKey: .controllerLeft)) ?? 0
        controllerLeft = ctlLRaw.isFinite ? max(-2, min(2, ctlLRaw)) : 0
        let ctlRRaw = (try? c.decodeIfPresent(Double.self, forKey: .controllerRight)) ?? 0
        controllerRight = ctlRRaw.isFinite ? max(-2, min(2, ctlRRaw)) : 0
        let windRaw = (try? c.decodeIfPresent(Double.self, forKey: .windStrength)) ?? 0
        windStrength = windRaw.isFinite ? max(0, min(1, windRaw)) : 0
        let windDirRaw = (try? c.decodeIfPresent(Double.self, forKey: .windDirectionDeg)) ?? 0
        windDirectionDeg = windDirRaw.isFinite ? windDirRaw.truncatingRemainder(dividingBy: 360) : 0
        windSensory = (try? c.decodeIfPresent(Bool.self, forKey: .windSensory)) ?? false
        let touchRaw = (try? c.decodeIfPresent(Double.self, forKey: .touchStrength)) ?? 0
        touchStrength = touchRaw.isFinite ? max(0, min(1, touchRaw)) : 0
        touchSensory = (try? c.decodeIfPresent(Bool.self, forKey: .touchSensory)) ?? false
        let vxRaw = (try? c.decodeIfPresent(Double.self, forKey: .vx)) ?? 0
        vx = min(2.0, max(-2.0, vxRaw))
        let yawRaw = (try? c.decodeIfPresent(Double.self, forKey: .yawRate)) ?? 0
        yawRate = min(20.0, max(-20.0, yawRaw))
        var cc = (try? c.decodeIfPresent([Double].self, forKey: .contacts)) ?? []
        cc = cc.map { min(1.0, max(0.0, $0)) }
        while cc.count < 6 { cc.append(0) }
        contacts = Array(cc.prefix(6))
        let l = (try? c.decodeIfPresent(Double.self, forKey: .leftContact)) ?? 0
        leftContact = min(1.0, max(0.0, l))
        let rr = (try? c.decodeIfPresent(Double.self, forKey: .rightContact)) ?? 0
        rightContact = min(1.0, max(0.0, rr))
        if let g = (try? c.decodeIfPresent(Double.self, forKey: .gaitPhase)) ?? nil {
            gaitPhase = min(1.0, max(0.0, g))
        } else { gaitPhase = nil }
        loomLeft = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .loomLeft)) ?? 0))
        loomRight = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .loomRight)) ?? 0))
        brightness = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .brightness)) ?? 0))
        brightnessLeft = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .brightnessLeft)) ?? brightness))
        brightnessRight = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .brightnessRight)) ?? brightness))
        occupancyLeft = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .occupancyLeft)) ?? 0))
        occupancyRight = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .occupancyRight)) ?? 0))
        opticExpansionLeft = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .opticExpansionLeft)) ?? 0))
        opticExpansionRight = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .opticExpansionRight)) ?? 0))
        flashLeft = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .flashLeft)) ?? 0))
        flashRight = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .flashRight)) ?? 0))
        odorLeft = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .odorLeft)) ?? 0))
        odorRight = min(1.0, max(0.0, (try? c.decodeIfPresent(Double.self, forKey: .odorRight)) ?? 0))
        if let d = (try? c.decodeIfPresent(Double.self, forKey: .nearestFoodDistanceMm)) ?? nil,
           d.isFinite {
            nearestFoodDistanceMm = min(1_000_000.0, max(0.0, d))
        } else { nearestFoodDistanceMm = nil }
        let headingRaw = (try? c.decodeIfPresent(Double.self, forKey: .headingRad)) ?? 0
        headingRad = headingRaw.isFinite ? min(Double.pi, max(-Double.pi, headingRaw)) : 0
        bearing = min(1.0, max(-1.0, (try? c.decodeIfPresent(Double.self, forKey: .bearing)) ?? 0))
    }
}

private struct FlyGymTaggedLine: Decodable { var type: String = "" }

/// Type-gated body parser: rejects malformed JSON AND wrong-type lines.
/// Single choke point used by recvLoop and --bridgetest.
func parseBodyLine(_ line: Data) -> FlyGymBodyPacket? {
    guard let tag = try? JSONDecoder().decode(FlyGymTaggedLine.self, from: line),
          tag.type == "body",
          let pkt = try? JSONDecoder().decode(FlyGymBodyPacket.self, from: line) else { return nil }
    return pkt
}

func parseLabStateLine(_ line: Data) -> LabRemoteState? {
    guard let tag = try? JSONDecoder().decode(FlyGymTaggedLine.self, from: line),
          tag.type == "lab_state" else { return nil }
    return try? JSONDecoder().decode(LabRemoteState.self, from: line)
}

func parseLabAckLine(_ line: Data) -> LabAck? {
    guard let tag = try? JSONDecoder().decode(FlyGymTaggedLine.self, from: line),
          tag.type == "lab_ack" else { return nil }
    return try? JSONDecoder().decode(LabAck.self, from: line)
}

func parseLabEventLine(_ line: Data) -> LabEventNotice? {
    guard let tag = try? JSONDecoder().decode(FlyGymTaggedLine.self, from: line),
          tag.type == "lab_event" else { return nil }
    return try? JSONDecoder().decode(LabEventNotice.self, from: line)
}

struct FlyGymBodyFeedback: FlyGymStampedPacket {
    /// MuJoCo/FlyGym simulation time in seconds from the body packet.
    var simTime: Double = 0
    /// MuJoCo simulation seconds advanced since the previous body packet.
    var simDt: Double = 0
    var wallDt: Double = 0
    /// `simDt / wallDt`, reported by Python. Values below 1 mean time dilation.
    var simWallRatio: Double = 0
    var controllerLeft: Double = 0
    var controllerRight: Double = 0
    var windStrength: Double = 0
    var windDirectionDeg: Double = 0
    var windSensory: Bool = false
    var touchStrength: Double = 0
    var touchSensory: Bool = false
    var vx: Double = 0
    var yawRate: Double = 0
    var contacts: [Double] = [0, 0, 0, 0, 0, 0]
    var leftContact: Double = 0
    var rightContact: Double = 0
    var gaitPhase: Double?
    var loomLeft: Double = 0
    var loomRight: Double = 0
    var brightness: Double = 0
    var brightnessLeft: Double = 0
    var brightnessRight: Double = 0
    var occupancyLeft: Double = 0
    var occupancyRight: Double = 0
    var opticExpansionLeft: Double = 0
    var opticExpansionRight: Double = 0
    var flashLeft: Double = 0
    var flashRight: Double = 0
    var odorLeft: Double = 0
    var odorRight: Double = 0
    var nearestFoodDistanceMm: Double?
    var headingRad: Double = 0
    var bearing: Double = 0
    var receivedAt: Date = Date()
    var connectionGeneration: UInt64 = 0
    var contactMean: Double { contacts.reduce(0, +) / 6.0 }
    init(_ p: FlyGymBodyPacket) {
        simTime = p.t
        simDt = p.simDt; wallDt = p.wallDt; simWallRatio = p.simWallRatio
        controllerLeft = p.controllerLeft; controllerRight = p.controllerRight
        windStrength = p.windStrength; windDirectionDeg = p.windDirectionDeg
        windSensory = p.windSensory
        touchStrength = p.touchStrength; touchSensory = p.touchSensory
        vx = p.vx; yawRate = p.yawRate; contacts = p.contacts
        leftContact = p.leftContact; rightContact = p.rightContact
        gaitPhase = p.gaitPhase
        loomLeft = p.loomLeft; loomRight = p.loomRight
        brightness = p.brightness; brightnessLeft = p.brightnessLeft; brightnessRight = p.brightnessRight
        occupancyLeft = p.occupancyLeft; occupancyRight = p.occupancyRight
        opticExpansionLeft = p.opticExpansionLeft; opticExpansionRight = p.opticExpansionRight
        flashLeft = p.flashLeft; flashRight = p.flashRight
        odorLeft = p.odorLeft; odorRight = p.odorRight
        nearestFoodDistanceMm = p.nearestFoodDistanceMm
        headingRad = p.headingRad; bearing = p.bearing
    }
    init() {}
}

// MARK: - Body -> brain mapping (MODELING ASSUMPTION)

/// Centralized mapping from compact MuJoCo body state into the sim's existing
/// ascending/sensory drive inputs. The connectome wiring downstream is real;
/// THIS mapping (contact/vx -> gaitDrive) is an engineering assumption.
/// Reuses the existing gait/proprioception path (`ascendDrive`), never invents
/// new neuron populations.
enum FlyGymSensoryMap {
    /// Movement-derived walking drive 0..1. Ground-contact occupancy is kept as
    /// telemetry only: a fly standing on six feet must not look like it is walking.
    static func bodyDrive(_ fb: FlyGymBodyFeedback) -> Float {
        let speedTerm = min(1.0, abs(fb.vx) / 0.03)       // 0.03 m/s ~= brisk walk
        let turnTerm = min(1.0, abs(fb.yawRate) / 4.0)    // turning in place is still locomotion
        let d = max(speedTerm, turnTerm)
        return Float(min(1.0, max(0.0, d)))
    }
    /// Fresh real-body data is authoritative. The procedural desktop fly is only
    /// a fallback when body feedback is absent/stale; it is never blended into a
    /// live FlyGym experiment.
    static func gaitDrive(procedural: Float, body: FlyGymBodyFeedback?, maxAge: TimeInterval = 0.5) -> Float {
        guard let b = body, Date().timeIntervalSince(b.receivedAt) < maxAge else { return procedural }
        return bodyDrive(b)
    }
    static func gaitPhase(procedural: Float, body: FlyGymBodyFeedback?, maxAge: TimeInterval = 0.5) -> Float {
        guard let b = body, let g = b.gaitPhase,
              Date().timeIntervalSince(b.receivedAt) < maxAge else { return procedural }
        return Float(g)
    }
    /// FlyGym visual looming feeds ONLY the existing LC4/LPLC2 external input.
    /// The visual decoder on the Python side is a modeling assumption; escape
    /// still requires the real downstream connectome/GF to spike.
    static func looming(body: FlyGymBodyFeedback?, maxAge: TimeInterval = 0.5) -> (l: Float, r: Float) {
        guard let b = body, Date().timeIntervalSince(b.receivedAt) < maxAge else { return (0, 0) }
        return (Float(b.loomLeft), Float(b.loomRight))
    }

    /// Modeled food odor from Python LabWorld.  These values are geometry-derived
    /// sensory-model scalars, not behavior commands.  The Coordinator maps them
    /// into real ORN_DM1/ORN_VA2 neurons; stale packets must clear the drive.
    static func foodOdor(body: FlyGymBodyFeedback?, maxAge: TimeInterval = 0.5) -> (l: Float, r: Float) {
        guard let b = body, Date().timeIntervalSince(b.receivedAt) < maxAge else { return (0, 0) }
        return (Float(b.odorLeft), Float(b.odorRight))
    }

    /// Body heading is world-frame yaw from the real MuJoCo thorax. It is kept
    /// separate from `bearing`, which is strictly the visual occupancy bearing.
    static func heading(body: FlyGymBodyFeedback?, maxAge: TimeInterval = 0.5) -> Double? {
        guard let b = body, Date().timeIntervalSince(b.receivedAt) < maxAge else { return nil }
        return b.headingRad
    }
}

/// Public packet-health snapshot for LabUI/diagnostics. The packet generation is
/// separate from the current connection generation so stale cross-reconnect data
/// is visible instead of silently looking current.
struct FlyGymPacketFreshness {
    var connected: Bool
    var currentGeneration: UInt64
    var packetGeneration: UInt64?
    var ageSeconds: TimeInterval?
    var isFresh: Bool
}

fileprivate enum FlyGymSendLane: Int {
    case brain = 0
    case escape = 1
    case lab = 2
}

fileprivate struct FlyGymPendingSend {
    var lane: FlyGymSendLane
    var data: Data
}

// MARK: - TCP client (POSIX, background threads only)

final class FlyGymBridge {
    let host: String
    let port: UInt16
    /// Minimum interval between brain packets on the wire (~66 Hz cap).
    var minSendInterval: TimeInterval = 0.0125
    /// A queued lab burst may use the shared wire between brain packets, but a
    /// normal latest-state brain packet becomes mandatory before this age.
    var maxNormalBrainGap: TimeInterval = 0.075

    static let bodyFreshMaxAge: TimeInterval = 0.5
    static let labStateFreshMaxAge: TimeInterval = 1.5
    static let labDiscreteFreshMaxAge: TimeInterval = 5.0

    private let lock = NSLock()
    private var running = false
    private var sock: Int32 = -1
    private var _connected = false
    private var _connectionGeneration: UInt64 = 0
    private var pending: Data?          // latest unsent brain line (bounded: 1)
    private var pendingEscape: Data?    // bounded pulse lane: escape cannot be coalesced away
    private var pendingLab: [Data] = [] // ordered lab commands (bounded FIFO, cap 32)
    private let labQueueCap = 32
    private var pendingCount = 0        // packets coalesced since last send
    private var droppedCoalesced: Int = 0
    private var droppedLab: Int = 0
    private var _latestBody: FlyGymBodyFeedback?
    private var _latestLabState: LabRemoteState?
    private var _latestLabAck: LabAck?
    private var _latestLabEvent: LabEventNotice?
    private var nextLabID = 1
    private var lastSend = Date.distantPast
    private var lastNormalBrainSendAt = Date.distantPast
    private var lastBodyAt: Date?
    private var bodyIntervals: [TimeInterval] = []   // bounded ring (cap 120)
    private(set) var sentCount = 0
    private(set) var recvCount = 0
    private(set) var malformedCount = 0
    private(set) var connectAttempts = 0
    private(set) var labSentCount = 0
    private(set) var labRecvCount = 0

    init(host: String = "127.0.0.1", port: UInt16 = 17841) {
        self.host = host; self.port = port
    }

    var connected: Bool { lock.lock(); defer { lock.unlock() }; return _connected }
    var connectionGeneration: UInt64 { lock.lock(); defer { lock.unlock() }; return _connectionGeneration }
    var coalescedDropped: Int { lock.lock(); defer { lock.unlock() }; return droppedCoalesced }
    var labDropped: Int { lock.lock(); defer { lock.unlock() }; return droppedLab }

    private func freshnessLocked(receivedAt: Date?, packetGeneration: UInt64?,
                                 maxAge: TimeInterval, now: Date = Date()) -> FlyGymPacketFreshness {
        let age = receivedAt.map { max(0, now.timeIntervalSince($0)) }
        let sameGeneration = packetGeneration == _connectionGeneration
        let fresh = _connected && sameGeneration && (age.map { $0 < maxAge } ?? false)
        return FlyGymPacketFreshness(connected: _connected,
                                     currentGeneration: _connectionGeneration,
                                     packetGeneration: packetGeneration,
                                     ageSeconds: age,
                                     isFresh: fresh)
    }

    func bodyFreshness(maxAge: TimeInterval = FlyGymBridge.bodyFreshMaxAge) -> FlyGymPacketFreshness {
        lock.lock(); defer { lock.unlock() }
        return freshnessLocked(receivedAt: _latestBody?.receivedAt,
                               packetGeneration: _latestBody?.connectionGeneration,
                               maxAge: maxAge)
    }

    func labStateFreshness(maxAge: TimeInterval = FlyGymBridge.labStateFreshMaxAge) -> FlyGymPacketFreshness {
        lock.lock(); defer { lock.unlock() }
        return freshnessLocked(receivedAt: _latestLabState?.receivedAt,
                               packetGeneration: _latestLabState?.connectionGeneration,
                               maxAge: maxAge)
    }

    func labAckFreshness(maxAge: TimeInterval = FlyGymBridge.labDiscreteFreshMaxAge) -> FlyGymPacketFreshness {
        lock.lock(); defer { lock.unlock() }
        return freshnessLocked(receivedAt: _latestLabAck?.receivedAt,
                               packetGeneration: _latestLabAck?.connectionGeneration,
                               maxAge: maxAge)
    }

    func labEventFreshness(maxAge: TimeInterval = FlyGymBridge.labDiscreteFreshMaxAge) -> FlyGymPacketFreshness {
        lock.lock(); defer { lock.unlock() }
        return freshnessLocked(receivedAt: _latestLabEvent?.receivedAt,
                               packetGeneration: _latestLabEvent?.connectionGeneration,
                               maxAge: maxAge)
    }

    func latestBody(maxAge: TimeInterval = FlyGymBridge.bodyFreshMaxAge) -> FlyGymBodyFeedback? {
        lock.lock(); defer { lock.unlock() }
        guard let b = _latestBody,
              freshnessLocked(receivedAt: b.receivedAt,
                              packetGeneration: b.connectionGeneration,
                              maxAge: maxAge).isFresh else { return nil }
        return b
    }

    func latestLabState(maxAge: TimeInterval? = nil) -> LabRemoteState? {
        lock.lock(); defer { lock.unlock() }
        guard let state = _latestLabState,
              _connected, state.connectionGeneration == _connectionGeneration else { return nil }
        if let maxAge, state.ageSeconds() >= maxAge { return nil }
        return state
    }

    func latestLabAck(maxAge: TimeInterval? = nil) -> LabAck? {
        lock.lock(); defer { lock.unlock() }
        guard let ack = _latestLabAck,
              _connected, ack.connectionGeneration == _connectionGeneration else { return nil }
        if let maxAge, ack.ageSeconds() >= maxAge { return nil }
        return ack
    }

    func latestLabEvent(maxAge: TimeInterval? = nil) -> LabEventNotice? {
        lock.lock(); defer { lock.unlock() }
        guard let event = _latestLabEvent,
              _connected, event.connectionGeneration == _connectionGeneration else { return nil }
        if let maxAge, event.ageSeconds() >= maxAge { return nil }
        return event
    }

    var bodyHz: Double {
        lock.lock(); defer { lock.unlock() }
        guard let body = _latestBody,
              freshnessLocked(receivedAt: body.receivedAt,
                              packetGeneration: body.connectionGeneration,
                              maxAge: FlyGymBridge.bodyFreshMaxAge).isFresh,
              bodyIntervals.count >= 4 else { return 0 }
        let span = bodyIntervals.reduce(0, +)
        return span > 0 ? Double(bodyIntervals.count) / span : 0
    }

    /// Largest receive-to-receive gap in the recent body-feedback window. A live
    /// average Hz can hide stalls, so regression/smoke tests assert this too.
    var maxRecentBodyGap: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let body = _latestBody,
              freshnessLocked(receivedAt: body.receivedAt,
                              packetGeneration: body.connectionGeneration,
                              maxAge: FlyGymBridge.bodyFreshMaxAge).isFresh else { return .infinity }
        return bodyIntervals.max() ?? .infinity
    }

    var statusLine: String {
        lock.lock()
        let c = _connected
        let sent = sentCount, recv = recvCount, mal = malformedCount
        let labSent = labSentCount, labRecv = labRecvCount
        let bodyAge = _latestBody.map { max(0, Date().timeIntervalSince($0.receivedAt)) }
        let bodyFresh = _latestBody.map {
            _connected && $0.connectionGeneration == _connectionGeneration
            && max(0, Date().timeIntervalSince($0.receivedAt)) < FlyGymBridge.bodyFreshMaxAge
        } ?? false
        let hz = { () -> Double in
            guard bodyFresh, self.bodyIntervals.count >= 4 else { return 0 }
            let span = self.bodyIntervals.reduce(0, +)
            return span > 0 ? Double(self.bodyIntervals.count) / span : 0
        }()
        lock.unlock()
        if c {
            let bodyStatus: String
            if bodyFresh, let age = bodyAge {
                bodyStatus = String(format: "%.0f Hz, %.0f ms old", hz, age * 1000)
            } else if let age = bodyAge {
                bodyStatus = String(format: "STALE, %.2f s old", age)
            } else {
                bodyStatus = "waiting"
            }
            return "FlyGym connected - brain \(sent), body \(recv) (\(bodyStatus)), lab \(labSent)/\(labRecv), malformed \(mal)"
        }
        return "FlyGym disconnected (brain continues locally)"
    }

    var labStatusLine: String {
        lock.lock()
        let connected = _connected
        let q = pendingLab.count
        let dropped = droppedLab
        let ack = _latestLabAck
        lock.unlock()
        let a = ack.map { "ack #\($0.id) \($0.ok ? "OK" : "ERR") \($0.message)" } ?? "no ack yet"
        return "\(connected ? "connected" : "disconnected") · queue \(q)/\(labQueueCap) · dropped \(dropped) · \(a)"
    }

    func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()
        Thread { [weak self] in self?.sendLoop() }.start()
        Thread { [weak self] in self?.recvLoop() }.start()
    }

    func stop() {
        lock.lock()
        running = false
        let s = sock
        sock = -1
        _connected = false
        clearRemoteStateLocked()
        lock.unlock()
        if s >= 0 { Darwin.shutdown(s, Int32(SHUT_RDWR)); Darwin.close(s) }
    }

    private func isRunning() -> Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// Called from the render thread: only encodes JSON + stores one Data.
    /// Never touches the socket. Latest-packet-wins, so bursts coalesce.
    func sendBrain(_ s: BrainSignals, simMs: Int) {
        let pkt = FlyGymBrainPacket(signals: s, simMs: simMs)
        guard let line = try? JSONEncoder().encode(pkt) else { return }
        var data = line; data.append(0x0A)
        lock.lock()
        if s.escape {
            if pendingEscape != nil { droppedCoalesced += 1 }
            pendingEscape = data
        } else {
            if pending != nil { droppedCoalesced += 1 }
            pending = data
        }
        pendingCount += 1
        lock.unlock()
    }

    /// Enqueue one ordered experiment command. AppKit calls this directly; it
    /// performs only JSON encoding and a bounded in-memory append.
    @discardableResult
    func sendLab(action: String, target: String? = nil,
                 x: Double? = nil, y: Double? = nil, z: Double? = nil,
                 size: Double? = nil, speed: Double? = nil,
                 strength: Double? = nil, durationMs: Int? = nil,
                 value: Double? = nil, directionDeg: Double? = nil,
                 endDistance: Double? = nil, physical: Bool? = nil,
                 sensory: Bool? = nil, continuous: Bool? = nil,
                 mode: String? = nil) -> Int {
        lock.lock()
        let id = nextLabID
        nextLabID = nextLabID == Int.max ? 1 : nextLabID + 1
        lock.unlock()
        let cmd = LabCommand(id: id, action: action, target: target,
                             x: x, y: y, z: z, size: size, speed: speed,
                             strength: strength, durationMs: durationMs, value: value,
                             directionDeg: directionDeg, endDistance: endDistance,
                             physical: physical, sensory: sensory,
                             continuous: continuous, mode: mode)
        guard let line = try? JSONEncoder().encode(cmd) else { return id }
        var data = line; data.append(0x0A)
        lock.lock()
        if pendingLab.count >= labQueueCap {
            pendingLab.removeFirst()
            droppedLab += 1
        }
        pendingLab.append(data)
        lock.unlock()
        return id
    }

    // -- test hook: one latest-state slot + one escape-pulse slot.
    func pendingDepth() -> Int {
        lock.lock(); defer { lock.unlock() }
        return (pending == nil ? 0 : 1) + (pendingEscape == nil ? 0 : 1) + pendingLab.count
    }


    func pendingLabDepth() -> Int { lock.lock(); defer { lock.unlock() }; return pendingLab.count }

    private func clearRemoteStateLocked() {
        _latestBody = nil
        _latestLabState = nil
        _latestLabAck = nil
        _latestLabEvent = nil
        lastBodyAt = nil
        bodyIntervals.removeAll(keepingCapacity: true)
    }

    private func beginConnectionLocked(_ fd: Int32) {
        sock = fd
        _connected = true
        _connectionGeneration &+= 1
        if _connectionGeneration == 0 { _connectionGeneration = 1 }
        clearRemoteStateLocked()
        lastSend = .distantPast
        lastNormalBrainSendAt = .distantPast
    }

    private func currentConnectionLocked(fd: Int32, generation: UInt64) -> Bool {
        _connected && sock == fd && _connectionGeneration == generation
    }

    private func dequeueNextLocked(now: Date) -> FlyGymPendingSend? {
        if let urgent = pendingEscape {
            pendingEscape = nil
            return FlyGymPendingSend(lane: .escape, data: urgent)
        }
        if let brain = pending,
           pendingLab.isEmpty || now.timeIntervalSince(lastNormalBrainSendAt) >= maxNormalBrainGap {
            pending = nil
            return FlyGymPendingSend(lane: .brain, data: brain)
        }
        if !pendingLab.isEmpty {
            return FlyGymPendingSend(lane: .lab, data: pendingLab.removeFirst())
        }
        if let brain = pending {
            pending = nil
            return FlyGymPendingSend(lane: .brain, data: brain)
        }
        return nil
    }

    private func requeueLocked(_ item: FlyGymPendingSend) {
        switch item.lane {
        case .escape:
            if pendingEscape == nil { pendingEscape = item.data }
        case .lab:
            pendingLab.insert(item.data, at: 0)
            if pendingLab.count > labQueueCap {
                pendingLab.removeLast()
                droppedLab += 1
            }
        case .brain:
            // If a newer latest-state packet arrived while send() was running,
            // keep the newer packet rather than restoring an obsolete snapshot.
            if pending == nil { pending = item.data }
        }
    }

    private func acceptInboundLine(_ line: Data, fd: Int32, generation: UInt64,
                                   receivedAt: Date = Date()) -> Bool {
        if let pkt = parseBodyLine(line) {
            var fb = FlyGymBodyFeedback(pkt)
            fb.receivedAt = receivedAt
            fb.connectionGeneration = generation
            lock.lock()
            guard currentConnectionLocked(fd: fd, generation: generation) else {
                lock.unlock(); return true
            }
            if let prev = lastBodyAt {
                let interval = receivedAt.timeIntervalSince(prev)
                if interval > 0 {
                    bodyIntervals.append(interval)
                    if bodyIntervals.count > 120 { bodyIntervals.removeFirst(bodyIntervals.count - 120) }
                }
            }
            lastBodyAt = receivedAt
            _latestBody = fb
            recvCount += 1
            lock.unlock()
            return true
        }
        if var state = parseLabStateLine(line) {
            state.receivedAt = receivedAt
            state.connectionGeneration = generation
            lock.lock()
            guard currentConnectionLocked(fd: fd, generation: generation) else {
                lock.unlock(); return true
            }
            _latestLabState = state
            labRecvCount += 1
            if let ackID = state.ack {
                _latestLabAck = LabAck(type: "lab_ack", id: ackID,
                                       ok: state.ok ?? (state.error == nil),
                                       action: state.lastAction ?? "",
                                       message: state.error ?? "ok",
                                       receivedAt: receivedAt,
                                       connectionGeneration: generation)
            }
            lock.unlock()
            return true
        }
        if var ack = parseLabAckLine(line) {
            ack.receivedAt = receivedAt
            ack.connectionGeneration = generation
            lock.lock()
            guard currentConnectionLocked(fd: fd, generation: generation) else {
                lock.unlock(); return true
            }
            _latestLabAck = ack
            labRecvCount += 1
            lock.unlock()
            return true
        }
        if var event = parseLabEventLine(line) {
            event.receivedAt = receivedAt
            event.connectionGeneration = generation
            lock.lock()
            guard currentConnectionLocked(fd: fd, generation: generation) else {
                lock.unlock(); return true
            }
            _latestLabEvent = event
            labRecvCount += 1
            lock.unlock()
            return true
        }
        return false
    }

    // MARK: test hooks (same production lifecycle/arbitration paths, no sockets)

    fileprivate func beginConnectionForTesting() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        beginConnectionLocked(-2)
        return _connectionGeneration
    }

    fileprivate func receiveLineForTesting(_ line: Data, at receivedAt: Date = Date()) -> Bool {
        lock.lock()
        let fd = sock
        let generation = _connectionGeneration
        lock.unlock()
        return acceptInboundLine(line, fd: fd, generation: generation, receivedAt: receivedAt)
    }

    fileprivate func disconnectForTesting() {
        lock.lock()
        let fd = sock
        let generation = _connectionGeneration
        lock.unlock()
        markDown(fd, generation: generation)
    }

    fileprivate func dequeueLaneForTesting(at now: Date) -> FlyGymSendLane? {
        lock.lock(); defer { lock.unlock() }
        guard let item = dequeueNextLocked(now: now) else { return nil }
        if item.lane == .brain { lastNormalBrainSendAt = now }
        return item.lane
    }

    // MARK: threads

    private func openConnection() -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        withUnsafePointer(to: &tv) { p in
            p.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { q in
                _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, q, socklen_t(MemoryLayout<timeval>.size))
                _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, q, socklen_t(MemoryLayout<timeval>.size))
            }
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = host.withCString { Darwin.inet_addr($0) }
        let r = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { q in
                Darwin.connect(fd, q, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { Darwin.close(fd); return -1 }
        return fd
    }

    private func sendLoop() {
        while isRunning() {
            lock.lock()
            let fd = sock
            let ok = _connected
            let generation = _connectionGeneration
            lock.unlock()
            if !ok || fd < 0 {
                lock.lock(); connectAttempts += 1; lock.unlock()
                let fd2 = openConnection()
                var closeUnused = false
                lock.lock()
                if fd2 >= 0 && running && !_connected && sock < 0 {
                    beginConnectionLocked(fd2)
                } else if fd2 >= 0 {
                    closeUnused = true
                }
                lock.unlock()
                if closeUnused { Darwin.shutdown(fd2, Int32(SHUT_RDWR)); Darwin.close(fd2) }
                if fd2 < 0 { Thread.sleep(forTimeInterval: 0.5); continue }
                continue
            }
            lock.lock()
            let now = Date()
            let sendWait = minSendInterval - now.timeIntervalSince(lastSend)
            let item = sendWait <= 0 ? dequeueNextLocked(now: now) : nil
            lock.unlock()
            if sendWait > 0 {
                Thread.sleep(forTimeInterval: min(0.005, max(0.001, sendWait)))
                continue
            }
            if let item {
                let d = item.data
                var sent = 0
                d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                    var cur = p.baseAddress!
                    var left = d.count
                    while left > 0 {
                        let n = Darwin.send(fd, cur, left, 0)
                        if n <= 0 { break }
                        sent += n; cur = cur.advanced(by: n); left -= n
                    }
                }
                lock.lock()
                if sent == d.count {
                    let sentAt = Date()
                    if item.lane == .lab { labSentCount += 1 } else { sentCount += 1 }
                    if item.lane == .brain { lastNormalBrainSendAt = sentAt }
                    lastSend = sentAt
                }
                else {
                    requeueLocked(item)
                }
                lock.unlock()
                if sent != d.count { markDown(fd, generation: generation) }
            } else {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }

    private func markDown(_ fd: Int32, generation: UInt64) {
        lock.lock()
        let shouldClose = sock == fd && _connectionGeneration == generation
        if shouldClose {
            sock = -1
            _connected = false
            clearRemoteStateLocked()
        }
        lock.unlock()
        // sendLoop and recvLoop can discover the same failure concurrently.
        // Only the first thread that still owns this descriptor may close it;
        // otherwise a reused descriptor for a new connection could be closed.
        if shouldClose && fd >= 0 {
            Darwin.shutdown(fd, Int32(SHUT_RDWR)); Darwin.close(fd)
        }
    }

    private func recvLoop() {
        var buf = Data()
        var bufferFD: Int32 = -1
        var bufferGeneration: UInt64 = 0
        let tmp = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { tmp.deallocate() }
        while isRunning() {
            lock.lock()
            let fd = sock
            let ok = _connected
            let generation = _connectionGeneration
            lock.unlock()
            if !ok || fd < 0 {
                buf.removeAll(keepingCapacity: true)
                bufferFD = -1
                bufferGeneration = 0
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            if fd != bufferFD || generation != bufferGeneration {
                buf.removeAll(keepingCapacity: true)
                bufferFD = fd
                bufferGeneration = generation
            }
            let n = Darwin.recv(fd, tmp, 4096, 0)
            if n > 0 {
                buf.append(tmp, count: n)
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = buf.subdata(in: buf.startIndex..<nl)
                    buf.removeSubrange(buf.startIndex...nl)
                    if line.isEmpty { continue }
                    if !acceptInboundLine(line, fd: fd, generation: generation) {
                        lock.lock()
                        if currentConnectionLocked(fd: fd, generation: generation) {
                            malformedCount += 1
                        }
                        lock.unlock()
                    }
                }
                if buf.count > 65536 { buf.removeAll() }   // malformed flood guard
            } else if n == 0 {
                markDown(fd, generation: generation); buf.removeAll() // orderly close -> reconnect
                bufferFD = -1; bufferGeneration = 0
            } else {
                if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    markDown(fd, generation: generation); buf.removeAll()
                    bufferFD = -1; bufferGeneration = 0
                }
                // else: timeout tick, socket still alive
            }
        }
    }
}

// MARK: - Headless self-test (--bridgetest, no sim, no sockets)

func runBridgeTest() {
    var failures = 0
    func check(_ name: String, _ cond: Bool, _ detail: String = "") {
        print((cond ? "PASS" : "FAIL") + "  " + name + (detail.isEmpty ? "" : ": " + detail))
        if !cond { failures += 1 }
    }
    // 1. BrainSignals serialization: all keys present, escape pulse preserved.
    var s = BrainSignals()
    s.escape = true; s.walkDrive = 0.52; s.turnBias = -0.18; s.sleep = false
    s.backward = true; s.groomDrive = 0.02; s.wingDrive = 0.1; s.arousal = 0.31
    let pkt = FlyGymBrainPacket(signals: s, simMs: 1234)
    let data = (try? JSONEncoder().encode(pkt)) ?? Data()
    let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    check("brain keys", (obj["type"] as? String) == "brain"
        && (obj["walk"] as? Double ?? -1) == 0.52
        && (obj["turn"] as? Double ?? 9) == -0.18
        && (obj["escape"] as? Bool) == true
        && (obj["backward"] as? Bool) == true
        && abs((obj["t"] as? Double ?? -1) - 1.234) < 1e-9)
    // 2/6. body parse of a well-formed line.
    let line = #"{"type":"body","t":1.238,"sim_dt":0.002,"wall_dt":0.020,"sim_wall_ratio":0.1,"controller_left":0.21,"controller_right":0.43,"wind_strength":0.7,"wind_direction_deg":-30,"wind_sensory":true,"touch_strength":0.55,"touch_sensory":true,"vx":0.013,"yaw_rate":-0.12,"contacts":[1,1,0,0,1,0],"left_contact":0.67,"right_contact":0.33,"loom_left":0.7,"loom_right":0.2,"brightness":0.4,"odor_left":0.75,"odor_right":0.2,"nearest_food_distance_mm":12.5,"heading_rad":1.25,"bearing":0.5}"#
    let body = parseBodyLine(Data(line.utf8))
    check("body parse", body != nil && abs((body?.vx ?? 9) - 0.013) < 1e-9
        && abs((body?.t ?? -1) - 1.238) < 1e-9
        && abs((body?.simDt ?? -1) - 0.002) < 1e-9
        && abs((body?.wallDt ?? -1) - 0.020) < 1e-9
        && abs((body?.simWallRatio ?? -1) - 0.1) < 1e-9
        && abs((body?.controllerLeft ?? -9) - 0.21) < 1e-9
        && abs((body?.controllerRight ?? -9) - 0.43) < 1e-9
        && abs((body?.windStrength ?? -9) - 0.7) < 1e-9
        && abs((body?.windDirectionDeg ?? 9) + 30) < 1e-9
        && body?.windSensory == true
        && abs((body?.touchStrength ?? -9) - 0.55) < 1e-9
        && body?.touchSensory == true
        && (body?.contacts ?? []) == [1, 1, 0, 0, 1, 0]
        && abs((body?.leftContact ?? -1) - 0.67) < 1e-9
        && abs((body?.loomLeft ?? -1) - 0.7) < 1e-9
        && abs((body?.odorLeft ?? -1) - 0.75) < 1e-9
        && abs((body?.odorRight ?? -1) - 0.2) < 1e-9
        && abs((body?.nearestFoodDistanceMm ?? -1) - 12.5) < 1e-9
        && abs((body?.headingRad ?? -9) - 1.25) < 1e-9)
    // 7. clamping.
    let wild = #"{"type":"body","sim_dt":99,"wall_dt":-3,"sim_wall_ratio":9999,"vx":99,"yaw_rate":-99,"contacts":[9,-9,2,2,2,2,2,2],"left_contact":5,"right_contact":-5,"loom_left":9,"loom_right":-2,"brightness":7,"odor_left":9,"odor_right":-2,"nearest_food_distance_mm":-4,"heading_rad":99,"bearing":-9}"#
    let c = parseBodyLine(Data(wild.utf8))
    check("feedback clamps", c?.vx == 2.0 && c?.yawRate == -20.0
        && c?.simDt == 10.0 && c?.wallDt == 0.0 && c?.simWallRatio == 1000.0
        && (c?.contacts ?? []) == [1, 0, 1, 1, 1, 1]
        && c?.leftContact == 1.0 && c?.rightContact == 0.0
        && c?.loomLeft == 1.0 && c?.loomRight == 0.0 && c?.brightness == 1.0
        && c?.odorLeft == 1.0 && c?.odorRight == 0.0 && c?.nearestFoodDistanceMm == 0.0
        && c?.headingRad == Double.pi
        && c?.bearing == -1.0)
    // 2. malformed lines throw (recvLoop counts and skips them).
    var malformed = 0
    for bad in ["not json", "[1,2]", #"{"type":"nope"}"#, "", "{\"type\":\"body\",\"vx\":}"] {
        if parseBodyLine(Data(bad.utf8)) == nil {
            malformed += 1
        }
    }
    check("malformed rejected", malformed == 5, "\(malformed)/5")
    // sensory map: standing contact is not gait; fresh real body is authoritative;
    // stale/missing real body falls back to the desktop procedural fly.
    var still = FlyGymBodyFeedback()
    still.contacts = [1, 1, 1, 1, 1, 1]
    still.leftContact = 1; still.rightContact = 1
    check("standing contact -> 0 gait", FlyGymSensoryMap.bodyDrive(still) == 0)
    check("fresh real ignores procedural gait",
          FlyGymSensoryMap.gaitDrive(procedural: 0.8, body: still) == 0)
    var brisk = FlyGymBodyFeedback()
    brisk.vx = 0.03; brisk.contacts = [1, 1, 1, 1, 1, 1]
    brisk.leftContact = 1; brisk.rightContact = 1
    check("brisk body -> ~1", abs(FlyGymSensoryMap.bodyDrive(brisk) - 1.0) < 1e-9)
    check("stale falls back", FlyGymSensoryMap.gaitDrive(procedural: 0.4, body: nil) == 0.4)
    var old = brisk; old.receivedAt = Date(timeIntervalSinceNow: -10)
    check("old packet falls back", FlyGymSensoryMap.gaitDrive(procedural: 0.4, body: old) == 0.4)
    if let body {
        var freshOdor = FlyGymBodyFeedback(body)
        check("body sim time/dt reach feedback",
              abs(freshOdor.simTime - 1.238) < 1e-9
              && abs(freshOdor.simDt - 0.002) < 1e-9
              && abs(freshOdor.simWallRatio - 0.1) < 1e-9
              && abs(freshOdor.controllerLeft - 0.21) < 1e-9
              && abs(freshOdor.controllerRight - 0.43) < 1e-9
              && abs(freshOdor.windStrength - 0.7) < 1e-9
              && freshOdor.windSensory
              && abs(freshOdor.touchStrength - 0.55) < 1e-9
              && freshOdor.touchSensory)
        freshOdor.receivedAt = Date()
        let o = FlyGymSensoryMap.foodOdor(body: freshOdor)
        check("fresh food odor maps", abs(o.l - 0.75) < 1e-6 && abs(o.r - 0.2) < 1e-6)
        freshOdor.receivedAt = Date(timeIntervalSinceNow: -10)
        let staleOdor = FlyGymSensoryMap.foodOdor(body: freshOdor)
        check("stale food odor clears", staleOdor.l == 0 && staleOdor.r == 0)
        check("fresh body heading maps", abs((FlyGymSensoryMap.heading(body: FlyGymBodyFeedback(body)) ?? -9) - 1.25) < 1e-9)
        check("stale body heading clears", FlyGymSensoryMap.heading(body: freshOdor) == nil)
    } else {
        check("food odor mapping", false, "body packet missing")
    }
    // 9. bounded queue: one normal latest slot + one protected escape slot.
    let b = FlyGymBridge()
    for _ in 0..<100 { b.sendBrain(s, simMs: 1) }
    check("bounded queue", b.pendingDepth() <= 2, "depth=\(b.pendingDepth())")
    s.escape = false
    b.sendBrain(s, simMs: 2)
    s.escape = true
    b.sendBrain(s, simMs: 3)
    check("escape pulse gets protected lane", b.pendingDepth() == 2,
          "depth=\(b.pendingDepth())")

    // Connection generation + freshness. Test hooks reuse the exact production
    // lifecycle/inbound paths but never open a socket.
    let freshBridge = FlyGymBridge()
    let gen1 = freshBridge.beginConnectionForTesting()
    let recvNow = Date()
    for i in 0..<5 {
        let at = recvNow.addingTimeInterval(Double(i - 4) * 0.02)
        _ = freshBridge.receiveLineForTesting(Data(line.utf8), at: at)
    }
    let liveBody = freshBridge.latestBody()
    let bodyFresh = freshBridge.bodyFreshness()
    check("body generation + simTime stamped",
          gen1 == 1 && liveBody?.connectionGeneration == gen1
          && abs((liveBody?.simTime ?? -1) - 1.238) < 1e-9)
    check("body freshness exposes age/generation",
          bodyFresh.connected && bodyFresh.isFresh
          && bodyFresh.packetGeneration == gen1
          && (bodyFresh.ageSeconds ?? 9) < 0.2)
    check("fresh bodyHz reports live cadence",
          freshBridge.bodyHz > 40 && freshBridge.bodyHz < 60,
          String(format: "%.1f Hz", freshBridge.bodyHz))

    let stateLine = #"{"type":"lab_state","t":1.25,"ack":7,"ok":true,"object_count":1,"last_action":"spawn_sphere"}"#
    let ackLine = #"{"type":"lab_ack","id":8,"ok":true,"action":"wind","message":"ok"}"#
    let eventLine = #"{"type":"lab_event","event":"wind_started"}"#
    _ = freshBridge.receiveLineForTesting(Data(stateLine.utf8), at: recvNow)
    _ = freshBridge.receiveLineForTesting(Data(ackLine.utf8), at: recvNow)
    _ = freshBridge.receiveLineForTesting(Data(eventLine.utf8), at: recvNow)
    let stateFresh = freshBridge.labStateFreshness()
    let ackFresh = freshBridge.labAckFreshness()
    let eventFresh = freshBridge.labEventFreshness()
    check("lab state/ack/event generation stamped",
          freshBridge.latestLabState()?.connectionGeneration == gen1
          && freshBridge.latestLabAck()?.connectionGeneration == gen1
          && freshBridge.latestLabEvent()?.connectionGeneration == gen1)
    check("lab state/ack/event freshness exposes age",
          stateFresh.isFresh && ackFresh.isFresh && eventFresh.isFresh
          && (stateFresh.ageSeconds ?? 9) < 0.2
          && (ackFresh.ageSeconds ?? 9) < 0.2
          && (eventFresh.ageSeconds ?? 9) < 0.2)

    freshBridge.disconnectForTesting()
    check("disconnect clears remote state",
          !freshBridge.connected && freshBridge.latestBody() == nil
          && freshBridge.latestLabState() == nil && freshBridge.latestLabAck() == nil
          && freshBridge.latestLabEvent() == nil && freshBridge.bodyHz == 0)
    let gen2 = freshBridge.beginConnectionForTesting()
    check("reconnect advances generation and stays empty",
          gen2 == gen1 + 1 && freshBridge.latestBody() == nil
          && freshBridge.latestLabState() == nil)

    let oldAt = Date(timeIntervalSinceNow: -2)
    for i in 0..<5 {
        let at = oldAt.addingTimeInterval(Double(i) * 0.02)
        _ = freshBridge.receiveLineForTesting(Data(line.utf8), at: at)
    }
    _ = freshBridge.receiveLineForTesting(Data(stateLine.utf8), at: oldAt)
    _ = freshBridge.receiveLineForTesting(Data(ackLine.utf8), at: oldAt)
    _ = freshBridge.receiveLineForTesting(Data(eventLine.utf8), at: oldAt)
    check("stale bodyHz drops to zero",
          freshBridge.bodyHz == 0 && !freshBridge.bodyFreshness().isFresh
          && freshBridge.latestBody() == nil)
    check("stale lab age is queryable",
          !freshBridge.labStateFreshness(maxAge: 1).isFresh
          && !freshBridge.labAckFreshness(maxAge: 1).isFresh
          && !freshBridge.labEventFreshness(maxAge: 1).isFresh
          && (freshBridge.labStateFreshness(maxAge: 1).ageSeconds ?? 0) > 1.5
          && freshBridge.latestLabState(maxAge: 1) == nil
          && freshBridge.latestLabAck(maxAge: 1) == nil
          && freshBridge.latestLabEvent(maxAge: 1) == nil)

    // Fair sender arbitration: a full 32-command lab burst must drain while a
    // normal latest-state brain packet gets the wire at least every ~75 ms.
    let fair = FlyGymBridge()
    fair.maxNormalBrainGap = 0.075
    var normal = BrainSignals()
    normal.escape = false
    fair.sendBrain(normal, simMs: 0)
    for i in 0..<32 { _ = fair.sendLab(action: "move_object", target: "fair_\(i)", x: Double(i)) }
    let fairStart = Date()
    var fairNow = fairStart
    var lastBrain = fairStart
    var maxBrainGap = 0.0
    var normalBrainSends = 0
    var labSends = 0
    var fairnessSteps = 0
    while fair.pendingLabDepth() > 0 && fairnessSteps < 100 {
        if let lane = fair.dequeueLaneForTesting(at: fairNow) {
            switch lane {
            case .brain:
                if normalBrainSends > 0 {
                    maxBrainGap = max(maxBrainGap, fairNow.timeIntervalSince(lastBrain))
                }
                lastBrain = fairNow
                normalBrainSends += 1
                fair.sendBrain(normal, simMs: fairnessSteps + 1)
            case .lab:
                labSends += 1
            case .escape:
                break
            }
        }
        fairNow = fairNow.addingTimeInterval(fair.minSendInterval)
        fairnessSteps += 1
    }
    maxBrainGap = max(maxBrainGap, fairNow.timeIntervalSince(lastBrain))
    check("32-lab burst preserves <=100ms brain gap",
          labSends == 32 && fair.pendingLabDepth() == 0
          && normalBrainSends > 1 && maxBrainGap <= 0.100,
          String(format: "lab=%d brain=%d maxGap=%.1fms", labSends, normalBrainSends, maxBrainGap * 1000))
    print(failures == 0 ? "ALL BRIDGE TESTS PASS" : "\(failures) FAILURES")
    exit(failures == 0 ? 0 : 1)
}

// MARK: - Headless loop test (--bridgeloop, needs bridge.py --mock running)

/// Sends synthetic BrainSignals at ~60 Hz through the real TCP client and
/// counts body packets coming back. Verifies the full Swift<->Python loop.
func runBridgeLoopTest() {
    let fg = FlyGymBridge()
    fg.start()
    var waited = 0
    while !fg.connected && waited < 50 {
        Thread.sleep(forTimeInterval: 0.1); waited += 1
    }
    guard fg.connected else {
        print("FAIL  bridgeloop: no connection (is bridge.py --mock running?)")
        exit(1)
    }
    print("bridgeloop: connected, sending 200 packets @ ~75 Hz")
    let t0 = Date()
    var peakBodySpeed = 0.0
    for i in 0..<200 {
        var s = BrainSignals()
        s.walkDrive = 0.6; s.turnBias = 0.2
        s.arousal = 0.3; s.sleep = false
        fg.sendBrain(s, simMs: i * 13)
        if let b = fg.latestBody() { peakBodySpeed = max(peakBodySpeed, abs(b.vx)) }
        Thread.sleep(forTimeInterval: 1.0 / 75.0)
    }
    Thread.sleep(forTimeInterval: 1.0)   // let stragglers arrive
    if let b = fg.latestBody() { peakBodySpeed = max(peakBodySpeed, abs(b.vx)) }
    let dt = Date().timeIntervalSince(t0)
    let sent = fg.sentCount
    let recv = fg.recvCount
    let hz = fg.bodyHz
    let maxGap = fg.maxRecentBodyGap
    let finalBody = fg.latestBody()
    let simWall = finalBody?.simWallRatio ?? 0
    let brainHz = dt > 0 ? Double(sent) / dt : 0
    fg.stop()
    print(String(format: "bridgeloop: sent %d brain, recv %d body in %.1f s (brain %.1f Hz, body %.1f Hz, max body gap %.0f ms, sim/wall %.3f, peak |vx| %.2f mm/s)",
                 sent, recv, dt, brainHz, hz, maxGap * 1000, simWall, peakBodySpeed * 1000))
    // This synthetic packet intentionally asks the body to walk.  The loop is
    // not healthy if packets flow but the real body remains effectively static.
    let pass = sent >= 180 && recv >= 50 && hz >= 30
        && maxGap <= 0.250 && simWall > 0.25 && peakBodySpeed > 0.0005
    print(pass ? "BRIDGELOOP PASS" : "BRIDGELOOP FAIL")
    exit(pass ? 0 : 1)
}

// MARK: - Live lab protocol test (--labloop, needs bridge.py running)

/// Exercises the actual TCP lab lane and acknowledgement/state/event path.
/// Works against both `bridge.py --mock` and real FlyGym.
func runLabLoopTest() {
    let fg = FlyGymBridge()
    fg.start()
    var waited = 0
    while !fg.connected && waited < 80 {
        Thread.sleep(forTimeInterval: 0.1); waited += 1
    }
    guard fg.connected else {
        print("FAIL  labloop: no connection (start bridge.py --mock or --flygym-headless)")
        exit(1)
    }

    func waitAck(_ id: Int, seconds: Double = 3.0) -> LabAck? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let ack = fg.latestLabAck(), ack.id == id { return ack }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    var failures = 0
    func command(_ name: String, _ id: Int) {
        let ack = waitAck(id)
        let ok = ack?.ok == true
        let fresh = fg.labAckFreshness()
        let ageMs = fresh.ageSeconds.map { String(format: "%.0f", $0 * 1000) } ?? "n/a"
        print("\(ok ? "PASS" : "FAIL")  labloop \(name) ack=\(ack?.id ?? -1) \(ack?.message ?? "timeout")"
              + " gen=\(fresh.packetGeneration.map(String.init) ?? "n/a")/\(fresh.currentGeneration) age=\(ageMs)ms")
        if !ok { failures += 1 }
    }

    func bodyDiagnostic(_ body: FlyGymBodyFeedback?) -> String {
        let fresh = fg.bodyFreshness()
        let ageMs = fresh.ageSeconds.map { String(format: "%.0f", $0 * 1000) } ?? "n/a"
        guard let body else {
            return "body=nil gen=\(fresh.packetGeneration.map(String.init) ?? "n/a")/\(fresh.currentGeneration) age=\(ageMs)ms fresh=\(fresh.isFresh)"
        }
        return String(format: "t=%.4fs dt=%.4fs wind=%.3f touch=%.3f gen=%@/%llu age=%@ms fresh=%@",
                      body.simTime, body.simDt, body.windStrength, body.touchStrength,
                      fresh.packetGeneration.map(String.init) ?? "n/a", fresh.currentGeneration,
                      ageMs, fresh.isFresh ? "yes" : "no")
    }

    let objectID = "labloop_ball_\(ProcessInfo.processInfo.processIdentifier)"
    let spawn = fg.sendLab(action: "spawn_sphere", target: objectID,
                           x: 20, y: 5, z: 3, size: 4)
    command("spawn", spawn)
    if (fg.latestLabState()?.objectCount ?? 0) < 1 {
        Thread.sleep(forTimeInterval: 0.15)
    }
    let stateOK = (fg.latestLabState()?.objectCount ?? 0) >= 1
    print("\(stateOK ? "PASS" : "FAIL")  labloop state object_count=\(fg.latestLabState()?.objectCount ?? -1)")
    if !stateOK { failures += 1 }

    let wind = fg.sendLab(action: "wind", strength: 0.2, durationMs: 300,
                          directionDeg: 90, physical: true, sensory: true, continuous: false)
    command("wind", wind)
    let flash = fg.sendLab(action: "flash_eye", target: "left", strength: 0.8, durationMs: 80)
    command("flash", flash)
    let touch = fg.sendLab(action: "touch", target: "thorax", strength: 0.2, durationMs: 300)
    command("touch", touch)
    let sourceDeadline = Date().addingTimeInterval(0.25)
    var sourceOK = false
    var sourceBody: FlyGymBodyFeedback?
    while Date() < sourceDeadline {
        if let body = fg.latestBody(), body.windStrength > 0.19, body.windSensory,
           body.touchStrength > 0.19, body.touchSensory {
            sourceOK = true
            sourceBody = body
            break
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    print("\(sourceOK ? "PASS" : "FAIL")  labloop body packet is wind/touch source-of-truth — \(bodyDiagnostic(sourceBody ?? fg.latestBody()))")
    if !sourceOK { failures += 1 }

    // The backend timer is expressed in MuJoCo simulation time, not wall time.
    // A slow real backend may need much more than 300 ms of wall time to advance
    // 300 ms of simulation. Accept only a bounded simulation-time expiry window:
    // too-early clear, frozen timers and excessively late clear are all failures.
    // The tolerance covers one observed body packet plus a few physics/telemetry
    // steps; wall time remains only a hang guard.
    let sourceSimTime = sourceBody?.simTime ?? fg.latestBody()?.simTime ?? 0
    let requestedDurationS = 0.300
    let sourceDt = max(0.001, sourceBody?.simDt ?? fg.latestBody()?.simDt ?? 0.001)
    let expiryToleranceS = max(0.060, min(0.120, sourceDt * 4 + 0.020))
    let expiryTargetSimTime = sourceSimTime + requestedDurationS
    let expiryEarliestSimTime = expiryTargetSimTime - expiryToleranceS
    let expiryLatestSimTime = expiryTargetSimTime + expiryToleranceS
    let expiryWallDeadline = Date().addingTimeInterval(12.0)
    var expired: FlyGymBodyFeedback?
    var expiredTooEarly = false
    var expiredTooLate = false
    var expiredInWindow = false
    while Date() < expiryWallDeadline {
        if let body = fg.latestBody() {
            expired = body
            let cleared = body.windStrength == 0 && body.touchStrength == 0
            if cleared {
                if body.simTime < expiryEarliestSimTime {
                    expiredTooEarly = true
                } else if body.simTime <= expiryLatestSimTime {
                    expiredInWindow = true
                } else {
                    expiredTooLate = true
                }
                break
            }
            if body.simTime > expiryLatestSimTime {
                expiredTooLate = true
                break
            }
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    let expiredOK = expiredInWindow && !expiredTooEarly && !expiredTooLate
    print("\(expiredOK ? "PASS" : "FAIL")  labloop body source clears on simulation-time timer expiry"
          + " target_t=\(String(format: "%.4f", expiryTargetSimTime))s"
          + " window=[\(String(format: "%.4f", expiryEarliestSimTime)),\(String(format: "%.4f", expiryLatestSimTime))]s"
          + " — \(bodyDiagnostic(expired))")
    if !expiredOK { failures += 1 }
    if let event = fg.latestLabEvent() {
        print("PASS  labloop event \(event.event)")
    } else {
        print("FAIL  labloop event missing"); failures += 1
    }
    // Clean up only the object this test created. Never reset an already-running
    // user's body/world merely because --labloop connected to that listener.
    let cleanup = fg.sendLab(action: "delete_object", target: objectID)
    command("delete_object", cleanup)

    fg.stop()
    print(failures == 0 ? "LABLOOP PASS" : "LABLOOP FAIL (\(failures))")
    exit(failures == 0 ? 0 : 1)
}
