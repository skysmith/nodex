import AppKit
import CoreMotion
import Foundation

func expandPath(_ path: String) -> String {
    if path == "~" {
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    if path.hasPrefix("~/") {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    }

    return path
}

enum NodexError: Error, CustomStringConvertible {
    case missingQuestion
    case unknownCommand(String)
    case unknownOption(String)
    case invalidValue(String)
    case configExists(String)

    var description: String {
        switch self {
        case .missingQuestion:
            return "Missing question. Try: nodex ask \"Should I run the tests?\""
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .invalidValue(let message):
            return message
        case .configExists(let path):
            return "Config already exists at \(path). Use --force to overwrite it."
        }
    }
}

enum Answer: String, Equatable {
    case yes
    case no
    case timeout

    var exitCode: Int32 {
        switch self {
        case .yes:
            return 0
        case .no:
            return 1
        case .timeout:
            return 2
        }
    }
}

struct MotionTuning: Codable {
    var window: TimeInterval = 1.45
    var warmup: TimeInterval = 0.65
    var nodThreshold: Double = 0.26
    var shakeThreshold: Double = 0.34
    var nodDominance: Double = 1.05
    var shakeDominance: Double = 1.15
    var centerMargin: Double = 0.07
    var minimumSamples: Int = 12
}

struct NodexSettings: Codable {
    var defaultTimeout: TimeInterval = 25
    var sayQuestions = true
    var defaultLogPath = "~/.nodex/events.jsonl"
    var motion = MotionTuning()

    static var defaultPath: String {
        "~/.nodex/config.json"
    }

    static func load() -> (settings: NodexSettings, path: String, loaded: Bool, warning: String?) {
        let path = expandPath(defaultPath)
        guard FileManager.default.fileExists(atPath: path) else {
            return (NodexSettings(), path, false, nil)
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let settings = try JSONDecoder().decode(NodexSettings.self, from: data)
            return (settings, path, true, nil)
        } catch {
            return (NodexSettings(), path, false, "Could not load \(path): \(error.localizedDescription). Using defaults.")
        }
    }
}

struct AskConfig {
    var question: String
    var timeout: TimeInterval = 25
    var speak = true
    var motion = true
    var media = true
    var keyboard = true
    var json = false
    var debug = false
    var log = false
    var logPath = expandPath("~/.nodex/events.jsonl")
    var timeoutDefault: Answer?
    var tuning = MotionTuning()
}

struct CalibrateConfig {
    var timeout: TimeInterval = 8
    var speak = true
    var debug = true
    var tuning = MotionTuning()
}

final class Completion {
    private let lock = NSLock()
    private var storedAnswer: Answer?
    private(set) var source: String = ""
    private(set) var detail: String = ""

    var answer: Answer? {
        lock.lock()
        defer { lock.unlock() }
        return storedAnswer
    }

    func finish(_ answer: Answer, source: String, detail: String = "") {
        lock.lock()
        defer { lock.unlock() }
        guard storedAnswer == nil else { return }
        storedAnswer = answer
        self.source = source
        self.detail = detail
    }
}

struct MotionSample {
    let time: TimeInterval
    let pitch: Double
    let yaw: Double
    let roll: Double
}

final class HeadMotionDetector {
    private let manager = CMHeadphoneMotionManager()
    private var samples: [MotionSample] = []
    private var baseline: MotionSample?
    private var startedAt: TimeInterval = 0
    private let tuning: MotionTuning
    private let completion: Completion
    private let debug: Bool

    init(completion: Completion, debug: Bool, tuning: MotionTuning = MotionTuning()) {
        self.completion = completion
        self.debug = debug
        self.tuning = tuning
    }

    var availabilitySummary: String {
        if manager.isDeviceMotionAvailable {
            return "available"
        }
        return "not available"
    }

    func start() -> Bool {
        guard manager.isDeviceMotionAvailable else {
            return false
        }

        startedAt = ProcessInfo.processInfo.systemUptime
        samples.removeAll()
        baseline = nil

        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.completion.finish(.timeout, source: "motion-error", detail: error.localizedDescription)
                return
            }
            guard let motion else { return }
            self.ingest(motion)
        }

        return true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func ingest(_ motion: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let sample = MotionSample(
            time: now,
            pitch: motion.attitude.pitch,
            yaw: motion.attitude.yaw,
            roll: motion.attitude.roll
        )

        if baseline == nil {
            baseline = sample
        }

        guard let baseline else { return }

        let relative = MotionSample(
            time: now,
            pitch: normalizeAngle(sample.pitch - baseline.pitch),
            yaw: normalizeAngle(sample.yaw - baseline.yaw),
            roll: normalizeAngle(sample.roll - baseline.roll)
        )

        samples.append(relative)
        samples.removeAll { now - $0.time > tuning.window }

        guard now - startedAt > tuning.warmup else { return }
        guard samples.count >= tuning.minimumSamples else { return }

        let pitch = axisStats(samples.map(\.pitch))
        let yaw = axisStats(samples.map(\.yaw))
        let roll = axisStats(samples.map(\.roll))
        let vertical = pitch.amplitude >= roll.amplitude ? pitch : roll
        let verticalAxis = pitch.amplitude >= roll.amplitude ? "pitch" : "roll"

        if debug, samples.count % 8 == 0 {
            fputs(
                String(
                    format: "motion pitch=%.2f yaw=%.2f roll=%.2f axis=%@\n",
                    pitch.amplitude,
                    yaw.amplitude,
                    roll.amplitude,
                    verticalAxis
                ),
                stderr
            )
        }

        if yaw.amplitude > tuning.shakeThreshold && yaw.amplitude > vertical.amplitude * tuning.shakeDominance && yaw.crossesCenter {
            completion.finish(.no, source: "head-shake", detail: "yaw amplitude \(formatRadians(yaw.amplitude)), confidence \(confidence(yaw.amplitude, threshold: tuning.shakeThreshold))")
            stop()
            return
        }

        if vertical.amplitude > tuning.nodThreshold && vertical.amplitude > yaw.amplitude * tuning.nodDominance && vertical.crossesCenter {
            completion.finish(.yes, source: "head-nod", detail: "\(verticalAxis) amplitude \(formatRadians(vertical.amplitude)), confidence \(confidence(vertical.amplitude, threshold: tuning.nodThreshold))")
            stop()
        }
    }

    private func axisStats(_ values: [Double]) -> (amplitude: Double, crossesCenter: Bool) {
        guard let minimum = values.min(), let maximum = values.max() else {
            return (0, false)
        }
        let amplitude = maximum - minimum
        let margin = Swift.max(tuning.nodThreshold * 0.28, tuning.centerMargin)
        return (amplitude, minimum < -margin && maximum > margin)
    }

    private func normalizeAngle(_ value: Double) -> Double {
        var result = value
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }

    private func formatRadians(_ value: Double) -> String {
        String(format: "%.2f rad", value)
    }

    private func confidence(_ amplitude: Double, threshold: Double) -> String {
        String(format: "%.2fx", amplitude / Swift.max(threshold, 0.001))
    }
}

final class MediaKeyDetector {
    private var monitor: Any?
    private let completion: Completion
    private let debug: Bool

    init(completion: Completion, debug: Bool) {
        self.completion = completion
        self.debug = debug
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let data = event.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyState = (data & 0x0000FF00) >> 8
        let isKeyDown = keyState == 0x0A

        guard isKeyDown else { return }

        if debug {
            fputs("media key code=\(keyCode)\n", stderr)
        }

        switch keyCode {
        case 16:
            completion.finish(.yes, source: "media-play-pause", detail: "single squeeze/media play-pause")
        case 17, 18:
            completion.finish(.no, source: "media-skip", detail: "double/triple squeeze/media skip")
        default:
            break
        }
    }
}

@main
struct Nodex {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let loaded = NodexSettings.load()
            if let warning = loaded.warning {
                fputs("nodex: \(warning)\n", stderr)
            }

            guard let command = args.first else {
                printHelp()
                Foundation.exit(0)
            }

            switch command {
            case "ask":
                let config = try parseAsk(Array(args.dropFirst()), settings: loaded.settings)
                let (answer, source, detail) = runAsk(config)
                output(answer: answer, source: source, detail: detail, json: config.json)
                Foundation.exit(answer.exitCode)
            case "calibrate":
                let config = try parseCalibrate(Array(args.dropFirst()), settings: loaded.settings)
                let succeeded = runCalibrate(config)
                Foundation.exit(succeeded ? 0 : 1)
            case "config":
                try runConfig(Array(args.dropFirst()), settings: loaded.settings, path: loaded.path, loaded: loaded.loaded)
                Foundation.exit(0)
            case "doctor":
                runDoctor(settings: loaded.settings, path: loaded.path, loaded: loaded.loaded)
                Foundation.exit(0)
            case "help", "--help", "-h":
                printHelp()
                Foundation.exit(0)
            default:
                throw NodexError.unknownCommand(command)
            }
        } catch {
            fputs("nodex: \(error)\n\n", stderr)
            printHelp(to: stderr)
            Foundation.exit(64)
        }
    }

    private static func parseAsk(_ args: [String], settings: NodexSettings) throws -> AskConfig {
        var questionParts: [String] = []
        var config = AskConfig(
            question: "",
            timeout: settings.defaultTimeout,
            speak: settings.sayQuestions,
            logPath: expandPath(settings.defaultLogPath),
            tuning: settings.motion
        )
        var index = 0

        while index < args.count {
            let arg = args[index]

            switch arg {
            case "--timeout":
                index += 1
                guard index < args.count, let timeout = TimeInterval(args[index]) else {
                    throw NodexError.unknownOption("--timeout requires seconds")
                }
                config.timeout = timeout
            case "--default":
                index += 1
                guard index < args.count else {
                    throw NodexError.unknownOption("--default requires yes, no, or timeout")
                }
                config.timeoutDefault = try parseAnswer(args[index], allowTimeout: true)
            case "--no-say":
                config.speak = false
            case "--say":
                config.speak = true
            case "--keyboard-only":
                config.motion = false
                config.media = false
                config.keyboard = true
            case "--motion-only":
                config.motion = true
                config.media = false
                config.keyboard = false
            case "--no-motion":
                config.motion = false
            case "--no-media":
                config.media = false
            case "--no-keyboard":
                config.keyboard = false
            case "--json":
                config.json = true
            case "--debug":
                config.debug = true
            case "--log":
                config.log = true
            case "--no-log":
                config.log = false
            case "--log-path":
                index += 1
                guard index < args.count else {
                    throw NodexError.unknownOption("--log-path requires a path")
                }
                config.logPath = expandPath(args[index])
                config.log = true
            case "--nod-threshold":
                index += 1
                guard index < args.count, let value = Double(args[index]) else {
                    throw NodexError.unknownOption("--nod-threshold requires a number")
                }
                config.tuning.nodThreshold = value
            case "--shake-threshold":
                index += 1
                guard index < args.count, let value = Double(args[index]) else {
                    throw NodexError.unknownOption("--shake-threshold requires a number")
                }
                config.tuning.shakeThreshold = value
            case "--help", "-h":
                printAskHelp()
                Foundation.exit(0)
            default:
                if arg.hasPrefix("-") {
                    throw NodexError.unknownOption(arg)
                }
                questionParts.append(arg)
            }

            index += 1
        }

        let question = questionParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw NodexError.missingQuestion
        }

        config.question = question
        return config
    }

    private static func parseCalibrate(_ args: [String], settings: NodexSettings) throws -> CalibrateConfig {
        var config = CalibrateConfig(
            timeout: 8,
            speak: settings.sayQuestions,
            debug: true,
            tuning: settings.motion
        )
        var index = 0

        while index < args.count {
            let arg = args[index]

            switch arg {
            case "--timeout":
                index += 1
                guard index < args.count, let timeout = TimeInterval(args[index]) else {
                    throw NodexError.unknownOption("--timeout requires seconds")
                }
                config.timeout = timeout
            case "--no-say":
                config.speak = false
            case "--say":
                config.speak = true
            case "--quiet":
                config.debug = false
            case "--debug":
                config.debug = true
            case "--nod-threshold":
                index += 1
                guard index < args.count, let value = Double(args[index]) else {
                    throw NodexError.unknownOption("--nod-threshold requires a number")
                }
                config.tuning.nodThreshold = value
            case "--shake-threshold":
                index += 1
                guard index < args.count, let value = Double(args[index]) else {
                    throw NodexError.unknownOption("--shake-threshold requires a number")
                }
                config.tuning.shakeThreshold = value
            case "--help", "-h":
                printCalibrateHelp()
                Foundation.exit(0)
            default:
                throw NodexError.unknownOption(arg)
            }

            index += 1
        }

        return config
    }

    private static func parseAnswer(_ value: String, allowTimeout: Bool) throws -> Answer {
        switch value.lowercased() {
        case "y", "yes":
            return .yes
        case "n", "no":
            return .no
        case "timeout":
            if allowTimeout {
                return .timeout
            }
            fallthrough
        default:
            throw NodexError.invalidValue("Expected yes, no\(allowTimeout ? ", or timeout" : "").")
        }
    }

    private static func runAsk(_ config: AskConfig) -> (Answer, String, String) {
        let startedAt = Date()
        let completion = Completion()
        var motionDetector: HeadMotionDetector?
        var mediaDetector: MediaKeyDetector?

        line("", json: config.json)
        line("Nodex asks: \(config.question)", json: config.json)
        line("yes: nod, single squeeze/media play-pause, or type y", json: config.json)
        line(" no: shake, double squeeze/media skip, or type n", json: config.json)
        line("", json: config.json)

        if config.speak {
            speak(config.question)
        }

        if config.motion {
            let detector = HeadMotionDetector(completion: completion, debug: config.debug, tuning: config.tuning)
            motionDetector = detector
            if detector.start() {
                fputs("listening: AirPods head motion\n", stderr)
            } else {
                fputs("nodex: headphone motion is not available right now\n", stderr)
            }
        }

        if config.media {
            let detector = MediaKeyDetector(completion: completion, debug: config.debug)
            mediaDetector = detector
            detector.start()
            fputs("listening: media/squeeze keys\n", stderr)
        }

        if config.keyboard {
            fputs("listening: keyboard y/n\n", stderr)
            DispatchQueue.global(qos: .userInitiated).async {
                while completion.answer == nil {
                    guard let line = readLine() else { return }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if ["y", "yes"].contains(trimmed) {
                        completion.finish(.yes, source: "keyboard")
                        return
                    }
                    if ["n", "no"].contains(trimmed) {
                        completion.finish(.no, source: "keyboard")
                        return
                    }
                    fputs("Type y/yes or n/no.\n", stderr)
                }
            }
        }

        let deadline = Date().addingTimeInterval(config.timeout)
        while completion.answer == nil && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        motionDetector?.stop()
        mediaDetector?.stop()

        if let answer = completion.answer {
            appendLogIfNeeded(config: config, answer: answer, source: completion.source, detail: completion.detail, startedAt: startedAt)
            return (answer, completion.source, completion.detail)
        }

        let detail = "\(Int(config.timeout)) seconds elapsed"
        if let timeoutDefault = config.timeoutDefault, timeoutDefault != .timeout {
            appendLogIfNeeded(config: config, answer: timeoutDefault, source: "timeout-default", detail: detail, startedAt: startedAt)
            return (timeoutDefault, "timeout-default", detail)
        }

        appendLogIfNeeded(config: config, answer: .timeout, source: "timeout", detail: detail, startedAt: startedAt)
        return (.timeout, "timeout", detail)
    }

    private static func runCalibrate(_ config: CalibrateConfig) -> Bool {
        print("Nodex calibration")
        print("Step 1: nod when prompted. Step 2: shake when prompted.")
        print("This does not rewrite thresholds yet; it verifies whether the current tuning can see both gestures.")
        print("")

        var nodAsk = AskConfig(
            question: "Nod yes now.",
            timeout: config.timeout,
            speak: config.speak,
            motion: true,
            media: false,
            keyboard: false,
            debug: config.debug,
            tuning: config.tuning
        )
        nodAsk.log = false
        let (nodAnswer, nodSource, nodDetail) = runAsk(nodAsk)
        let nodOK = nodAnswer == .yes

        print("")
        print("Nod result: \(nodAnswer.rawValue) via \(nodSource)\(nodDetail.isEmpty ? "" : " (\(nodDetail))")")
        print("")

        var shakeAsk = AskConfig(
            question: "Shake no now.",
            timeout: config.timeout,
            speak: config.speak,
            motion: true,
            media: false,
            keyboard: false,
            debug: config.debug,
            tuning: config.tuning
        )
        shakeAsk.log = false
        let (shakeAnswer, shakeSource, shakeDetail) = runAsk(shakeAsk)
        let shakeOK = shakeAnswer == .no

        print("")
        print("Shake result: \(shakeAnswer.rawValue) via \(shakeSource)\(shakeDetail.isEmpty ? "" : " (\(shakeDetail))")")
        print("")

        if nodOK && shakeOK {
            print("Calibration pass: current thresholds can detect nod and shake.")
            return true
        }

        print("Calibration needs tuning.")
        print("Try lower thresholds if gestures time out:")
        print("  nodex calibrate --nod-threshold 0.20 --shake-threshold 0.28")
        print("Try higher thresholds if ordinary movement is misread:")
        print("  nodex calibrate --nod-threshold 0.32 --shake-threshold 0.42")
        return false
    }

    private static func runConfig(_ args: [String], settings: NodexSettings, path: String, loaded: Bool) throws {
        if args.first == "init" {
            let force = args.dropFirst().contains("--force")
            if FileManager.default.fileExists(atPath: path) && !force {
                throw NodexError.configExists(path)
            }
            try writeDefaultConfig(path: path)
            print("Wrote Nodex config: \(path)")
            return
        }

        if args.contains("--help") || args.contains("-h") {
            printConfigHelp()
            return
        }

        if !args.isEmpty {
            throw NodexError.unknownOption(args.joined(separator: " "))
        }

        print("Nodex config")
        print("path: \(path)")
        print("loaded: \(loaded ? "yes" : "no; using built-in defaults")")
        print("")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    private static func writeDefaultConfig(path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(NodexSettings())
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    private static func appendLogIfNeeded(config: AskConfig, answer: Answer, source: String, detail: String, startedAt: Date) {
        guard config.log else { return }

        let endedAt = Date()
        let event: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: endedAt),
            "question": config.question,
            "answer": answer.rawValue,
            "source": source,
            "detail": detail,
            "duration_ms": Int(endedAt.timeIntervalSince(startedAt) * 1000),
            "timeout_seconds": config.timeout,
            "motion_enabled": config.motion,
            "media_enabled": config.media,
            "keyboard_enabled": config.keyboard
        ]

        guard JSONSerialization.isValidJSONObject(event),
              let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
            fputs("nodex: could not encode log event\n", stderr)
            return
        }

        do {
            let url = URL(fileURLWithPath: config.logPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var line = data
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: config.logPath) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: url, options: [.atomic])
            }
        } catch {
            fputs("nodex: could not write log \(config.logPath): \(error.localizedDescription)\n", stderr)
        }
    }

    private static func line(_ value: String, json: Bool) {
        if json {
            fputs("\(value)\n", stderr)
        } else {
            print(value)
        }
    }

    private static func speak(_ question: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [question]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("nodex: could not run /usr/bin/say: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func output(answer: Answer, source: String, detail: String, json: Bool) {
        if json {
            let payload = [
                "answer": answer.rawValue,
                "source": source,
                "detail": detail
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let encoded = String(data: data, encoding: .utf8) {
                print(encoded)
            } else {
                print("{\"answer\":\"\(answer.rawValue)\"}")
            }
            return
        }

        switch answer {
        case .yes:
            print("YES (\(source))")
        case .no:
            print("NO (\(source))")
        case .timeout:
            print("TIMEOUT (\(detail))")
        }
    }

    private static func runDoctor(settings: NodexSettings, path: String, loaded: Bool) {
        let detector = HeadMotionDetector(completion: Completion(), debug: false, tuning: settings.motion)
        let status = CMHeadphoneMotionManager.authorizationStatus()

        print("Nodex doctor")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("config: \(loaded ? "loaded" : "defaults") at \(path)")
        print("headphone motion: \(detector.availabilitySummary)")
        print("motion authorization: \(describe(status))")
        print("default timeout: \(Int(settings.defaultTimeout))s")
        print("motion tuning: nod \(settings.motion.nodThreshold), shake \(settings.motion.shakeThreshold), window \(settings.motion.window)s")
        print("default log path: \(expandPath(settings.defaultLogPath))")
        print("")
        let command = displayCommand()
        print("Try:")
        print("  \(command) ask \"Should Codex continue?\" --debug")
        print("  \(command) calibrate")
        print("  \(command) ask \"Keyboard smoke test?\" --keyboard-only --no-say")
        print("")
        print("Notes:")
        print("- AirPods must be connected to this Mac.")
        print("- macOS may ask for Motion & Fitness permission on first use.")
        print("- Squeeze fallback depends on macOS exposing AirPods presses as media keys.")
        if loaded {
            print("- Edit \(path) to tune default thresholds.")
        } else {
            print("- Use `nodex config init` to create \(path).")
        }
    }

    private static func describe(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "not determined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        @unknown default:
            return "unknown"
        }
    }

    private static func displayCommand() -> String {
        if let displayCommand = ProcessInfo.processInfo.environment["NODEX_DISPLAY_COMMAND"],
           !displayCommand.isEmpty {
            return displayCommand
        }

        let invoked = CommandLine.arguments.first ?? "nodex"
        let url = URL(fileURLWithPath: invoked)
        let name = url.lastPathComponent

        if invoked.contains("/") {
            return invoked
        }

        if name.isEmpty {
            return "nodex"
        }

        return name
    }

    private static func printHelp(to output: UnsafeMutablePointer<FILE> = stdout) {
        fputs(
            """
            Nodex: answer Codex yes/no prompts with AirPods head gestures.

            Usage:
              nodex ask "Should I run the tests?"
              nodex calibrate
              nodex config
              nodex config init
              nodex doctor

            Ask options:
              --timeout SECONDS   Wait time before returning timeout. Default: 25
              --default ANSWER     Return yes/no/timeout when time expires
              --no-say            Do not read the question aloud with macOS say
              --say               Read the question aloud even if config disables it
              --keyboard-only     Disable AirPods/media inputs and wait for y/n
              --motion-only       Disable media and keyboard fallback
              --no-motion         Disable AirPods head-motion input
              --no-media          Disable squeeze/media-key input
              --no-keyboard       Disable keyboard fallback
              --json              Print a machine-readable result
              --debug             Print gesture diagnostics to stderr
              --log               Append question/result JSONL to the Nodex log
              --log-path PATH      Use a custom JSONL log path
              --nod-threshold N    Override nod detection threshold
              --shake-threshold N  Override shake detection threshold

            Answer mapping:
              yes = nod, single squeeze/media play-pause, y
               no = shake, double squeeze/media skip, n

            """,
            output
        )
    }

    private static func printAskHelp() {
        printHelp()
    }

    private static func printCalibrateHelp() {
        fputs(
            """
            Usage:
              nodex calibrate

            Options:
              --timeout SECONDS
              --no-say
              --quiet
              --nod-threshold N
              --shake-threshold N

            """,
            stdout
        )
    }

    private static func printConfigHelp() {
        fputs(
            """
            Usage:
              nodex config
              nodex config init [--force]

            The default config path is ~/.nodex/config.json.

            """,
            stdout
        )
    }
}
