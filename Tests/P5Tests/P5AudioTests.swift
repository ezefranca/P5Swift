import AVFoundation
import Foundation
import Testing

@testable import P5

@Suite("P5 native audio", .serialized)
struct P5AudioTests {
    @Test("Audio values validate, serialize, and evaluate every ADSR stage")
    func values() throws {
        let envelope = P5AudioEnvelope(
            attackTime: 1,
            decayTime: 1,
            sustainLevel: 0.25,
            releaseTime: 2
        )
        #expect(envelope.amplitude(at: 0) == 0)
        #expect(envelope.amplitude(at: 0.5) == 0.5)
        #expect(envelope.amplitude(at: 1) == 1)
        #expect(abs(envelope.amplitude(at: 1.5) - 0.625) < 0.001)
        #expect(envelope.amplitude(at: 2) == 0.25)
        #expect(envelope.amplitude(at: 3, releaseAt: 2) == 0.125)
        #expect(envelope.amplitude(at: 5, releaseAt: 2) == 0)
        #expect(
            P5AudioEnvelope(
                attackTime: 0,
                decayTime: 0,
                sustainLevel: 0.5,
                releaseTime: 0
            ).amplitude(at: 0, releaseAt: 0) == 0
        )
        #expect(
            P5AudioEnvelope(
                attackTime: 0,
                decayTime: 1,
                sustainLevel: 0,
                releaseTime: 1
            ).amplitude(at: 0.5) == 0.5
        )
        #expect(try Self.roundTrip(envelope) == envelope)

        let analysis = P5AudioAnalysis(
            amplitude: 0.5,
            spectrum: [0, 1, 2, 3],
            sampleRate: 8_000,
            fftSize: 8
        )
        #expect(analysis.frequency(forBin: 2) == 2_000)
        #expect(try Self.roundTrip(analysis) == analysis)

        for waveform in P5OscillatorWaveform.allCases {
            #expect(
                try JSONDecoder().decode(
                    P5OscillatorWaveform.self,
                    from: JSONEncoder().encode(waveform)
                ) == waveform
            )
        }
        for state in [
            P5AudioEngineState.stopped,
            .running,
            .paused,
            .failed("reason"),
        ] {
            #expect(
                try JSONDecoder().decode(
                    P5AudioEngineState.self,
                    from: JSONEncoder().encode(state)
                ) == state
            )
        }
        for state in [
            P5AudioFilePlayerState.stopped,
            .playing,
            .paused,
            .ended,
        ] {
            #expect(
                try JSONDecoder().decode(
                    P5AudioFilePlayerState.self,
                    from: JSONEncoder().encode(state)
                ) == state
            )
        }
        let errors: [P5AudioError] = [
            .fileLoadingFailed("reason"),
            .engineStartFailed("reason"),
            .invalidTime,
            .invalidSamples,
            .analyzerCreationFailed("reason"),
            .formatCreationFailed,
            .analyzerAlreadyInstalled,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("Invalid serialized audio values are rejected")
    func decodingValidation() throws {
        let invalidEnvelopes = [
            #"{"attackTime":-1,"decayTime":1,"sustainLevel":0.5,"releaseTime":1}"#,
            #"{"attackTime":1,"decayTime":-1,"sustainLevel":0.5,"releaseTime":1}"#,
            #"{"attackTime":1,"decayTime":1,"sustainLevel":2,"releaseTime":1}"#,
            #"{"attackTime":1,"decayTime":1,"sustainLevel":0.5,"releaseTime":-1}"#,
        ]
        for json in invalidEnvelopes {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(P5AudioEnvelope.self, from: Data(json.utf8))
            }
        }

        let invalidAnalyses = [
            #"{"amplitude":-1,"spectrum":[0,0],"sampleRate":8,"fftSize":4}"#,
            #"{"amplitude":1,"spectrum":[0,0],"sampleRate":0,"fftSize":4}"#,
            #"{"amplitude":1,"spectrum":[0,0],"sampleRate":8,"fftSize":3}"#,
            #"{"amplitude":1,"spectrum":[0],"sampleRate":8,"fftSize":4}"#,
            #"{"amplitude":1,"spectrum":[-1,0],"sampleRate":8,"fftSize":4}"#,
        ]
        for json in invalidAnalyses {
            #expect(throws: DecodingError.self) {
                _ = try JSONDecoder().decode(P5AudioAnalysis.self, from: Data(json.utf8))
            }
        }
    }

    @Test("Audio files expose validated AVFoundation metadata and typed failures")
    func audioFiles() throws {
        let url = Self.temporaryURL(extension: "caf")
        let emptyURL = Self.temporaryURL(extension: "caf")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: emptyURL)
        }
        try Self.writeAudio(to: url, frameCount: 64)
        try Self.writeAudio(to: emptyURL, frameCount: 0)

        let file = try P5AudioFile(url: url)
        #expect(file.url == url)
        #expect(file.sampleRate == 8_000)
        #expect(file.channelCount == 1)
        #expect(abs(file.duration - 0.008) < 0.000_1)

        #expect(throws: P5AudioError.self) {
            _ = try P5AudioFile(url: URL(fileURLWithPath: "/missing-audio.caf"))
        }
        #expect(
            throws: P5AudioError.fileLoadingFailed("AVFoundation returned invalid file metadata.")
        ) {
            _ = try P5AudioFile(url: emptyURL)
        }

        var typedRuntime = P5AudioFileRuntime()
        typedRuntime.open = { _ in throw P5AudioError.invalidSamples }
        #expect(throws: P5AudioError.invalidSamples) {
            _ = try P5AudioFile(url: url, runtime: typedRuntime)
        }
        var nativeRuntime = P5AudioFileRuntime()
        nativeRuntime.open = { _ in throw StubAudioError.file }
        #expect(throws: P5AudioError.fileLoadingFailed("file")) {
            _ = try P5AudioFile(url: url, runtime: nativeRuntime)
        }
    }

    @Test("Accelerate analysis finds amplitude and a deterministic spectral peak")
    func analysis() throws {
        let analyzer = try P5AudioAnalyzer(fftSize: 64)
        #expect(analyzer.latest == nil)
        let samples = (0..<64).map { index in
            Float(sin(2 * Double.pi * 8 * Double(index) / 64))
        }
        let result = try analyzer.analyze(samples: samples, sampleRate: 64)
        #expect(abs(result.amplitude - Float(1 / sqrt(2.0))) < 0.001)
        let peak = try #require(
            result.spectrum.indices.max { lhs, rhs in
                result.spectrum[lhs] < result.spectrum[rhs]
            })
        #expect(peak == 8)

        let short = try analyzer.analyze(samples: [1, -1], sampleRate: 64)
        #expect(short.spectrum.count == 32)
        let long = try analyzer.analyze(
            samples: Array(repeating: 0, count: 64) + samples,
            sampleRate: 64
        )
        #expect(long.spectrum == result.spectrum)

        for (input, sampleRate) in [
            ([Float](), 64.0),
            ([Float.nan], 64.0),
            ([Float(0)], 0.0),
        ] {
            #expect(throws: P5AudioError.invalidSamples) {
                _ = try analyzer.analyze(samples: input, sampleRate: sampleRate)
            }
        }

        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: AVAudioFormat(
                    standardFormatWithSampleRate: 64,
                    channels: 1
                )!,
                frameCapacity: 64
            )
        )
        buffer.frameLength = 64
        for index in 0..<64 {
            buffer.floatChannelData?[0][index] = samples[index]
        }
        #expect(try analyzer.process(buffer) == result)
        #expect(analyzer.latest == result)

        let empty = try #require(
            AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: 1)
        )
        #expect(throws: P5AudioError.invalidSamples) { _ = try analyzer.process(empty) }
        let integerFormat = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 64,
                channels: 1,
                interleaved: false
            )
        )
        let integerBuffer = try #require(
            AVAudioPCMBuffer(pcmFormat: integerFormat, frameCapacity: 1)
        )
        integerBuffer.frameLength = 1
        #expect(throws: P5AudioError.invalidSamples) {
            _ = try analyzer.process(integerBuffer)
        }

        var runtime = P5AudioAnalysisRuntime()
        runtime.makeTransform = { _ in throw StubAudioError.transform }
        #expect(throws: P5AudioError.analyzerCreationFailed("transform")) {
            _ = try P5AudioAnalyzer(fftSize: 64, runtime: runtime)
        }
    }

    @Test("Oscillator DSP renders every waveform and envelope transition")
    func oscillatorDSP() throws {
        let expected: [P5OscillatorWaveform: [Float]] = [
            .sine: [0, 1, 0, -1],
            .square: [1, 1, -1, -1],
            .sawtooth: [-1, -0.5, 0, 0.5],
            .triangle: [-1, 0, 1, 0],
        ]
        for waveform in P5OscillatorWaveform.allCases {
            let state = P5OscillatorRenderState(
                waveform: waveform,
                frequency: 1,
                amplitude: 1
            )
            #expect(state.waveform == waveform)
            #expect(state.frequency == 1)
            #expect(state.amplitude == 1)
            #expect(state.isPlaying == false)
            state.play()
            let samples = try Self.render(state, frameCount: 4, sampleRate: 4)
            for (actual, expected) in zip(samples, try #require(expected[waveform])) {
                #expect(abs(actual - expected) < 0.000_1)
            }
            state.release()
            #expect(state.isPlaying == false)
        }

        let state = P5OscillatorRenderState(waveform: .sine, frequency: 1, amplitude: 1)
        state.waveform = .triangle
        state.frequency = 2
        state.amplitude = 0.5
        #expect(state.waveform == .triangle)
        #expect(state.frequency == 2)
        #expect(state.amplitude == 0.5)
        state.trigger(
            envelope: P5AudioEnvelope(
                attackTime: 0.2,
                decayTime: 0.2,
                sustainLevel: 0.5,
                releaseTime: 0.2
            )
        )
        _ = try Self.render(state, frameCount: 5, sampleRate: 10)
        state.release()
        state.release()
        _ = try Self.render(state, frameCount: 3, sampleRate: 10)
        #expect(state.isPlaying == false)
        state.stop()

        let emptyBuffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        var emptyList = AudioBufferList(mNumberBuffers: 1, mBuffers: emptyBuffer)
        withUnsafeMutablePointer(to: &emptyList) {
            state.render(
                frameCount: 1,
                sampleRate: 10,
                buffers: UnsafeMutableAudioBufferListPointer($0)
            )
        }
    }

    @Test("The audio engine orders lifecycle, construction, analysis, and cleanup")
    @MainActor
    func engineLifecycle() throws {
        let state = AudioEngineState()
        var runtime = P5AudioEngineRuntime()
        runtime.prepare = { _ in state.prepareCount += 1 }
        runtime.start = { _ in
            state.startCount += 1
            if state.startFails { throw StubAudioError.start }
        }
        runtime.pause = { _ in state.pauseCount += 1 }
        runtime.stop = { _ in state.stopCount += 1 }
        runtime.reset = { _ in state.resetCount += 1 }
        runtime.outputVolume = { _ in state.volume }
        runtime.setOutputVolume = { _, value in state.volume = value }
        runtime.outputFormat = { _ in
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        }
        runtime.attach = { _, _ in state.attachCount += 1 }
        runtime.connect = { _, _, _, format in
            state.connectFormats.append(format?.sampleRate)
        }
        runtime.installTap = { _, size, handler in
            state.tapSize = size
            state.tapHandler = handler
        }
        runtime.removeTap = { _ in state.removeTapCount += 1 }

        var engine: P5AudioEngine? = P5AudioEngine(nativeEngine: AVAudioEngine(), runtime: runtime)
        let observed = try #require(engine)
        observed.stateChanged = { state.transitions.append($0) }
        observed.outputVolume = 0.25
        #expect(observed.outputVolume == 0.25)
        try observed.start()
        observed.scenePhaseChanged(to: .active)
        #expect(state.pauseCount == 0)
        observed.scenePhaseChanged(to: .inactive)
        #expect(observed.state == .paused)
        try observed.start()
        observed.scenePhaseChanged(to: .background)
        observed.stop()
        #expect(state.prepareCount == 2)
        #expect(state.startCount == 2)
        #expect(state.pauseCount == 2)
        #expect(state.resetCount == 1)

        let oscillator = try observed.makeOscillator(
            waveform: .square,
            frequency: 220,
            amplitude: 0.5
        )
        #expect(oscillator.waveform == .square)
        #expect(oscillator.frequency == 220)
        #expect(oscillator.amplitude == 0.5)
        oscillator.waveform = .sawtooth
        oscillator.frequency = 440
        oscillator.amplitude = 0.25
        oscillator.play()
        #expect(oscillator.isPlaying)
        oscillator.trigger(envelope: P5AudioEnvelope())
        oscillator.release()
        oscillator.stop()
        #expect(oscillator.isPlaying == false)
        #expect(oscillator.nativeNode.engine == nil)
        #expect(state.attachCount == 1)
        #expect(state.connectFormats == [8_000])

        var fallbackRuntime = runtime
        fallbackRuntime.outputFormat = { _ in AVAudioFormat() }
        let fallbackEngine = P5AudioEngine(
            nativeEngine: AVAudioEngine(),
            runtime: fallbackRuntime
        )
        _ = try fallbackEngine.makeOscillator()
        #expect(state.connectFormats.last == 44_100)

        let analyzer = try P5AudioAnalyzer(fftSize: 32)
        try observed.installAnalyzer(analyzer)
        #expect(state.tapSize == 32)
        #expect(throws: P5AudioError.analyzerAlreadyInstalled) {
            try observed.installAnalyzer(analyzer)
        }
        let buffer = try Self.buffer(samples: Array(repeating: 0.5, count: 32), sampleRate: 8_000)
        state.tapHandler?(buffer)
        #expect(analyzer.latest != nil)
        observed.removeAnalyzer()
        observed.removeAnalyzer()
        #expect(state.removeTapCount == 1)

        state.startFails = true
        #expect(throws: P5AudioError.engineStartFailed("start")) { try observed.start() }
        #expect(observed.state == .failed("The native audio engine could not start: start"))

        var invalidFormatRuntime = runtime
        invalidFormatRuntime.makeFormat = { _ in nil }
        let invalidFormatEngine = P5AudioEngine(
            nativeEngine: AVAudioEngine(),
            runtime: invalidFormatRuntime
        )
        #expect(throws: P5AudioError.formatCreationFailed) {
            _ = try invalidFormatEngine.makeOscillator()
        }

        engine = nil
        #expect(state.stopCount == 1)
        _ = observed
    }

    @Test("Engine file construction preserves typed and native loading failures")
    @MainActor
    func engineFileFailures() throws {
        let url = Self.temporaryURL(extension: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeAudio(to: url, frameCount: 8)
        let file = try P5AudioFile(url: url)

        var typed = P5AudioEngineRuntime()
        typed.openFile = { _ in throw P5AudioError.invalidSamples }
        typed.stop = { _ in }
        let typedEngine = P5AudioEngine(nativeEngine: AVAudioEngine(), runtime: typed)
        #expect(throws: P5AudioError.invalidSamples) {
            _ = try typedEngine.makeFilePlayer(for: file)
        }

        var native = typed
        native.openFile = { _ in throw StubAudioError.file }
        let nativeEngine = P5AudioEngine(nativeEngine: AVAudioEngine(), runtime: native)
        #expect(throws: P5AudioError.fileLoadingFailed("file")) {
            _ = try nativeEngine.makeFilePlayer(for: file)
        }
    }

    @Test("File-player transport schedules, seeks, loops, and reports completion")
    @MainActor
    func filePlayer() async throws {
        let url = Self.temporaryURL(extension: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeAudio(to: url, frameCount: 80)
        let file = try P5AudioFile(url: url)
        let nativeFile = try AVAudioFile(forReading: url)
        let state = AudioPlayerState()
        var runtime = P5AudioPlayerRuntime()
        runtime.schedule = { _, _, start, count, completion in
            state.starts.append(start)
            state.counts.append(count)
            state.completion = completion
        }
        runtime.play = { _ in state.playCount += 1 }
        runtime.pause = { _ in state.pauseCount += 1 }
        runtime.stop = { _ in state.stopCount += 1 }
        runtime.volume = { _ in state.volume }
        runtime.setVolume = { _, value in state.volume = value }
        runtime.pan = { _ in state.pan }
        runtime.setPan = { _, value in state.pan = value }
        let player = P5AudioFilePlayer(
            file: file,
            nativeFile: nativeFile,
            nativeNode: AVAudioPlayerNode(),
            runtime: runtime
        )
        player.stateChanged = { state.transitions.append($0) }
        #expect(player.nativeNode.engine == nil)
        player.volume = 0.25
        player.pan = -0.5
        #expect(player.volume == 0.25)
        #expect(player.pan == -0.5)

        player.play()
        player.play()
        #expect(state.starts == [0])
        #expect(state.playCount == 2)
        player.pause()
        #expect(player.state == .paused)
        player.play()
        try player.seek(to: 0.005)
        #expect(state.starts.last == 40)
        #expect(player.state == .playing)
        player.pause()
        try player.seek(to: 0.002)
        #expect(player.state == .paused)

        for time in [Double.nan, -1, file.duration + 1] {
            #expect(throws: P5AudioError.invalidTime) { try player.seek(to: time) }
        }
        try player.seek(to: file.duration)
        #expect(player.state == .ended)
        player.play()
        state.completion?()
        await Self.waitUntil { player.state == .ended }
        player.loops = true
        player.play()
        state.completion?()
        await Self.waitUntil { player.state == .playing }
        player.stop()
        #expect(player.state == .stopped)
        #expect(state.pauseCount == 2)
        #expect(state.stopCount >= 4)
    }

    @Test("Default AVAudioEngine bindings render oscillator, analysis, and file nodes offline")
    @MainActor
    func nativeEngine() async throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        )
        var engine: P5AudioEngine? = P5AudioEngine()
        let observed = try #require(engine)
        try observed.nativeEngine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 64
        )
        let oscillator = try observed.makeOscillator(
            waveform: .sine,
            frequency: 1_000,
            amplitude: 0.5
        )
        let analyzer = try P5AudioAnalyzer(fftSize: 64)
        try observed.installAnalyzer(analyzer)
        observed.outputVolume = 0.75
        #expect(observed.outputVolume == 0.75)
        oscillator.play()
        try observed.start()
        let rendered = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        let status = try observed.nativeEngine.renderOffline(64, to: rendered)
        #expect(status == .success)
        #expect(rendered.floatChannelData?[0][1] != 0)
        _ = try analyzer.process(rendered)
        observed.pause()
        observed.removeAnalyzer()
        observed.stop()
        engine = nil
        _ = observed

        let url = Self.temporaryURL(extension: "caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeAudio(to: url, frameCount: 32)
        let file = try P5AudioFile(url: url)
        let fileEngine = P5AudioEngine()
        try fileEngine.nativeEngine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 64
        )
        let player = try fileEngine.makeFilePlayer(for: file)
        player.volume = 0.5
        player.pan = 0.25
        #expect(player.volume == 0.5)
        #expect(player.pan == 0.25)
        try player.seek(to: 0)
        player.play()
        try fileEngine.start()
        let fileBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        _ = try fileEngine.nativeEngine.renderOffline(64, to: fileBuffer)
        player.pause()
        player.stop()
        fileEngine.stop()

        let liveEngine = P5AudioEngine()
        let liveAnalyzer = try P5AudioAnalyzer(fftSize: 64)
        let liveOscillator = try liveEngine.makeOscillator(
            waveform: .sine,
            frequency: 440,
            amplitude: 0.1
        )
        let liveFilePlayer = try liveEngine.makeFilePlayer(for: file)
        try liveEngine.installAnalyzer(liveAnalyzer)
        liveOscillator.play()
        try liveEngine.start()
        liveFilePlayer.play()
        try await Task.sleep(for: .milliseconds(150))
        #expect(liveAnalyzer.latest != nil)
        #expect(liveFilePlayer.state == .ended)
        liveEngine.stop()
    }

    @Test("Installed taps and engines release native resources on deinitialization")
    @MainActor
    func cleanup() throws {
        let state = AudioEngineState()
        var runtime = P5AudioEngineRuntime()
        runtime.installTap = { _, _, _ in }
        runtime.removeTap = { _ in state.removeTapCount += 1 }
        runtime.stop = { _ in state.stopCount += 1 }
        do {
            var engine: P5AudioEngine? = P5AudioEngine(
                nativeEngine: AVAudioEngine(),
                runtime: runtime
            )
            try engine?.installAnalyzer(P5AudioAnalyzer(fftSize: 32))
            engine = nil
        }
        #expect(state.removeTapCount == 1)
        #expect(state.stopCount == 1)
        do {
            _ = P5AudioEngine(nativeEngine: AVAudioEngine(), runtime: runtime)
        }
        #expect(state.removeTapCount == 1)
        #expect(state.stopCount == 2)
    }

    @Test("Invalid audio values terminate at their public boundaries")
    func invalidValues() async {
        await #expect(processExitsWith: .failure) {
            _ = P5AudioEnvelope(attackTime: .nan)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioEnvelope(decayTime: -Double.infinity)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioEnvelope(sustainLevel: 2)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioEnvelope(releaseTime: -Double.infinity)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioEnvelope().amplitude(at: -.infinity)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioEnvelope().amplitude(at: 0, releaseAt: .nan)
        }

        await #expect(processExitsWith: .failure) {
            _ = P5AudioAnalysis(amplitude: -1, spectrum: [0, 0], sampleRate: 8, fftSize: 4)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioAnalysis(amplitude: 0, spectrum: [0, 0], sampleRate: 0, fftSize: 4)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioAnalysis(amplitude: 0, spectrum: [0], sampleRate: 8, fftSize: 3)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioAnalysis(amplitude: 0, spectrum: [0], sampleRate: 8, fftSize: 4)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioAnalysis(amplitude: 0, spectrum: [-1, 0], sampleRate: 8, fftSize: 4)
        }
        await #expect(processExitsWith: .failure) {
            _ = P5AudioAnalysis(
                amplitude: 0,
                spectrum: [0, 0],
                sampleRate: 8,
                fftSize: 4
            ).frequency(forBin: 2)
        }
        await #expect(processExitsWith: .failure) {
            _ = try P5AudioAnalyzer(fftSize: 31)
        }
        await #expect(processExitsWith: .failure) {
            _ = try P5AudioAnalyzer(fftSize: 48)
        }
        await #expect(processExitsWith: .failure) {
            _ = try P5AudioAnalyzer(fftSize: 65_536)
        }

        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let engine = P5AudioEngine()
                engine.outputVolume = .nan
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let engine = P5AudioEngine()
                _ = try! engine.makeOscillator(frequency: 0)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let engine = P5AudioEngine()
                _ = try! engine.makeOscillator(amplitude: 2)
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let engine = P5AudioEngine()
                let oscillator = try! engine.makeOscillator()
                oscillator.frequency = .nan
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let engine = P5AudioEngine()
                let oscillator = try! engine.makeOscillator()
                oscillator.amplitude = -1
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let player = try! Self.makeBoundaryPlayer()
                player.volume = .nan
            }
        }
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let player = try! Self.makeBoundaryPlayer()
                player.pan = 2
            }
        }
    }

    private static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private static func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("P5Audio-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private static func writeAudio(to url: URL, frameCount: AVAudioFrameCount) throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard frameCount > 0 else { return }
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            buffer.floatChannelData?[0][frame] = sin(2 * .pi * 440 * Float(frame) / 8_000)
        }
        try file.write(from: buffer)
    }

    private static func buffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        )
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            buffer.floatChannelData?[0][index] = samples[index]
        }
        return buffer
    }

    @MainActor
    private static func makeBoundaryPlayer() throws -> P5AudioFilePlayer {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "P5AudioBoundary-\(ProcessInfo.processInfo.processIdentifier).caf"
        )
        try? FileManager.default.removeItem(at: url)
        try writeAudio(to: url, frameCount: 1)
        let file = try P5AudioFile(url: url)
        return try P5AudioEngine().makeFilePlayer(for: file)
    }

    private static func render(
        _ state: P5OscillatorRenderState,
        frameCount: Int,
        sampleRate: Double
    ) throws -> [Float] {
        let buffer = try Self.buffer(
            samples: Array(repeating: 0, count: frameCount),
            sampleRate: sampleRate
        )
        state.render(
            frameCount: frameCount,
            sampleRate: sampleRate,
            buffers: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        )
        return Array(
            UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: frameCount)
        )
    }

    @MainActor
    private static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<200 where predicate() == false {
            await Task.yield()
        }
        #expect(predicate())
    }
}

private enum StubAudioError: String, Error, LocalizedError {
    case file
    case transform
    case start

    var errorDescription: String? { rawValue }
}

private final class AudioEngineState: @unchecked Sendable {
    var prepareCount = 0
    var startCount = 0
    var pauseCount = 0
    var stopCount = 0
    var resetCount = 0
    var attachCount = 0
    var removeTapCount = 0
    var volume: Float = 1
    var startFails = false
    var connectFormats: [Double?] = []
    var tapSize: AVAudioFrameCount?
    var tapHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var transitions: [P5AudioEngineState] = []
}

private final class AudioPlayerState: @unchecked Sendable {
    var starts: [AVAudioFramePosition] = []
    var counts: [AVAudioFrameCount] = []
    var playCount = 0
    var pauseCount = 0
    var stopCount = 0
    var volume: Float = 1
    var pan: Float = 0
    var completion: (@Sendable () -> Void)?
    var transitions: [P5AudioFilePlayerState] = []
}
