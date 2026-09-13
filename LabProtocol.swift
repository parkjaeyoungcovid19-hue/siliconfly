// LabProtocol.swift — compact protocol and telemetry types for Virtual Fly Lab V2.
//
// Classification used by the UI is deliberately explicit:
//   physical       = a MuJoCo/FlyGym world mutation handled by the Python owner thread
//   sensory-model  = an engineered sensory/environment transform into existing inputs
//   direct-neural  = electrical stimulation of an existing MetalSim population

import Foundation

/// Local receive metadata attached by FlyGymBridge after a packet is accepted
/// on the current TCP connection. `connectionGeneration` lets callers reject a
/// packet from a previous reconnect epoch even when its payload is otherwise
/// valid; `receivedAt` provides a directly displayable packet age.
protocol FlyGymStampedPacket {
    var receivedAt: Date { get set }
    var connectionGeneration: UInt64 { get set }
}

extension FlyGymStampedPacket {
    func ageSeconds(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(receivedAt))
    }
}

enum LabInterventionKind: String {
    case physical = "PHYSICAL"
    case sensoryModel = "SENSORY-MODEL"
    case directNeural = "DIRECT-NEURAL"
}

/// Swift -> Python. Kept flat so both sides can tolerate new optional fields.
/// Commands are queued in a small bounded FIFO by FlyGymBridge and never touch
/// the socket from AppKit or the SceneKit render callback.
struct LabCommand: Codable {
    var type = "lab_command"
    var id: Int
    var action: String
    var target: String?
    var x: Double?
    var y: Double?
    var z: Double?
    var size: Double?
    var speed: Double?
    var strength: Double?
    var durationMs: Int?
    var value: Double?
    var directionDeg: Double? = nil
    var endDistance: Double? = nil
    var physical: Bool? = nil
    var sensory: Bool? = nil
    var continuous: Bool? = nil
    var mode: String? = nil

    enum CodingKeys: String, CodingKey {
        case type, id, action, target, x, y, z, size, speed, strength, value
        case durationMs = "duration_ms"
        case directionDeg = "direction_deg"
        case endDistance = "end_distance_mm"
        case physical, sensory, continuous, mode
    }
}

/// Python -> Swift acknowledgement for one LabCommand.
struct LabAck: Decodable, FlyGymStampedPacket {
    var type: String = "lab_ack"
    var id: Int = 0
    var ok: Bool = false
    var action: String = ""
    var message: String = ""
    var receivedAt: Date = Date()
    var connectionGeneration: UInt64 = 0

    enum CodingKeys: String, CodingKey {
        case type, id, ok, action, message
    }
}

/// Python -> Swift lifecycle marker (approach/wind/touch/flash start/complete).
/// `data` is intentionally ignored here; the event name is sufficient for the
/// V1 status/recording UI and unknown payload fields remain forward-compatible.
struct LabEventNotice: Decodable, FlyGymStampedPacket {
    var type: String = "lab_event"
    var event: String = ""
    var receivedAt: Date = Date()
    var connectionGeneration: UInt64 = 0

    enum CodingKeys: String, CodingKey {
        case type, event
    }
}

/// Python -> Swift compact lab state. Every field except `type` is optional so
/// older/newer bridge versions remain displayable instead of becoming malformed.
struct LabRemoteState: Decodable, FlyGymStampedPacket {
    var type: String = "lab_state"
    var t: Double = 0
    var ack: Int?
    var ok: Bool?
    var error: String?
    var objectCount: Int?
    var temperature: Double?
    var wind: Double?
    var leftEyeCovered: Bool?
    var rightEyeCovered: Bool?
    var lastAction: String?
    var receivedAt: Date = Date()
    var connectionGeneration: UInt64 = 0

    enum CodingKeys: String, CodingKey {
        case type, t, ack, ok, error, temperature, wind
        case objectCount = "object_count"
        case leftEyeCovered = "left_eye_covered"
        case rightEyeCovered = "right_eye_covered"
        case lastAction = "last_action"
    }
}

/// Render-owner snapshot copied under Coordinator's lock. It contains only
/// scalars/short strings so the AppKit timer never reaches into Metal buffers.
struct LabTelemetry {
    var wallTime: TimeInterval = Date().timeIntervalSince1970
    var simMs: Int = 0
    var ratePop: Double = 0
    var rateLoom: Double = 0
    var rateDNaL: Double = 0
    var rateDNaR: Double = 0
    var rateMDN: Double = 0
    var rateFwd: Double = 0
    var rateGroom: Double = 0
    var rateEscW: Double = 0
    // Receptor-group EMA spike rates from the real FlyWire cell-type groups.
    var rateFoodOdorL: Double = 0
    var rateFoodOdorR: Double = 0
    var rateThermoWarm: Double = 0
    var rateThermoCool: Double = 0
    var rateWindC: Double = 0
    var rateWindE: Double = 0
    var loomL: Double = 0
    var loomR: Double = 0
    var airPuff: Double = 0
    var gaitDrive: Double = 0
    var odorDriveL: Double = 0
    var odorDriveR: Double = 0
    var thermoWarmDrive: Double = 0
    var thermoCoolDrive: Double = 0
    var windCDrive: Double = 0
    var windEDrive: Double = 0
    var temperatureC: Double = 25
    var bodyVX: Double = 0
    var bodyYawRate: Double = 0
    var bodyContactMean: Double = 0
    var bodyLoomL: Double = 0
    var bodyLoomR: Double = 0
    var bodyBrightnessL: Double = 0
    var bodyBrightnessR: Double = 0
    var bodyOccupancyL: Double = 0
    var bodyOccupancyR: Double = 0
    var bodyOpticExpansionL: Double = 0
    var bodyOpticExpansionR: Double = 0
    var bodyFlashL: Double = 0
    var bodyFlashR: Double = 0
    var bodyOdorL: Double = 0
    var bodyOdorR: Double = 0
    /// -1 means no active food source / no fresh distance telemetry.
    var bodyNearestFoodDistanceMm: Double = -1
    /// MuJoCo/FlyGym simulation time carried by the exact body packet used for
    /// this telemetry sample. -1 means no fresh body packet was available.
    var bodySimTime: Double = -1
    var bodySimDt: Double = 0
    var bodyWallDt: Double = 0
    var bodySimWallRatio: Double = 0
    var bodyControllerLeft: Double = 0
    var bodyControllerRight: Double = 0
    var bodyWindStrength: Double = 0
    var bodyWindDirectionDeg: Double = 0
    var bodyWindSensory: Bool = false
    var bodyTouchStrength: Double = 0
    var bodyTouchSensory: Bool = false
    /// Wall-clock receive age of that body packet at snapshot time.
    var bodyPacketAgeS: Double = -1
    var bodyConnectionGeneration: UInt64 = 0
    // Exact decoded BrainSignals that were sent to FlyGym for this render step.
    var brainSignalsAvailable: Bool = false
    var brainWalkDrive: Double = 0
    var brainTurnBias: Double = 0
    var brainEscape: Bool = false
    var brainBackward: Bool = false
    var brainGroomDrive: Double = 0
    var brainWingDrive: Double = 0
    var brainArousal: Double = 0
    var brainTempo: Double = 1
    var brainSleep: Bool = false
    var brainNervous: Double = 0
    var flyState: String = "unknown"
}

extension LabTelemetry {
    mutating func applyReceptorRates(_ sim: MetalSim) {
        rateFoodOdorL = Double(sim.rateFoodOdorL)
        rateFoodOdorR = Double(sim.rateFoodOdorR)
        rateThermoWarm = Double(sim.rateThermoWarm)
        rateThermoCool = Double(sim.rateThermoCool)
        rateWindC = Double(sim.rateWindC)
        rateWindE = Double(sim.rateWindE)
    }

    mutating func applyBrainSignals(_ signals: BrainSignals?) {
        guard let signals else {
            brainSignalsAvailable = false
            brainWalkDrive = 0; brainTurnBias = 0
            brainEscape = false; brainBackward = false
            brainGroomDrive = 0; brainWingDrive = 0; brainArousal = 0
            brainTempo = 1; brainSleep = false; brainNervous = 0
            return
        }
        brainSignalsAvailable = true
        brainWalkDrive = Double(signals.walkDrive)
        brainTurnBias = Double(signals.turnBias)
        brainEscape = signals.escape
        brainBackward = signals.backward
        brainGroomDrive = Double(signals.groomDrive)
        brainWingDrive = Double(signals.wingDrive)
        brainArousal = Double(signals.arousal)
        brainTempo = Double(signals.tempo)
        brainSleep = signals.sleep
        brainNervous = Double(signals.nervous)
    }

    /// Copies one body packet as a unit so telemetry cannot accidentally mix a
    /// newer packet's diagnostics with an older packet's neural input.
    mutating func applyBodyFeedback(_ fb: FlyGymBodyFeedback?, now: Date = Date()) {
        guard let fb else {
            bodyVX = 0; bodyYawRate = 0; bodyContactMean = 0
            bodyLoomL = 0; bodyLoomR = 0
            bodyBrightnessL = 0; bodyBrightnessR = 0
            bodyOccupancyL = 0; bodyOccupancyR = 0
            bodyOpticExpansionL = 0; bodyOpticExpansionR = 0
            bodyFlashL = 0; bodyFlashR = 0
            bodyOdorL = 0; bodyOdorR = 0
            bodyNearestFoodDistanceMm = -1
            bodySimTime = -1; bodySimDt = 0; bodyWallDt = 0; bodySimWallRatio = 0
            bodyControllerLeft = 0; bodyControllerRight = 0
            bodyWindStrength = 0; bodyWindDirectionDeg = 0; bodyWindSensory = false
            bodyTouchStrength = 0; bodyTouchSensory = false
            bodyPacketAgeS = -1; bodyConnectionGeneration = 0
            return
        }
        bodyVX = fb.vx; bodyYawRate = fb.yawRate; bodyContactMean = fb.contactMean
        bodyLoomL = fb.loomLeft; bodyLoomR = fb.loomRight
        bodyBrightnessL = fb.brightnessLeft; bodyBrightnessR = fb.brightnessRight
        bodyOccupancyL = fb.occupancyLeft; bodyOccupancyR = fb.occupancyRight
        bodyOpticExpansionL = fb.opticExpansionLeft; bodyOpticExpansionR = fb.opticExpansionRight
        bodyFlashL = fb.flashLeft; bodyFlashR = fb.flashRight
        bodyOdorL = fb.odorLeft; bodyOdorR = fb.odorRight
        bodyNearestFoodDistanceMm = fb.nearestFoodDistanceMm ?? -1
        bodySimTime = fb.simTime
        bodySimDt = fb.simDt
        bodyWallDt = fb.wallDt
        bodySimWallRatio = fb.simWallRatio
        bodyControllerLeft = fb.controllerLeft
        bodyControllerRight = fb.controllerRight
        bodyWindStrength = fb.windStrength
        bodyWindDirectionDeg = fb.windDirectionDeg
        bodyWindSensory = fb.windSensory
        bodyTouchStrength = fb.touchStrength
        bodyTouchSensory = fb.touchSensory
        bodyPacketAgeS = fb.ageSeconds(at: now)
        bodyConnectionGeneration = fb.connectionGeneration
    }

    static let csvHeader = "wall_time,sim_ms,pop_hz,loom_hz,dna_l_hz,dna_r_hz,mdn_hz,dnp09_hz,dng11_hz,escw_hz,loom_l,loom_r,air_puff,gait_drive,odor_drive_l,odor_drive_r,thermo_warm_drive,thermo_cool_drive,wind_c_drive,wind_e_drive,temp_c,body_vx,body_yaw_rate,body_contact_mean,body_loom_l,body_loom_r,brightness_l,brightness_r,occupancy_l,occupancy_r,optic_expansion_l,optic_expansion_r,flash_l,flash_r,odor_l,odor_r,nearest_food_mm,fly_state,body_sim_s,body_sim_dt,body_wall_dt,body_sim_wall_ratio,body_packet_age_s,body_generation,receptor_odor_l_hz,receptor_odor_r_hz,receptor_warm_hz,receptor_cool_hz,receptor_wind_c_hz,receptor_wind_e_hz,brain_signals_available,brain_walk,brain_turn,brain_escape,brain_backward,brain_groom,brain_wing,brain_arousal,brain_tempo,brain_sleep,brain_nervous,controller_left,controller_right,body_wind_strength,body_wind_direction_deg,body_wind_sensory,body_touch_strength,body_touch_sensory\n"

    var csvLine: String {
        let safeState = flyState.replacingOccurrences(of: ",", with: "_")
        let base = String(format: "%.6f,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.3f,%.7f,%.7f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.3f,%@,%.6f,%.6f,%.6f,%.6f,%.6f,%llu",
                          wallTime, simMs, ratePop, rateLoom, rateDNaL, rateDNaR,
                          rateMDN, rateFwd, rateGroom, rateEscW, loomL, loomR,
                          airPuff, gaitDrive, odorDriveL, odorDriveR,
                          thermoWarmDrive, thermoCoolDrive, windCDrive, windEDrive,
                          temperatureC, bodyVX, bodyYawRate,
                          bodyContactMean, bodyLoomL, bodyLoomR,
                          bodyBrightnessL, bodyBrightnessR, bodyOccupancyL, bodyOccupancyR,
                          bodyOpticExpansionL, bodyOpticExpansionR, bodyFlashL, bodyFlashR,
                          bodyOdorL, bodyOdorR, bodyNearestFoodDistanceMm,
                          safeState, bodySimTime, bodySimDt, bodyWallDt, bodySimWallRatio,
                          bodyPacketAgeS, bodyConnectionGeneration)
        let diagnostic = String(format: ",%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%d,%.5f,%.5f,%d,%d,%.5f,%.5f,%.5f,%.5f,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%d,%.5f,%d\n",
                                rateFoodOdorL, rateFoodOdorR, rateThermoWarm, rateThermoCool,
                                rateWindC, rateWindE, brainSignalsAvailable ? 1 : 0,
                                brainWalkDrive, brainTurnBias, brainEscape ? 1 : 0,
                                brainBackward ? 1 : 0, brainGroomDrive, brainWingDrive,
                                brainArousal, brainTempo, brainSleep ? 1 : 0, brainNervous,
                                bodyControllerLeft, bodyControllerRight,
                                bodyWindStrength, bodyWindDirectionDeg, bodyWindSensory ? 1 : 0,
                                bodyTouchStrength, bodyTouchSensory ? 1 : 0)
        return base + diagnostic
    }
}

/// Single mapping table for direct-neural lab stimulation. These are existing
/// populations only; no synthetic neuron group is created for the lab UI.
func labPopulationIndices(_ sim: MetalSim, role: String) -> [Int] {
    switch role {
    case "GF": return sim.gf
    case "DNa-left": return sim.dnaL
    case "DNa-right": return sim.dnaR
    case "MDN": return sim.mdn
    case "DNp09": return sim.fwd
    case "DNg11": return sim.groom
    case "escW": return sim.escw
    case "LC4/LPLC2": return sim.loomLeft + sim.loomRight
    case "LC4/LPLC2-left": return sim.loomLeft
    case "LC4/LPLC2-right": return sim.loomRight
    case "ascend": return sim.ascend
    case "sens": return sim.sens
    case "ORN-food-left": return sim.foodOdorLeft
    case "ORN-food-right": return sim.foodOdorRight
    case "TRN-warm": return sim.thermoWarm
    case "TRN-cool": return sim.thermoCool
    case "JO-C-wind": return sim.windC
    case "JO-E-wind": return sim.windE
    case "HRN-dry": return sim.hygroDry
    case "HRN-moist": return sim.hygroMoist
    default: return []
    }
}

/// Headless lab protocol test. No socket is opened; queue behavior, tolerant
/// state parsing and direct-neural population selection are exercised directly.
func runLabTest() {
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print((ok ? "PASS" : "FAIL") + "  " + name + (detail.isEmpty ? "" : ": " + detail))
        if !ok { failures += 1 }
    }

    let bridge = FlyGymBridge()
    for i in 0..<100 {
        _ = bridge.sendLab(action: "move_object", target: "box", x: Double(i), y: 0, z: 5)
    }
    check("lab command queue bounded", bridge.pendingLabDepth() == 32,
          "depth=\(bridge.pendingLabDepth()) dropped=\(bridge.labDropped)")
    check("lab queue drops oldest", bridge.labDropped == 68, "dropped=\(bridge.labDropped)")

    let stateLine = #"{"type":"lab_state","t":1.25,"ack":7,"ok":false,"error":"bad target","object_count":3,"temperature":27.0,"wind":0.4,"left_eye_covered":true,"right_eye_covered":false}"#
    let state = parseLabStateLine(Data(stateLine.utf8))
    check("lab_state parse", state?.ack == 7 && state?.ok == false && state?.error == "bad target"
          && state?.objectCount == 3 && state?.leftEyeCovered == true && state?.rightEyeCovered == false)
    check("lab_state type gate", parseLabStateLine(Data(#"{"type":"body","ack":7}"#.utf8)) == nil)
    let event = parseLabEventLine(Data(#"{"type":"lab_event","event":"approach_complete","data":{"id":"x"}}"#.utf8))
    check("lab_event parse", event?.event == "approach_complete")

    var backendStim = FlyGymBodyFeedback()
    backendStim.windStrength = 0.7
    backendStim.windDirectionDeg = -30
    backendStim.windSensory = true
    backendStim.touchStrength = 0.55
    backendStim.touchSensory = true
    let activeBackend = labBackendSensoryState(backendStim)
    backendStim.windSensory = false
    backendStim.touchSensory = false
    let disabledBackend = labBackendSensoryState(backendStim)
    let missingBackend = labBackendSensoryState(nil)
    check("backend body state is authoritative for wind/touch neural source",
          abs(activeBackend.wind - 0.7) < 1e-6
          && abs(activeBackend.windDirectionDeg + 30) < 1e-9
          && abs(activeBackend.touchDrive - 0.119) < 1e-6
          && disabledBackend.wind == 0 && disabledBackend.touchDrive == 0
          && missingBackend.wind == 0 && missingBackend.touchDrive == 0)

    var decodedSignals = BrainSignals()
    decodedSignals.walkDrive = 0.42
    decodedSignals.turnBias = -0.17
    decodedSignals.escape = true
    decodedSignals.backward = true
    decodedSignals.groomDrive = 0.23
    decodedSignals.wingDrive = 0.31
    decodedSignals.arousal = 0.44
    decodedSignals.tempo = 1.25
    decodedSignals.sleep = true
    decodedSignals.nervous = 0.66
    var decodedTelemetry = LabTelemetry()
    decodedTelemetry.applyBrainSignals(decodedSignals)
    check("decoded BrainSignals reach telemetry",
          decodedTelemetry.brainSignalsAvailable
          && abs(decodedTelemetry.brainWalkDrive - 0.42) < 1e-9
          && abs(decodedTelemetry.brainTurnBias + 0.17) < 1e-9
          && decodedTelemetry.brainEscape && decodedTelemetry.brainBackward
          && abs(decodedTelemetry.brainGroomDrive - 0.23) < 1e-9
          && abs(decodedTelemetry.brainWingDrive - 0.31) < 1e-9
          && abs(decodedTelemetry.brainArousal - 0.44) < 1e-9
          && abs(decodedTelemetry.brainTempo - 1.25) < 1e-9
          && decodedTelemetry.brainSleep
          && abs(decodedTelemetry.brainNervous - 0.66) < 1e-9)
    decodedTelemetry.applyBrainSignals(nil)
    check("missing BrainSignals clear telemetry",
          !decodedTelemetry.brainSignalsAvailable
          && decodedTelemetry.brainWalkDrive == 0 && decodedTelemetry.brainTurnBias == 0
          && !decodedTelemetry.brainEscape && !decodedTelemetry.brainBackward
          && decodedTelemetry.brainTempo == 1 && !decodedTelemetry.brainSleep)

    let telemetryBodyLine = #"{"type":"body","t":2.5,"sim_dt":0.003,"wall_dt":0.030,"sim_wall_ratio":0.1,"controller_left":0.22,"controller_right":0.44,"wind_strength":0.7,"wind_direction_deg":45,"wind_sensory":true,"touch_strength":0.55,"touch_sensory":true,"vx":0.004,"yaw_rate":0.2,"contacts":[1,1,1,1,1,1],"odor_left":0.3,"odor_right":0.4}"#
    if let bodyPacket = parseBodyLine(Data(telemetryBodyLine.utf8)) {
        let now = Date()
        var feedback = FlyGymBodyFeedback(bodyPacket)
        feedback.receivedAt = now.addingTimeInterval(-0.125)
        feedback.connectionGeneration = 9
        var bodyTelemetry = LabTelemetry()
        bodyTelemetry.applyBodyFeedback(feedback, now: now)
        check("body timing reaches lab telemetry",
              abs(bodyTelemetry.bodySimTime - 2.5) < 1e-9
              && abs(bodyTelemetry.bodySimDt - 0.003) < 1e-9
              && abs(bodyTelemetry.bodyWallDt - 0.030) < 1e-9
              && abs(bodyTelemetry.bodySimWallRatio - 0.1) < 1e-9
              && abs(bodyTelemetry.bodyControllerLeft - 0.22) < 1e-9
              && abs(bodyTelemetry.bodyControllerRight - 0.44) < 1e-9
              && abs(bodyTelemetry.bodyWindStrength - 0.7) < 1e-9
              && abs(bodyTelemetry.bodyWindDirectionDeg - 45) < 1e-9
              && bodyTelemetry.bodyWindSensory
              && abs(bodyTelemetry.bodyTouchStrength - 0.55) < 1e-9
              && bodyTelemetry.bodyTouchSensory
              && abs(bodyTelemetry.bodyPacketAgeS - 0.125) < 1e-6
              && bodyTelemetry.bodyConnectionGeneration == 9)
        check("body timing columns recorded",
              LabTelemetry.csvHeader.contains("body_sim_s")
              && LabTelemetry.csvHeader.contains("body_sim_dt")
              && LabTelemetry.csvHeader.contains("body_sim_wall_ratio")
              && LabTelemetry.csvHeader.contains("controller_left")
              && LabTelemetry.csvHeader.contains("controller_right")
              && LabTelemetry.csvHeader.contains("body_wind_strength")
              && LabTelemetry.csvHeader.contains("body_touch_strength")
              && bodyTelemetry.csvLine.contains(",2.500000,0.003000,0.030000,0.100000,"))
    } else {
        check("body timing reaches lab telemetry", false, "body packet did not parse")
    }

    if let c = loadConnectome(), let sim = MetalSim(connectome: c, spikeBus: nil, seed: SIM_SEED) {
        sim.perfLogIntervalMs = 0
        let roles = ["GF", "DNa-left", "DNa-right", "MDN", "DNp09", "DNg11", "escW",
                     "LC4/LPLC2-left", "LC4/LPLC2-right", "LC4/LPLC2", "ascend", "sens",
                     "ORN-food-left", "ORN-food-right", "TRN-warm", "TRN-cool",
                     "JO-C-wind", "JO-E-wind", "HRN-dry", "HRN-moist"]
        check("direct-neural roles map to existing neurons",
              roles.allSatisfy { !labPopulationIndices(sim, role: $0).isEmpty })
        check("FlyWire sensory group counts",
              sim.foodOdorLeft.count == 69 && sim.foodOdorRight.count == 66
              && sim.thermoWarm.count == 7 && sim.thermoCool.count == 9
              && sim.windC.count == 56 && sim.windE.count == 363,
              "odor=\(sim.foodOdorLeft.count)/\(sim.foodOdorRight.count) thermo=\(sim.thermoWarm.count)/\(sim.thermoCool.count) wind=\(sim.windC.count)/\(sim.windE.count)")
        sim.setModeledSensoryDrive(.foodOdorLeft, indices: sim.foodOdorLeft, strength: 0.05)
        let odorCurrent = sim.debugExternalInput(sim.foodOdorLeft)
        check("persistent sensory current reaches ORN group",
              odorCurrent.count == sim.foodOdorLeft.count
              && odorCurrent.allSatisfy { abs($0 - 0.05) < 1e-6 })
        sim.clearModeledSensoryDrives()
        check("modeled sensory clear zeros ORN current",
              sim.debugExternalInput(sim.foodOdorLeft).allSatisfy { abs($0) < 1e-8 })
        sim.setModeledSensoryDrive(.foodOdorLeft, indices: sim.foodOdorLeft, strength: 0.05)
        sim.reset(seed: SIM_SEED)
        check("brain reset clears persistent sensory current",
              sim.debugExternalInput(sim.foodOdorLeft).allSatisfy { abs($0) < 1e-8 })

        // Gain sanity: a modeled odor current should make its receptor group
        // more active than the same seeded baseline. This deliberately tests a
        // receptor response only, never a scripted downstream behavior.
        let odorSet = Set(sim.foodOdorLeft)
        func odorSpikes(_ drive: Float) -> Int {
            sim.reset(seed: SIM_SEED)
            sim.perfLogIntervalMs = 0
            sim.setModeledSensoryDrive(.foodOdorLeft, indices: sim.foodOdorLeft, strength: drive)
            var count = 0
            for _ in 0..<150 {
                sim.step(1)
                count += sim.lastStepSpikes().reduce(0) { $0 + (odorSet.contains(Int($1)) ? 1 : 0) }
            }
            return count
        }
        let odorBaselineSpikes = odorSpikes(0)
        let odorDrivenSpikes = odorSpikes(0.060)
        check("modeled odor raises ORN receptor spiking",
              odorDrivenSpikes > odorBaselineSpikes,
              "baseline=\(odorBaselineSpikes) driven=\(odorDrivenSpikes)")

        // End-to-end calibration for the shipped UI defaults. A 5 mm food
        // marker at (60, 0, 5) mm relative to a nominal thorax at z=0.7 mm
        // produces the same isotropic LabWorld concentration used by Python;
        // frontal bearing splits it equally across the two antenna channels.
        // The Coordinator's bounded compressive transduction must make that
        // ordinary placement measurable without raising the 0.060 max current.
        let defaultCenterDistance = sqrt(60.0 * 60.0 + 4.3 * 4.3)
        let defaultSurfaceDistance = max(0.0, defaultCenterDistance - 2.5)
        let defaultConcentration = exp(-defaultSurfaceDistance / 30.0)
        let defaultOdorLeft = Float(0.5 * defaultConcentration)
        let defaultFoodDrive: Float = 0.060 * sqrt(sqrt(defaultOdorLeft))
        let defaultFoodSpikes = odorSpikes(defaultFoodDrive)
        check("default UI food geometry raises ORN receptor spiking",
              defaultFoodDrive > 0 && defaultFoodDrive <= 0.060
              && defaultFoodSpikes > odorBaselineSpikes,
              String(format: "odor=%.4f current=%.4f baseline=%d driven=%d",
                     defaultOdorLeft, defaultFoodDrive, odorBaselineSpikes, defaultFoodSpikes))

        func receptorSpikes(_ indices: [Int], channel: MetalSim.ModeledSensoryChannel,
                            drive: Float) -> Int {
            let set = Set(indices)
            sim.reset(seed: SIM_SEED)
            sim.perfLogIntervalMs = 0
            sim.setModeledSensoryDrive(channel, indices: indices, strength: drive)
            var count = 0
            for _ in 0..<150 {
                sim.step(1)
                count += sim.lastStepSpikes().reduce(0) { $0 + (set.contains(Int($1)) ? 1 : 0) }
            }
            return count
        }
        func receptorCheck(_ name: String, indices: [Int],
                           channel: MetalSim.ModeledSensoryChannel, drive: Float) {
            let baseline = receptorSpikes(indices, channel: channel, drive: 0)
            let driven = receptorSpikes(indices, channel: channel, drive: drive)
            check(name, driven > baseline,
                  "baseline=\(baseline) driven=\(driven) current=\(drive)")
        }
        receptorCheck("warm TRN modeled drive raises receptor spiking",
                      indices: sim.thermoWarm, channel: .thermoWarm, drive: 0.060)
        receptorCheck("cool TRN modeled drive raises receptor spiking",
                      indices: sim.thermoCool, channel: .thermoCool, drive: 0.060)
        receptorCheck("JO-C wind modeled drive raises receptor spiking",
                      indices: sim.windC, channel: .windC, drive: 0.055)
        receptorCheck("JO-E wind modeled drive raises receptor spiking",
                      indices: sim.windE, channel: .windE, drive: 0.055)
        var receptorTelemetry = LabTelemetry()
        receptorTelemetry.applyReceptorRates(sim)
        check("receptor EMA rates reach telemetry",
              abs(receptorTelemetry.rateFoodOdorL - Double(sim.rateFoodOdorL)) < 1e-9
              && abs(receptorTelemetry.rateFoodOdorR - Double(sim.rateFoodOdorR)) < 1e-9
              && abs(receptorTelemetry.rateThermoWarm - Double(sim.rateThermoWarm)) < 1e-9
              && abs(receptorTelemetry.rateThermoCool - Double(sim.rateThermoCool)) < 1e-9
              && abs(receptorTelemetry.rateWindC - Double(sim.rateWindC)) < 1e-9
              && abs(receptorTelemetry.rateWindE - Double(sim.rateWindE)) < 1e-9
              && receptorTelemetry.rateWindE > 0,
              String(format: "ORN L/R %.1f/%.1f Hz · JO-E %.1f Hz",
                     receptorTelemetry.rateFoodOdorL, receptorTelemetry.rateFoodOdorR,
                     receptorTelemetry.rateWindE))
        sim.reset(seed: SIM_SEED)
        check("unknown neural role rejected", labPopulationIndices(sim, role: "invented").isEmpty)
    } else {
        check("direct-neural role mapping", false, "could not initialize MetalSim")
    }

    // Recording is part of the user-facing lab contract. Exercise the async
    // writer in a temporary directory so stop() cannot drop the final queued
    // telemetry/event and no test artifact reaches ~/Documents.
    let fm = FileManager.default
    let recorderRoot = fm.temporaryDirectory
        .appendingPathComponent("siliconfly-recorder-test-\(UUID().uuidString)", isDirectory: true)
    let recorder = ExperimentRecorder(baseDirectory: recorderRoot)
    if let recordingPath = recorder.start() {
        var sample = LabTelemetry()
        sample.simMs = 42
        sample.odorDriveL = 0.04
        sample.bodyOdorL = 0.7
        sample.bodyNearestFoodDistanceMm = 11.5
        sample.rateFoodOdorL = 23.5
        sample.brainSignalsAvailable = true
        sample.brainWalkDrive = 0.42
        sample.brainTurnBias = -0.17
        sample.flyState = "walking"
        recorder.append(sample)
        recorder.mark(kind: "lab_test_marker", detail: "flush")
        recorder.stop()
        recorder.flushForTesting()

        let metadata = (try? String(contentsOfFile: recordingPath + "/metadata.json", encoding: .utf8)) ?? ""
        let telemetry = (try? String(contentsOfFile: recordingPath + "/telemetry.csv", encoding: .utf8)) ?? ""
        let events = (try? String(contentsOfFile: recordingPath + "/events.jsonl", encoding: .utf8)) ?? ""
        check("recorder writes V2 metadata", metadata.contains("SiliconFly Virtual Fly Lab V2"))
        check("recorder flushes V2 telemetry on stop",
              telemetry.contains("odor_drive_l") && telemetry.contains("nearest_food_mm")
              && telemetry.contains("receptor_odor_l_hz")
              && telemetry.contains("brain_signals_available")
              && telemetry.contains("brain_walk")
              && telemetry.contains(",42,"))
        check("recorder preserves start/marker/stop events",
              events.contains("recording_started") && events.contains("lab_test_marker")
              && events.contains("recording_stopped"))
    } else {
        check("recorder starts in temporary directory", false)
    }
    try? fm.removeItem(at: recorderRoot)
    print(failures == 0 ? "ALL LAB TESTS PASS" : "\(failures) LAB TEST FAILURES")
    exit(failures == 0 ? 0 : 1)
}
