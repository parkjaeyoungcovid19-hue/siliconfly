// LabWindow.swift — AppKit Virtual Fly Lab V2 control/telemetry window.

import Cocoa

private final class LabFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class LabWindowController: NSWindowController, NSWindowDelegate {
    private unowned let coordinator: Coordinator
    private let bridge: FlyGymBridge?
    private let recorder = ExperimentRecorder()
    private var timer: Timer?

    private let protocolLabel = NSTextField(labelWithString: "FlyGym bridge — starting…")
    private let remoteStateLabel = NSTextField(labelWithString: "Environment — waiting for state…")
    private let recorderLabel = NSTextField(labelWithString: "not recording")
    private let freshnessLabel = NSTextField(labelWithString: "Packets — waiting for body/environment telemetry…")
    private let commandDiagnosticsLabel = NSTextField(wrappingLabelWithString: "Commands — no command sent yet")
    private let signalPathLabel = NSTextField(wrappingLabelWithString: "Signal path — waiting for telemetry…")
    private let temperatureModeStatusLabel = NSTextField(wrappingLabelWithString: "Neural input: OFF — environment-only temperature is recorded without neural input.")

    private let objectID = NSTextField(string: "stimulus")
    private let objectShape = NSPopUpButton(frame: .zero, pullsDown: false)
    private let objectX = NSTextField(string: "60")
    private let objectY = NSTextField(string: "0")
    private let objectZ = NSTextField(string: "5")
    private let objectSize = NSTextField(string: "5")
    private let objectSpeed = NSTextField(string: "12")
    private let objectEndDistance = NSTextField(string: "8")

    private let windStrength = NSTextField(string: "0.7")
    private let windDuration = NSTextField(string: "500")
    private let windDirection = NSTextField(string: "0")
    private let windPhysical = NSButton(checkboxWithTitle: "physical force", target: nil, action: nil)
    private let windSensory = NSButton(checkboxWithTitle: "sensory input", target: nil, action: nil)
    private let windContinuous = NSButton(checkboxWithTitle: "continuous", target: nil, action: nil)
    private let touchStrength = NSTextField(string: "0.55")
    private let touchDuration = NSTextField(string: "150")
    private let touchTarget = NSPopUpButton(frame: .zero, pullsDown: false)
    private let temperature = NSTextField(string: "25")
    private let temperatureMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let flashEye = NSPopUpButton(frame: .zero, pullsDown: false)
    private let flashIntensity = NSTextField(string: "1.0")
    private let flashDuration = NSTextField(string: "100")

    private let brainRole = NSPopUpButton(frame: .zero, pullsDown: false)
    private let brainStrength = NSTextField(string: "0.30")
    private let brainDuration = NSTextField(string: "300")

    private let neuralGraph = LabGraphView(frame: .zero,
                                           names: ["brain", "loom", "walk", "back", "groom"])
    private let commandGraph = LabGraphView(frame: .zero,
                                           names: ["DNa L", "DNa R", "MDN", "DNp09", "DNg11", "escW"])
    private let sensoryGraph = LabGraphView(frame: .zero,
                                            names: ["loom L", "loom R", "legacy air", "gait"])
    private let flywireSensoryGraph = LabGraphView(frame: .zero,
                                                   names: ["food L", "food R", "warm", "cool", "wind C", "wind E"])
    private let bodyGraph = LabGraphView(frame: .zero,
                                         names: ["speed×20", "turn÷5", "contact", "eye loom", "food L", "food R", "distance÷100"])
    private let visionGraph = LabGraphView(frame: .zero,
                                           names: ["light L", "light R", "target L", "target R", "expand L", "expand R"])
    private let bodyTelemetryLabel = NSTextField(labelWithString: "Movement — speed 0.0000 m/s · turn 0.00 rad/s · contact 0.00")
    private let foodTelemetryLabel = NSTextField(labelWithString: "Food odor — left 0.000 · right 0.000 · nearest source: none")
    private let visionTelemetryLabel = NSTextField(labelWithString: "Vision — expansion L/R 0.000/0.000 · brightness L/R 0.000/0.000")
    private var lastPreset: String?
    private var eyeButtons: [NSButton] = []
    private var eyeCommandPendingID: Int?
    private var eyeCommandStartedAt: Date?
    private var eyeCommandSide: String?
    private var eyeCommandCovered: Bool?
    private var lastCommandID: Int?
    private var lastCommandAction = "none"

    init(coordinator: Coordinator, bridge: FlyGymBridge?) {
        self.coordinator = coordinator
        self.bridge = bridge
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Thongpari Fly Neuron Sim — Virtual Fly Lab V2"
        w.minSize = NSSize(width: 760, height: 600)
        super.init(window: w)
        w.delegate = self
        buildUI()
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var hasRecordingToFinish: Bool { recorder.isRecording || recorder.isStopping }

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the controller reusable from the menu; telemetry recording can
        // intentionally continue after the window is hidden.
    }

    private func buildUI() {
        guard let window else { return }
        let root = NSViewController()
        let rootView = NSView()
        root.view = rootView

        protocolLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        protocolLabel.textColor = .labelColor
        protocolLabel.lineBreakMode = .byTruncatingMiddle
        remoteStateLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        remoteStateLabel.textColor = .secondaryLabelColor
        remoteStateLabel.lineBreakMode = .byTruncatingMiddle
        freshnessLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        freshnessLabel.textColor = .secondaryLabelColor
        freshnessLabel.lineBreakMode = .byTruncatingMiddle

        let intro = NSTextField(wrappingLabelWithString:
            "Change the fly's environment or sensory input, then watch the whole-brain model respond. " +
            "Physical and sensory controls do not script a behavior; direct-neural controls are explicitly marked.")
        intro.font = NSFont.systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        intro.maximumNumberOfLines = 2

        let statusStack = NSStackView(views: [protocolLabel, freshnessLabel, remoteStateLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 3
        statusStack.edgeInsets = NSEdgeInsets(top: 4, left: 2, bottom: 6, right: 2)

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("World", worldPage()))
        tabs.addTabViewItem(tab("Stimuli", sensesPage()))
        tabs.addTabViewItem(tab("Brain", brainPage()))
        tabs.addTabViewItem(tab("Live Data", metricsPage()))
        tabs.addTabViewItem(tab("Experiments", experimentPage()))

        root.addChild(tabs)
        let stack = NSStackView(views: [intro, statusStack, tabs.view])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -12),
            tabs.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 500)
        ])
        window.contentViewController = root
    }

    private func tab(_ title: String, _ vc: NSViewController) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: vc)
        item.label = title
        return item
    }

    private func page(_ views: [NSView]) -> NSViewController {
        let vc = NSViewController()
        let view = NSView()
        vc.view = view
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let document = LabFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -14)
        ])
        for child in views where child.identifier?.rawValue == "SiliconFlyLabSection" {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return vc
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = 8
        return s
    }

    private func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.textColor = .secondaryLabelColor
        l.font = NSFont.systemFont(ofSize: 11.5)
        l.maximumNumberOfLines = 4
        return l
    }

    private func field(_ f: NSTextField, width: CGFloat = 70) -> NSTextField {
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: 12)
        return l
    }

    private func button(_ title: String, _ selector: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: selector)
        b.bezelStyle = .rounded
        return b
    }

    private func section(_ title: String,
                         kind: LabInterventionKind? = nil,
                         help: String? = nil,
                         views: [NSView]) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        var content: [NSView] = [titleLabel]

        if let kind {
            let explanation: String
            switch kind {
            case .physical:
                explanation = "PHYSICAL · changes the actual MuJoCo/FlyGym world or body"
            case .sensoryModel:
                explanation = "SENSORY MODEL · converts a stimulus into existing modeled sensory inputs"
            case .directNeural:
                explanation = "DIRECT NEURAL · bypasses the sense organ and stimulates an existing FlyWire group"
            }
            let tag = NSTextField(labelWithString: explanation)
            tag.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
            tag.textColor = .secondaryLabelColor
            content.append(tag)
        }
        if let help { content.append(note(help)) }
        content.append(contentsOf: views)

        let divider = NSBox()
        divider.boxType = .separator
        content.append(divider)

        let stack = NSStackView(views: content)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 2, bottom: 4, right: 2)
        stack.identifier = NSUserInterfaceItemIdentifier("SiliconFlyLabSection")
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func addPopupItems(_ popup: NSPopUpButton, _ items: [(String, String)]) {
        popup.removeAllItems()
        for (title, value) in items {
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = value
        }
    }

    private func selectedValue(_ popup: NSPopUpButton, fallback: String) -> String {
        (popup.selectedItem?.representedObject as? String) ?? fallback
    }

    private func selectPopupValue(_ popup: NSPopUpButton, _ value: String) {
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == value }) {
            popup.select(item)
        }
    }

    private func worldPage() -> NSViewController {
        _ = field(objectID, width: 120)
        [objectX, objectY, objectZ, objectSize, objectSpeed, objectEndDistance].forEach { _ = field($0) }
        addPopupItems(objectShape, [
            ("Box", "box"),
            ("Sphere", "sphere"),
            ("Wall", "wall"),
            ("Food / odor source", "food")
        ])
        return page([
            section("Create or edit an object", kind: .physical,
                    help: "Position uses millimetres: X = forward/back, Y = left/right, Z = height. Give each object a short name so you can move or remove it later.",
                    views: [
                        row([label("Type"), objectShape, label("Name"), objectID]),
                        row([label("X (mm)"), objectX, label("Y (mm)"), objectY,
                             label("Z (mm)"), objectZ, label("Size (mm)"), objectSize]),
                        row([button("Create", #selector(createObject)),
                             button("Update position", #selector(moveObject)),
                             button("Update size", #selector(resizeObject)),
                             button("Remove", #selector(deleteObject))])
                    ]),
            section("Move an object toward the fly", kind: .physical,
                    help: "This moves the selected object only. The fly is never commanded to approach or escape; any response comes from the model.",
                    views: [
                        row([label("Speed (mm/s)"), objectSpeed,
                             label("Stop distance (mm)"), objectEndDistance,
                             button("Start approach", #selector(approachObject))])
                    ]),
            section("Food marker", kind: .sensoryModel,
                    help: "Food is a non-colliding odor source. Its position creates left/right odor signals that drive the real ORN_DM1/VA2 FlyWire groups. Taste, reward, feeding, and automatic food-seeking are not modeled.",
                    views: []),
            section("Reset", help: "Use the smallest reset you need. Reset everything clears the world, body, brain state, modeled stimuli, eye covers, and live graphs.",
                    views: [
                        row([button("Reset world", #selector(resetWorld)),
                             button("Reset body", #selector(resetBody)),
                             button("Reset brain", #selector(resetBrain)),
                             button("Reset everything", #selector(resetAll))])
                    ])
        ])
    }

    private func sensesPage() -> NSViewController {
        [windStrength, windDuration, windDirection, touchStrength, touchDuration, temperature,
         flashIntensity, flashDuration].forEach { _ = field($0) }
        windPhysical.state = .on; windSensory.state = .on
        windPhysical.title = "Apply physical force"
        windSensory.title = "Drive wind receptors (JO-C/E)"
        windContinuous.title = "Keep on until stopped"
        addPopupItems(touchTarget, [
            ("Thorax", "thorax"), ("Head", "head"), ("Abdomen", "abdomen"),
            ("Left front leg", "left_front_leg"), ("Left middle leg", "left_middle_leg"),
            ("Left hind leg", "left_hind_leg"), ("Right front leg", "right_front_leg"),
            ("Right middle leg", "right_middle_leg"), ("Right hind leg", "right_hind_leg")
        ])
        addPopupItems(temperatureMode, [
            ("FlyWire thermosensory (TRN)", "flywire_sensory"),
            ("Environment only (record value)", "environment_only"),
            ("Legacy physiology (tempo model)", "modeled_physiology")
        ])
        selectPopupValue(temperatureMode, "environment_only")
        temperatureMode.target = self
        temperatureMode.action = #selector(temperatureModeChanged)
        addPopupItems(flashEye, [("Left eye", "left"), ("Right eye", "right"), ("Both eyes", "both")])

        let coverLeftButton = button("Cover left eye", #selector(coverLeft))
        let restoreLeftButton = button("Open left eye", #selector(restoreLeft))
        let coverRightButton = button("Cover right eye", #selector(coverRight))
        let restoreRightButton = button("Open right eye", #selector(restoreRight))
        eyeButtons = [coverLeftButton, restoreLeftButton, coverRightButton, restoreRightButton]

        temperatureModeStatusLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        temperatureModeStatusLabel.maximumNumberOfLines = 2
        updateTemperatureModeStatus()
        return page([
            section("Vision", kind: .sensoryModel,
                    help: "Eye cover changes the rendered input reaching that eye. Flash changes full-field brightness telemetry only; it does not invent a direct flash-to-escape circuit.",
                    views: [
                        row([coverLeftButton, restoreLeftButton, coverRightButton, restoreRightButton]),
                        row([label("Flash"), flashEye, label("Intensity (0–1)"), flashIntensity,
                             label("Duration (ms)"), flashDuration, button("Apply flash", #selector(applyFlash))])
                    ]),
            section("Wind", kind: .sensoryModel,
                    help: "Physical force pushes the MuJoCo thorax. Wind-receptor mode drives the real JO-C/E FlyWire groups. Direction is transformed relative to the fly's current body heading.",
                    views: [
                        row([label("Strength (0–1)"), windStrength, label("Direction (°)"), windDirection,
                             label("Duration (ms)"), windDuration]),
                        row([windPhysical, windSensory, windContinuous,
                             button("Apply wind", #selector(applyWind)), button("Stop", #selector(stopWind))])
                    ]),
            section("Touch", kind: .physical,
                    help: "The physical impulse is applied to the selected body part. The neural side is a generic modeled startle/touch channel; it is not body-part-specific tactile transduction.",
                    views: [
                        row([label("Body part"), touchTarget, label("Strength (0–1)"), touchStrength,
                             label("Duration (ms)"), touchDuration, button("Apply touch", #selector(applyTouch))])
                    ]),
            section("Temperature", kind: .sensoryModel,
                    help: "FlyWire thermosensory drives TRN_VP2 for warmth and TRN_VP3a/b for cooling. Environment-only records the value without neural input. The temperature-to-current conversion is a modeling assumption.",
                    views: [
                        row([label("Temperature (°C)"), temperature, label("Mode"), temperatureMode,
                             button("Set temperature", #selector(setTemperature))]),
                        temperatureModeStatusLabel,
                        button("Reset sensory controls", #selector(resetSenses))
                    ])
        ])
    }

    private func brainPage() -> NSViewController {
        addPopupItems(brainRole, [
            ("Giant Fiber — escape pathway (GF)", "GF"),
            ("Turn left channel (DNa-left)", "DNa-left"),
            ("Turn right channel (DNa-right)", "DNa-right"),
            ("Backward locomotion (MDN)", "MDN"),
            ("Forward locomotion (DNp09)", "DNp09"),
            ("Grooming-related output (DNg11)", "DNg11"),
            ("Escape / wing-related output (escW)", "escW"),
            ("Loom-sensitive visual — left (LC4/LPLC2)", "LC4/LPLC2-left"),
            ("Loom-sensitive visual — right (LC4/LPLC2)", "LC4/LPLC2-right"),
            ("Loom-sensitive visual — both (LC4/LPLC2)", "LC4/LPLC2"),
            ("Ascending group", "ascend"),
            ("Legacy sensory group (JO-A/B-like)", "sens"),
            ("Food odor receptors — left (ORN DM1/VA2)", "ORN-food-left"),
            ("Food odor receptors — right (ORN DM1/VA2)", "ORN-food-right"),
            ("Warm receptors (TRN VP2)", "TRN-warm"),
            ("Cool receptors (TRN VP3a/b)", "TRN-cool"),
            ("Wind receptor channel C (JO-C)", "JO-C-wind"),
            ("Wind receptor channel E (JO-E)", "JO-E-wind"),
            ("Dry-air receptors (HRN VP4)", "HRN-dry"),
            ("Moist-air receptors (HRN VP5)", "HRN-moist")
        ])
        _ = field(brainStrength); _ = field(brainDuration)
        return page([
            section("Direct population stimulation", kind: .directNeural,
                    help: "Use this only when you intentionally want to bypass the physical stimulus or sense organ. The selected existing FlyWire population is stimulated directly; downstream whole-brain dynamics still run normally.",
                    views: [
                        row([label("Population"), brainRole]),
                        row([label("Strength"), brainStrength, label("Duration (ms)"), brainDuration,
                             button("Stimulate", #selector(stimulateBrain))])
                    ]),
            section("How to interpret common choices",
                    help: "GF is an escape-pathway probe; DNp09 is associated with forward locomotor output; MDN with backward locomotion; DNa channels with turning; DNg11 with grooming-related output. These labels describe the modeled population readout, not a guaranteed behavior.",
                    views: [])
        ])
    }

    private func metricsPage() -> NSViewController {
        neuralGraph.fixedRange = 0...220
        commandGraph.fixedRange = 0...220
        sensoryGraph.fixedRange = 0...1.2
        flywireSensoryGraph.fixedRange = 0...0.065
        flywireSensoryGraph.valueDecimals = 3
        flywireSensoryGraph.unitLabel = "injected current · sim units"
        bodyGraph.fixedRange = -1.2...1.2
        visionGraph.fixedRange = 0...1.05
        for status in [bodyTelemetryLabel, foodTelemetryLabel, visionTelemetryLabel] {
            status.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            status.textColor = .secondaryLabelColor
        }
        commandDiagnosticsLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        commandDiagnosticsLabel.textColor = .secondaryLabelColor
        signalPathLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        signalPathLabel.textColor = .labelColor
        signalPathLabel.maximumNumberOfLines = 0
        signalPathLabel.lineBreakMode = .byWordWrapping
        for g in [neuralGraph, commandGraph, sensoryGraph, flywireSensoryGraph, bodyGraph, visionGraph] {
            g.translatesAutoresizingMaskIntoConstraints = false
            g.heightAnchor.constraint(equalToConstant: 138).isActive = true
            g.widthAnchor.constraint(greaterThanOrEqualToConstant: 700).isActive = true
        }
        return page([
            section("Signal path — find where a response stops",
                    help: "Read top to bottom. Each line uses only telemetry the current V2 runtime actually exposes; missing stages are labeled instead of guessed.",
                    views: [signalPathLabel, commandDiagnosticsLabel]),
            section("Brain activity",
                    help: "Spike-rate summaries in Hz. ‘walk’, ‘back’, and ‘groom’ are DN population readouts; a higher line means that population is currently more active, not that a behavior is guaranteed.",
                    views: [neuralGraph]),
            section("Descending / motor-related populations",
                    help: "DNa L/R are steering-related descending neurons; MDN is backward-related, DNp09 forward-walking-related, DNg11 grooming-related, and escW escape/wing-related. These are neural rates in Hz, not body commands.",
                    views: [commandGraph]),
            section("Compact sensory inputs",
                    help: "Loom is the left/right visual expansion signal. Gait is body feedback. ‘legacy air’ is the older generic sensory channel and is not the Lab's JO-C/E wind-receptor signal.",
                    views: [sensoryGraph]),
            section("FlyWire sensory groups",
                    help: "Modeled injected current sent to real FlyWire receptor groups: food odor ORNs, warm/cool TRNs, and JO-C/E wind channels. This is simulation current, not a 0–1 normalized score; the expected maxima are about 0.055–0.060.",
                    views: [flywireSensoryGraph, foodTelemetryLabel]),
            section("Body state",
                    help: "For one stable plot, speed is shown ×20, turn rate ÷5, and nearest-food distance ÷100. The exact movement values are shown below the graph.",
                    views: [bodyGraph, bodyTelemetryLabel]),
            section("Rendered-eye vision",
                    help: "Brightness is mean light level; target is the legacy configured-color occupancy; expansion is the generic raw-frame optic-expansion estimate. Expansion is an engineering visual-motion proxy, not reconstructed biological retinotopy.",
                    views: [visionGraph, visionTelemetryLabel]),
            button("Clear live graphs", #selector(clearGraphs))
        ])
    }

    private func experimentPage() -> NSViewController {
        recorderLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        recorderLabel.textColor = .secondaryLabelColor
        recorderLabel.lineBreakMode = .byTruncatingMiddle
        return page([
            section("Record an experiment",
                    help: "Saves metadata, event markers, and telemetry under Documents/ThongpariFlyNeuronSimExperiments. Start recording before the baseline if you want a complete trial.",
                    views: [
                        row([button("Start recording", #selector(startRecording)), button("Stop & save", #selector(stopRecording))]),
                        recorderLabel
                    ]),
            section("Ready-made physical / sensory trials",
                    help: "These presets use the same controls available in World and Stimuli. They move objects or apply a stimulus, but never command the fly's behavior.",
                    views: [
                        row([button("Frontal looming object", #selector(presetFrontalLoom)),
                             button("Loom from left", #selector(presetLeftLoom)),
                             button("Loom from right", #selector(presetRightLoom))]),
                        row([button("Loom with left eye covered", #selector(presetCoveredLoom)),
                             button("Wind puff", #selector(presetWind)), button("Thorax touch", #selector(presetTouch))])
                    ]),
            section("Ready-made direct-neural trials", kind: .directNeural,
                    help: "These are explicit neural probes. They bypass the natural stimulus and stimulate an existing neural population directly.",
                    views: [
                        row([button("GF", #selector(presetGF)), button("DNa left", #selector(presetDNa)),
                             button("DNa right", #selector(presetDNaRight)), button("MDN", #selector(presetMDN)),
                             button("DNp09", #selector(presetDNp09))])
                    ]),
            section("Repeat / reset",
                    help: "Replay last preset runs the most recent preset again. Reset everything returns the lab to a clean starting state before a new trial.",
                    views: [
                        row([button("Replay last preset", #selector(replayLastPreset)),
                             button("Reset everything", #selector(resetAll))])
                    ]),
            section("Timeline markers",
                    help: "Markers do not change the simulation. They only label the recording so you can line up baseline, stimulus, and observation periods later.",
                    views: [
                        row([button("Baseline", #selector(markBaseline)), button("Stimulus ON", #selector(markStimulusOn)),
                             button("Stimulus OFF", #selector(markStimulusOff)), button("Observation", #selector(markObservation))])
                    ])
        ])
    }

    private func d(_ f: NSTextField, fallback: Double = 0) -> Double {
        let x = f.doubleValue
        return x.isFinite ? x : fallback
    }
    private func ms(_ f: NSTextField, fallback: Int) -> Int { max(1, min(60_000, f.integerValue == 0 ? fallback : f.integerValue)) }
    private var target: String { objectID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "stimulus" : objectID.stringValue }

    private func setEyeButtonsEnabled(_ enabled: Bool) {
        eyeButtons.forEach { $0.isEnabled = enabled }
    }

    private func clearEyePending() {
        eyeCommandPendingID = nil
        eyeCommandStartedAt = nil
        eyeCommandSide = nil
        eyeCommandCovered = nil
        setEyeButtonsEnabled(true)
    }

    private func updateTemperatureModeStatus() {
        switch selectedValue(temperatureMode, fallback: "environment_only") {
        case "flywire_sensory":
            temperatureModeStatusLabel.stringValue = "Neural input: ON — temperature drives FlyWire TRN warm/cool receptor groups."
            temperatureModeStatusLabel.textColor = .labelColor
        case "modeled_physiology":
            temperatureModeStatusLabel.stringValue = "Neural input: TEMPO MODEL — changes the legacy physiology tempo path; it does not drive FlyWire TRNs."
            temperatureModeStatusLabel.textColor = .secondaryLabelColor
        default:
            temperatureModeStatusLabel.stringValue = "Neural input: OFF — environment-only temperature is recorded without neural input."
            temperatureModeStatusLabel.textColor = .systemOrange
        }
    }

    @objc private func temperatureModeChanged() {
        updateTemperatureModeStatus()
    }

    @discardableResult
    private func send(_ action: String, target: String? = nil,
                      x: Double? = nil, y: Double? = nil, z: Double? = nil,
                      size: Double? = nil, speed: Double? = nil,
                      strength: Double? = nil, durationMs: Int? = nil,
                      value: Double? = nil, directionDeg: Double? = nil,
                      endDistance: Double? = nil, physical: Bool? = nil,
                      sensory: Bool? = nil, continuous: Bool? = nil,
                      mode: String? = nil) -> Int? {
        guard let bridge else {
            protocolLabel.stringValue = "FlyGym bridge — disabled (launch with --flygym for physical-world controls)"
            return nil
        }
        let id = bridge.sendLab(action: action, target: target, x: x, y: y, z: z,
                                size: size, speed: speed, strength: strength,
                                durationMs: durationMs, value: value,
                                directionDeg: directionDeg, endDistance: endDistance,
                                physical: physical, sensory: sensory,
                                continuous: continuous, mode: mode)
        lastCommandID = id
        lastCommandAction = action
        recorder.mark(kind: "lab_command", detail: "\(action) target=\(target ?? "-")", commandID: id)
        return id
    }

    @objc private func createObject() {
        let shape = selectedValue(objectShape, fallback: "box")
        let action: String
        switch shape {
        case "sphere": action = "spawn_sphere"
        case "wall": action = "spawn_wall"
        case "food": action = "spawn_food"
        default: action = "spawn_box"
        }
        send(action, target: target, x: d(objectX), y: d(objectY), z: d(objectZ),
             size: max(0.1, d(objectSize, fallback: 5)))
    }
    @objc private func moveObject() { send("move_object", target: target, x: d(objectX), y: d(objectY), z: d(objectZ)) }
    @objc private func resizeObject() { send("resize_object", target: target, size: max(0.1, d(objectSize, fallback: 5))) }
    @objc private func deleteObject() { send("delete_object", target: target) }
    @objc private func approachObject() {
        send("approach_object", target: target,
             speed: max(0.1, d(objectSpeed, fallback: 12)),
             endDistance: max(0.5, d(objectEndDistance, fallback: 8)))
    }
    @objc private func resetWorld() {
        coordinator.labResetModeledStimuli()
        clearEyePending()
        temperature.stringValue = "25"
        selectPopupValue(temperatureMode, "environment_only")
        updateTemperatureModeStatus()
        send("reset_world")
        recorder.mark(kind: "reset", detail: "world+modeled environment")
    }
    @objc private func resetBody() { send("reset_body"); recorder.mark(kind: "reset", detail: "body") }
    @objc private func resetBrain() { coordinator.labResetBrain(); recorder.mark(kind: "reset", detail: "brain") }
    @objc private func resetAll() {
        coordinator.labResetBrain()
        coordinator.labResetModeledStimuli()
        clearEyePending()
        temperature.stringValue = "25"
        selectPopupValue(temperatureMode, "environment_only")
        updateTemperatureModeStatus()
        send("reset_world")
        send("reset_body")
        send("restore_eyes")
        neuralGraph.clear(); sensoryGraph.clear(); flywireSensoryGraph.clear(); bodyGraph.clear(); visionGraph.clear()
        commandGraph.clear()
        recorder.mark(kind: "reset", detail: "all")
    }

    private func eye(_ side: String, covered: Bool) {
        guard eyeCommandPendingID == nil else {
            commandDiagnosticsLabel.stringValue = "Commands — eye change waiting for previous eye command acknowledgement"
            return
        }
        if let id = send("set_eye_state", target: side, value: covered ? 1 : 0) {
            eyeCommandPendingID = id
            eyeCommandStartedAt = Date()
            eyeCommandSide = side
            eyeCommandCovered = covered
            setEyeButtonsEnabled(false)
        }
    }
    @objc private func coverLeft() { eye("left", covered: true) }
    @objc private func restoreLeft() { eye("left", covered: false) }
    @objc private func coverRight() { eye("right", covered: true) }
    @objc private func restoreRight() { eye("right", covered: false) }

    @objc private func applyFlash() {
        let eye = selectedValue(flashEye, fallback: "both")
        let intensity = max(0, min(1, d(flashIntensity, fallback: 1)))
        let duration = ms(flashDuration, fallback: 100)
        send("flash_eye", target: eye, strength: intensity, durationMs: duration)
        recorder.mark(kind: "sensory_model", detail: "flash eye=\(eye) intensity=\(intensity) duration_ms=\(duration)")
    }

    @objc private func applyWind() {
        let strength = max(0, min(1, d(windStrength, fallback: 0.7)))
        let duration = ms(windDuration, fallback: 500)
        let direction = d(windDirection, fallback: 0).truncatingRemainder(dividingBy: 360)
        let physical = windPhysical.state == .on
        let sensory = windSensory.state == .on
        let continuous = windContinuous.state == .on
        if sensory {
            coordinator.labApplyWind(strength: Float(strength), directionDeg: direction,
                                     durationMs: duration, continuous: continuous)
        } else {
            coordinator.labStopWind()
        }
        send("wind", strength: strength, durationMs: duration, directionDeg: direction,
             physical: physical, sensory: sensory, continuous: continuous)
        recorder.mark(kind: physical ? "physical" : "sensory_model",
                      detail: "wind strength=\(strength) dir=\(direction) physical=\(physical) sensory=\(sensory) continuous=\(continuous)")
    }

    @objc private func stopWind() {
        coordinator.labStopWind()
        send("stop_wind")
        recorder.mark(kind: "stimulus_off", detail: "wind")
    }

    @objc private func applyTouch() {
        let strength = max(0, min(1, d(touchStrength, fallback: 0.55)))
        let duration = ms(touchDuration, fallback: 150)
        let bodyTarget = selectedValue(touchTarget, fallback: "thorax")
        coordinator.labApplyTouch(strength: Float(strength), durationMs: duration)
        send("touch", target: bodyTarget, strength: strength, durationMs: duration)
        recorder.mark(kind: "physical+sensory_model", detail: "touch target=\(bodyTarget) strength=\(strength) duration_ms=\(duration)")
    }

    @objc private func setTemperature() {
        let c = max(10, min(40, d(temperature, fallback: 25)))
        temperature.doubleValue = c
        let mode = selectedValue(temperatureMode, fallback: "flywire_sensory")
        updateTemperatureModeStatus()
        coordinator.labSetTemperature(celsius: c,
                                      modeledPhysiology: mode == "modeled_physiology",
                                      flywireSensory: mode == "flywire_sensory")
        send("temperature", value: c, mode: mode)
        recorder.mark(kind: mode == "environment_only" ? "environment_record_only" : "sensory_model",
                      detail: "temperature_c=\(c) mode=\(mode)")
    }

    @objc private func resetSenses() {
        coordinator.labResetModeledStimuli()
        clearEyePending()
        windStrength.stringValue = "0.7"; temperature.stringValue = "25"
        selectPopupValue(temperatureMode, "environment_only")
        updateTemperatureModeStatus()
        send("stop_wind")
        send("restore_eyes")
        send("temperature", value: 25, mode: "environment_only")
        recorder.mark(kind: "reset", detail: "modeled sensory interventions")
    }

    @objc private func stimulateBrain() {
        let role = selectedValue(brainRole, fallback: "GF")
        let strength = Float(max(0, min(2, d(brainStrength, fallback: 0.3))))
        let duration = ms(brainDuration, fallback: 300)
        coordinator.labStimulatePopulation(role, strength: strength, durationMs: duration)
        recorder.mark(kind: "direct_neural", detail: "role=\(role) strength=\(strength) duration_ms=\(duration)")
    }

    private func runPreset(_ name: String) {
        lastPreset = name
        recorder.mark(kind: "preset", detail: name)
        switch name {
        case "frontal_loom", "left_loom", "right_loom", "left_eye_covered_loom":
            coordinator.labResetBrain()
            coordinator.labResetModeledStimuli()
            clearEyePending()
            temperature.stringValue = "25"
            selectPopupValue(temperatureMode, "environment_only")
            updateTemperatureModeStatus()
            send("reset_world"); send("reset_body")
            if name == "left_eye_covered_loom" { eye("left", covered: true) }
            let y: Double = name == "left_loom" ? 22 : (name == "right_loom" ? -22 : 0)
            let id = "preset_loom"
            send("spawn_box", target: id, x: 60, y: y, z: 5, size: 10)
            send("approach_object", target: id, speed: 80, endDistance: 8)
        case "wind_puff":
            windStrength.stringValue = "0.7"; windDirection.stringValue = "0"; windDuration.stringValue = "500"
            windPhysical.state = .on; windSensory.state = .on; windContinuous.state = .off
            applyWind()
        case "thorax_touch":
            selectPopupValue(touchTarget, "thorax")
            touchStrength.stringValue = "0.55"; touchDuration.stringValue = "150"
            applyTouch()
        case "gf": presetStim(role: "GF", strength: 0.5, duration: 40)
        case "dna_left": presetStim(role: "DNa-left", strength: 0.3, duration: 900)
        case "dna_right": presetStim(role: "DNa-right", strength: 0.3, duration: 900)
        case "mdn": presetStim(role: "MDN", strength: 0.3, duration: 600)
        case "dnp09": presetStim(role: "DNp09", strength: 0.25, duration: 1200)
        default: break
        }
    }

    private func presetStim(role: String, strength: Float, duration: Int) {
        coordinator.labResetBrain()
        coordinator.labStimulatePopulation(role, strength: strength, durationMs: duration)
        recorder.mark(kind: "direct_neural", detail: "preset role=\(role) strength=\(strength) duration_ms=\(duration)")
    }

    @objc private func presetFrontalLoom() { runPreset("frontal_loom") }
    @objc private func presetLeftLoom() { runPreset("left_loom") }
    @objc private func presetRightLoom() { runPreset("right_loom") }
    @objc private func presetCoveredLoom() { runPreset("left_eye_covered_loom") }
    @objc private func presetWind() { runPreset("wind_puff") }
    @objc private func presetTouch() { runPreset("thorax_touch") }
    @objc private func presetGF() { runPreset("gf") }
    @objc private func presetDNa() { runPreset("dna_left") }
    @objc private func presetDNaRight() { runPreset("dna_right") }
    @objc private func presetMDN() { runPreset("mdn") }
    @objc private func presetDNp09() { runPreset("dnp09") }
    @objc private func replayLastPreset() {
        guard let lastPreset else {
            recorderLabel.stringValue = "no preset has been run yet"
            return
        }
        runPreset(lastPreset)
    }

    @objc private func clearGraphs() {
        neuralGraph.clear(); commandGraph.clear(); sensoryGraph.clear(); flywireSensoryGraph.clear(); bodyGraph.clear(); visionGraph.clear()
        recorder.mark(kind: "ui", detail: "graphs cleared")
    }

    @objc private func startRecording() {
        if recorder.isStopping {
            recorderLabel.stringValue = "stopping… previous recording is still being flushed"
            return
        }
        if let p = recorder.start() { recorderLabel.stringValue = "recording: \(p)" }
        else { recorderLabel.stringValue = "recording failed — \(recorder.lastErrorMessage ?? "see stderr")" }
    }
    @objc private func stopRecording() {
        let p = recorder.path ?? ""
        guard recorder.isRecording || recorder.isStopping else {
            recorderLabel.stringValue = p.isEmpty ? "not recording" : recorder.state.rawValue + ": " + p
            return
        }
        recorderLabel.stringValue = p.isEmpty ? "stopping…" : "stopping: \(p)"
        recorder.stop { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case .saved(let path):
                    self.recorderLabel.stringValue = "saved: \(path)"
                case .failed(let path, let message):
                    let whereText = path.map { " — \($0)" } ?? ""
                    self.recorderLabel.stringValue = "save failed: \(message)\(whereText)"
                case .notRecording:
                    self.recorderLabel.stringValue = "not recording"
                }
            }
        }
    }

    /// App termination waits for the same recorder drain/close completion as the
    /// manual Stop button. The caller decides when to reply to AppKit's quit request.
    func prepareForApplicationTermination(completion: @escaping (ExperimentRecorderStopOutcome) -> Void) {
        guard recorder.isRecording || recorder.isStopping else {
            // Keep AppDelegate's terminateLater/reply ordering asynchronous even
            // if a manual Stop finishes in the narrow gap before this call.
            let outcome = ExperimentRecorderStopOutcome.notRecording(path: recorder.path)
            DispatchQueue.main.async { completion(outcome) }
            return
        }
        let p = recorder.path ?? ""
        recorderLabel.stringValue = p.isEmpty ? "stopping for quit…" : "stopping for quit: \(p)"
        recorder.stop(reason: "application quit") { [weak self] outcome in
            DispatchQueue.main.async {
                if let self {
                    switch outcome {
                    case .saved(let path): self.recorderLabel.stringValue = "saved: \(path)"
                    case .failed(let path, let message):
                        self.recorderLabel.stringValue = "save failed: \(message)\(path.map { " — \($0)" } ?? "")"
                    case .notRecording: self.recorderLabel.stringValue = "not recording"
                    }
                }
                completion(outcome)
            }
        }
    }
    @objc private func markBaseline() { recorder.mark(kind: "marker", detail: "baseline") }
    @objc private func markStimulusOn() { recorder.mark(kind: "marker", detail: "stimulus_on") }
    @objc private func markStimulusOff() { recorder.mark(kind: "marker", detail: "stimulus_off") }
    @objc private func markObservation() { recorder.mark(kind: "marker", detail: "observation") }

    private func ageString(_ age: TimeInterval) -> String {
        let a = max(0, age)
        return a < 1 ? String(format: "%.0f ms", a * 1000) : String(format: "%.1f s", a)
    }

    private func refresh() {
        let now = Date()
        let t = coordinator.labTelemetry()
        var state: LabRemoteState?
        var ack: LabAck?
        var event: LabEventNotice?

        if let bridge {
            state = bridge.latestLabState()
            ack = bridge.latestLabAck()
            event = bridge.latestLabEvent()

            if eyeCommandPendingID != nil {
                let stateFresh = bridge.labStateFreshness().isFresh
                let observed: Bool?
                if eyeCommandSide == "left" { observed = state?.leftEyeCovered }
                else if eyeCommandSide == "right" { observed = state?.rightEyeCovered }
                else { observed = nil }
                if stateFresh, let expected = eyeCommandCovered, observed == expected {
                    clearEyePending()
                } else if bridge.connected,
                          let started = eyeCommandStartedAt,
                          now.timeIntervalSince(started) > 5 {
                    // Avoid permanently trapping the controls if an old command
                    // was dropped from the bounded queue. A later eye command is
                    // still serialized one-at-a-time by this UI.
                    clearEyePending()
                }
            }
        }

        if window?.isVisible == true {
            neuralGraph.append([t.ratePop, t.rateLoom, t.rateFwd, t.rateMDN, t.rateGroom])
            commandGraph.append([t.rateDNaL, t.rateDNaR, t.rateMDN, t.rateFwd, t.rateGroom, t.rateEscW])
            sensoryGraph.append([t.loomL, t.loomR, t.airPuff, t.gaitDrive])
            flywireSensoryGraph.append([t.odorDriveL, t.odorDriveR, t.thermoWarmDrive,
                                        t.thermoCoolDrive, t.windCDrive, t.windEDrive])
            let distanceScaled = t.bodyNearestFoodDistanceMm >= 0 ? min(1.2, t.bodyNearestFoodDistanceMm / 100.0) : 0
            bodyGraph.append([t.bodyVX * 20, t.bodyYawRate / 5, t.bodyContactMean,
                              max(t.bodyLoomL, t.bodyLoomR), t.bodyOdorL, t.bodyOdorR,
                              distanceScaled])
            let nearest = t.bodyNearestFoodDistanceMm >= 0
                ? String(format: "%.1f mm", t.bodyNearestFoodDistanceMm)
                : "none"
            bodyTelemetryLabel.stringValue = String(format: "Movement — speed %.4f m/s · turn %.2f rad/s · contact %.2f",
                                                     t.bodyVX, t.bodyYawRate, t.bodyContactMean)
            foodTelemetryLabel.stringValue = String(format: "Food odor — left %.3f · right %.3f · nearest source: %@ · ORN %.1f/%.1f Hz",
                                                     t.bodyOdorL, t.bodyOdorR, nearest,
                                                     t.rateFoodOdorL, t.rateFoodOdorR)
            visionGraph.append([t.bodyBrightnessL, t.bodyBrightnessR, t.bodyOccupancyL,
                                t.bodyOccupancyR, t.bodyOpticExpansionL, t.bodyOpticExpansionR])
            visionTelemetryLabel.stringValue = String(format: "Vision — expansion L/R %.3f/%.3f · brightness L/R %.3f/%.3f",
                                                       t.bodyOpticExpansionL, t.bodyOpticExpansionR,
                                                       t.bodyBrightnessL, t.bodyBrightnessR)
        }

        let nearest = t.bodyNearestFoodDistanceMm >= 0
            ? String(format: "%.1f mm", t.bodyNearestFoodDistanceMm)
            : "none"
        // The body packet is the same fresh backend snapshot that drives the
        // neural model, so source diagnostics cannot disagree with actual
        // LabWorld timer expiry merely because lab_state arrived at another rate.
        let windSource = t.bodyPacketAgeS >= 0
            ? String(format: "%.2f%@", t.bodyWindStrength,
                     (t.bodyWindStrength > 0 && t.bodyWindSensory) ? " sensory" : "")
            : "unavailable"
        let touchSource = t.bodyPacketAgeS >= 0
            ? String(format: "%.2f%@", t.bodyTouchStrength,
                     (t.bodyTouchStrength > 0 && t.bodyTouchSensory) ? " sensory" : "")
            : "unavailable"
        let sourceLine = String(format:
            "1  Source → sensor     food %@ → odor %.3f/%.3f  |  vision expansion %.3f/%.3f → loom %.3f/%.3f  |  wind %@  |  touch %@  |  temp %.1f°C",
            nearest, t.bodyOdorL, t.bodyOdorR,
            t.bodyOpticExpansionL, t.bodyOpticExpansionR, t.loomL, t.loomR,
            windSource, touchSource, t.temperatureC)
        let currentLine = String(format:
            "2  Sensor → current    ORN food %.3f/%.3f  |  TRN warm/cool %.3f/%.3f  |  JO-C/E wind %.3f/%.3f  (simulation current units)",
            t.odorDriveL, t.odorDriveR, t.thermoWarmDrive, t.thermoCoolDrive,
            t.windCDrive, t.windEDrive)
        let neuralLine = String(format:
            "3  Receptor → brain    ORN L/R %.1f/%.1f Hz  |  TRN warm/cool %.1f/%.1f  |  JO-C/E %.1f/%.1f  |  loom %.1f  |  DNa L/R %.1f/%.1f  |  DNp09 %.1f",
            t.rateFoodOdorL, t.rateFoodOdorR, t.rateThermoWarm, t.rateThermoCool,
            t.rateWindC, t.rateWindE, t.rateLoom, t.rateDNaL, t.rateDNaR, t.rateFwd)
        let commandLine: String
        if t.brainSignalsAvailable {
            commandLine = String(format:
                "4  BrainSignals → FlyGym controller    walk %.2f  |  turn %.2f  |  escape %@  |  back %@  |  groom %.2f  |  wing %.2f  |  arousal %.2f  |  nervous %.2f  |  tempo %.2f  |  sleep %@  |  controller L/R %.3f/%.3f",
                t.brainWalkDrive, t.brainTurnBias, t.brainEscape ? "ON" : "OFF",
                t.brainBackward ? "ON" : "OFF", t.brainGroomDrive, t.brainWingDrive,
                t.brainArousal, t.brainNervous, t.brainTempo, t.brainSleep ? "ON" : "OFF",
                t.bodyControllerLeft, t.bodyControllerRight)
        } else {
            commandLine = String(format:
                "4  BrainSignals → FlyGym controller    no decoded BrainSignals this frame  |  controller L/R %.3f/%.3f",
                t.bodyControllerLeft, t.bodyControllerRight)
        }
        let bodyPacketDetail = t.bodyPacketAgeS >= 0
            ? String(format: "body packet %.0f ms old · MuJoCo t %.3f s · sim/wall %.2fx",
                     t.bodyPacketAgeS * 1000, t.bodySimTime, t.bodySimWallRatio)
            : "no fresh body packet used"
        let motionLine = String(format:
            "5  Measured motion     forward %.4f m/s  |  yaw %.2f rad/s  |  contact %.2f  |  %@",
            t.bodyVX, t.bodyYawRate, t.bodyContactMean, bodyPacketDetail)
        signalPathLabel.stringValue = [sourceLine, currentLine, neuralLine, commandLine, motionLine]
            .joined(separator: "\n")

        recorder.append(t)

        if let bridge {
            if bridge.connected {
                let hz = bridge.bodyHz
                let dropped = bridge.labDropped
                let degraded = hz > 0 && hz < 30 ? " · DEGRADED: body feedback below 30 Hz" : ""
                let ratio = t.bodyPacketAgeS >= 0 ? String(format: " · sim/wall %.2fx", t.bodySimWallRatio) : ""
                protocolLabel.stringValue = String(format: "FlyGym bridge — Connected · body feedback %.0f Hz%@%@%@",
                                                    hz, ratio, degraded,
                                                    dropped > 0 ? " · \(dropped) UI command\(dropped == 1 ? "" : "s") dropped" : "")
            } else {
                protocolLabel.stringValue = "FlyGym bridge — Reconnecting… brain simulation continues locally"
            }

            let bodyFreshness = bridge.bodyFreshness()
            let stateFreshness = bridge.labStateFreshness()
            let bodyAge = bodyFreshness.ageSeconds.map(ageString) ?? "no packet"
            let stateAge = stateFreshness.ageSeconds.map(ageString) ?? "no packet"
            let bodyStatus = "body \(bodyFreshness.isFresh ? "FRESH" : "STALE") \(bodyAge)"
            let envStatus = "environment \(stateFreshness.isFresh ? "FRESH" : "STALE") \(stateAge)"
            freshnessLabel.stringValue = "Packets — \(bodyStatus) · \(envStatus)"

            if let s = state {
                var bits = [String(format: "%.1f s", s.t)]
                if let n = s.objectCount { bits.append("\(n) object\(n == 1 ? "" : "s")") }
                if let w = s.wind { bits.append(String(format: "wind %.2f", w)) }
                if let c = s.temperature { bits.append(String(format: "%.1f°C", c)) }
                if let l = s.leftEyeCovered { bits.append("left eye \(l ? "covered" : "open")") }
                if let r = s.rightEyeCovered { bits.append("right eye \(r ? "covered" : "open")") }
                if let e = s.error, !e.isEmpty { bits.append("error: \(e)") }
                if let event, !event.event.isEmpty { bits.append("last event: \(event.event)") }
                remoteStateLabel.stringValue = "Environment — " + bits.joined(separator: " · ")
            } else {
                remoteStateLabel.stringValue = "Environment — waiting for FlyGym state…"
            }

            let sleeping = t.brainSleep
            let gate = sleeping ? 0.55 : 1.0
            var commandBits = ["Brain state — sleep \(sleeping ? "ON" : "OFF") · sensoryGate ×\(String(format: "%.2f", gate))"]
            if let lastCommandID {
                commandBits.append("sent #\(lastCommandID) \(lastCommandAction)")
            } else {
                commandBits.append("sent: none")
            }
            if let ack {
                let age = ageString(ack.ageSeconds(at: now))
                let ackFreshness = bridge.labAckFreshness()
                let message = ack.message.isEmpty ? "" : " · \(ack.message)"
                commandBits.append("ack #\(ack.id) \(ack.ok ? "OK" : "ERROR") · \(ackFreshness.isFresh ? "FRESH" : "STALE") · \(ack.action)\(message) · seen \(age) ago")
            } else {
                commandBits.append("ack: none yet")
            }
            if let action = state?.lastAction, !action.isEmpty { commandBits.append("bridge last action: \(action)") }
            if let error = state?.error, !error.isEmpty { commandBits.append("ERROR: \(error)") }
            commandBits.append("queue \(bridge.pendingLabDepth())")
            commandDiagnosticsLabel.stringValue = commandBits.joined(separator: "\n")
        } else {
            protocolLabel.stringValue = "FlyGym bridge — disabled"
            freshnessLabel.stringValue = "Packets — body STALE · bridge disabled · environment STALE · bridge disabled"
            remoteStateLabel.stringValue = "Environment — local brain/sensory controls are still available"
            let sleeping = t.brainSleep
            commandDiagnosticsLabel.stringValue = "Brain state — sleep \(sleeping ? "ON" : "OFF") · sensoryGate ×\(sleeping ? "0.55" : "1.00")\nCommands — FlyGym bridge disabled"
        }
    }
}
