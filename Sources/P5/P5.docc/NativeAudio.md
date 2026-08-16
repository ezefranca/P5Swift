# Native Audio

Play files, synthesize periodic waveforms, shape amplitude, and inspect output with
AVAudioEngine and Accelerate.

## Own the engine lifecycle explicitly

Create ``P5AudioEngine`` on the main actor. Construction allocates a native graph but does not
activate an audio session or start rendering:

```swift
let audio = P5AudioEngine()

audio.stateChanged = { state in
    print(state)
}

try audio.start()
```

The host app owns `AVAudioSession` category, route, interruption, and activation policy on iOS.
This prevents a library call from interrupting other media or changing recording permissions.
Call ``P5AudioEngine/scenePhaseChanged(to:)`` from the host lifecycle. Inactive and background
transitions pause a running engine; returning active never resumes sound automatically.

Call ``P5AudioEngine/stop()`` when the experience is finished. The engine also removes its output
tap and stops native rendering when released.

## Play a local audio file

``P5AudioFile`` opens a local file and validates its duration, sample rate, and channel count.
Create a player through the engine so AVFoundation can connect the file's processing format to the
main mixer:

```swift
let file = try P5AudioFile(url: soundURL)
let player = try audio.makeFilePlayer(for: file)

player.volume = 0.8
player.pan = -0.25
player.loops = true

try audio.start()
player.play()
```

Use ``P5AudioFilePlayer/pause()``, ``P5AudioFilePlayer/stop()``, and
``P5AudioFilePlayer/seek(to:)`` for transport. Seeking preserves whether playback was active. A
seek to the file duration moves directly to ``P5AudioFilePlayerState/ended``; a later play starts
from the beginning. Completion means AVAudioEngine rendered the final audio data. Hardware route
latency can make the last sample audible slightly later.

## Generate an oscillator and envelope

``P5Oscillator`` uses an `AVAudioSourceNode` whose render state is synchronized independently of
the main actor. Choose a waveform, frequency, and peak amplitude when connecting it:

```swift
let oscillator = try audio.makeOscillator(
    waveform: .triangle,
    frequency: 220,
    amplitude: 0.4
)

try audio.start()
oscillator.play()
```

Trigger an attack-decay-sustain-release shape with ``P5AudioEnvelope``:

```swift
let envelope = P5AudioEnvelope(
    attackTime: 0.02,
    decayTime: 0.15,
    sustainLevel: 0.6,
    releaseTime: 0.3
)

oscillator.trigger(envelope: envelope)
oscillator.release()
```

Use ``P5AudioEnvelope/amplitude(at:releaseAt:)`` to inspect the same normalized curve for visual
animation or deterministic tests. Oscillator frequency is not restricted to the Nyquist range;
frequencies above half the negotiated sample rate alias like any directly sampled waveform.

## Measure amplitude and spectrum

``P5AudioAnalyzer`` applies a Hann window and an Accelerate discrete Fourier transform. Its FFT
size must be a power of two from 32 through 32,768. Install one analyzer on the engine's mixed
output:

```swift
let analyzer = try P5AudioAnalyzer(fftSize: 1_024)
try audio.installAnalyzer(analyzer)

if let snapshot = analyzer.latest {
    print(snapshot.amplitude)
    print(snapshot.frequency(forBin: 10))
}
```

``P5AudioAnalysis/amplitude`` is root-mean-square amplitude. The linear spectrum contains the
lower half of FFT bins, below the Nyquist frequency. Snapshots are immutable and `Codable`; reading
``P5AudioAnalyzer/latest`` is safe across the native render callback and application tasks.

For recorded or generated samples, run the same analysis without an engine:

```swift
let snapshot = try analyzer.analyze(samples: samples, sampleRate: 48_000)
```

``P5AudioAnalyzer/process(_:)`` copies and analyzes the first Float32 PCM channel immediately. It
never retains or mutates the supplied buffer. Installing an output analyzer does not access the
microphone and requires no media authorization. Remove it with
``P5AudioEngine/removeAnalyzer()`` when live visualization is no longer needed.
