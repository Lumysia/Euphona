# Known issues and to-do

## Not yet checked

- Running on iOS 26 itself (tested on iOS 27 only).
- iPad layouts.
- Speed, memory and battery use of the analysis on older iPhones, including whether Core ML would help
  there.
- Voice Quality scores from the leveled microphone signal against scores from a normal recording.

## Missing

- Translations in the 32 languages besides English and Simplified Chinese are checked for format,
  plurals and completeness but not yet read by native speakers; the score terms (flow, ease,
  fluency, timbre) and the Coach's name most need a review.

- Private Cloud Compute for the Coach: Apple grants `com.apple.developer.private-cloud-compute` on
  request; the team's profile can't include it yet, so the option stays hidden (it shows only where
  `PrivateCloudComputeLanguageModel` reports available).

- On iOS 27, Analyze Voice could become a tab with the system's prominent style instead of a floating
  button.

## Could be better

- From the literature review: a hidden-display transfer probe at the end of each Coach
  chapter, prompted same-vowel resonance against a personal baseline with confidence and rejection.
- Ease is validated on healthy FLEURS speakers and PVQD clinic voices only, not on trans and
  gender-diverse voices or deliberately light, breathy phonation; healthy women still read below 80
  more often than men (2.4 % against 0.4 %). Needs consented recordings from intended users.
- Flow's syllable counter misses quiet syllables (about 2 % of natural clips measure under 1.5/s)
  and compresses fast speech; a band-filtered detector (Sabu et al. 2021) would sharpen the rate.
- The result timeline's timbre chip showed "--" on a demo record; check whether timbre windows are
  missing there or only the demo data lacks them.
- Coach conversation: the first on-device answer after launch failed once in the simulator (model
  loading); the chat retries once. Not checked on a device.
- The language model reviews one try and picks again/easier/harder/next within the rules, and the
  chat can suggest a change to today's plan; it doesn't plan beyond today or across skills. Whether it
  should is a product question.
- The chat model sometimes asks "shall I make it easier?" without attaching the suggestion button;
  the quick replies below still confirm it in one tap.

- Live pitch sessions (`PitchSession`) still store a mean; the analysis uses the median.
- Mac: Import Audio is only in the analysis window's toolbar; no File menu command or drag and drop.

- Voice Quality estimates are not stored, so the lesson planner only sees the daily check-in when it
  decides on a rest day; storing the latest estimate would let a flagged voice steer to rest too.

- Xcode Previews crash at launch: SwiftData reports "Not a PersistentModel Type - AnalysisRecord" in the
  preview process, so views are checked with `-demo_screen` screenshots instead.
- Starting a recording in the simulator can abort inside CoreAudio (an RPC timeout initializing the input
  unit) when the host gives the simulator no input; real devices record normally. Recording therefore has
  no UI test.

- Cancelling an analysis drops the result, but the engine keeps working until it finishes: the
  analyzer has no cancellation check between stages.
- Spectrum and live pitch pause listening during replay.
- Live replay (`ReplayController`, `SpectrumMonitor.rewind`) still advances its playhead and page with
  a 16/33 ms loop; moving it to `TimelineView` needs the charts to compute the page from the time.
  The score count-up loop in `ScoreHero` stays: it keeps the ticks in step with the sound.
- Mac Settings tabs have fixed heights (a Form has no intrinsic height); check them in long languages
  and at large text sizes.

## Cleanup

- One owner for the audio session in EuphonaKit, shared by Voice Quality and recording.
- `PianoSynth` takes an `NSLock` on the render thread; `MicrophoneCapture` is `@unchecked Sendable`.
- Empty-section layout workarounds (the Mac result hero, the Settings reset footer).
- Score rule logic in `ScoreRulesView` belongs in the package next to `Scoring`.
- Literal numbers in `SpectrumView` (40, 8000 Hz) and `PianoView` (key sizes) to name once.
- The average-pitch reset has no UI; the gap slider reads inverted; threads uses a Stepper.

## Release

- ONNX Runtime, linked into the app binary, calls `statfs`/`fstatfs` (Apple's disk-space category).
  The privacy manifest declares only true reasons (`C617.1` file metadata, `CA92.1` defaults); if
  App Store Connect asks for a disk-space reason at upload, find the ORT code path before choosing one.

- CloudKit: deploy the development schema (history records) to production before the first App
  Store build.
