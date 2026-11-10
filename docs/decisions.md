# How it's built, and why

The technical choices behind the app, each with its reason. What the app should be is in
[`roadmap.md`](roadmap.md).

## Analysis engine

- **The engine is our own Swift code** (`EuphonaKit/Engine`) with a thin C++ runner for ONNX Runtime
  (`pa_model_*` in `CEuphonaApple`). Speech detection is Silero VAD with its official algorithm and
  defaults; pitch is SwiftF0 0.1.2 from PyPI; embeddings are our own export of SpeechBrain's ECAPA
  (filterbank in the graph, FP16 weights); the timbre head and the ease and voice-quality models are our own.
  Speech flow, HNR/jitter/shimmer/CPPS, spectrum and `Scoring` are Swift.
- **Models run on ONNX Runtime 1.30 on the CPU.** It was 1.8 times faster than ncnn, and older ONNX
  Runtime versions used 4–5.5 GB on a one-minute recording (1.30 stays under 750 MB). Core ML was about
  twice as fast but used 0.9 GB more memory and about 5 s to prepare; to be measured again on iPhones.
- **ONNX Runtime's usage telemetry is switched off before the engine starts** (`CEuphonaApple`), so
  "no tracking" is a guarantee rather than an observation.
- **The release upload removes the embedded copy of `onnxruntime.framework`** (`tools/ci/upload.sh`).
  It is a static library already linked into the app, and App Store Connect rejects the copy Xcode adds.
- **One result schema, in Swift names** (`EuphonaResult`): timbre is a `ScoreTrack` (overall score plus
  per-window scores); flow and ease judge the whole recording, so they are single values (flow with
  the pace and pause share it came from); fields nobody reads are not stored, and the JSON
  is the default `Codable` form.
- **Live tools run the same models as a full analysis.** Live timbre embeds the speech in the last
  1.5 s twice a second and scores it only when at least half the window is speech. Live resonance is
  LPC (order 16 at 16 kHz, pre-emphasis from 50 Hz, 32 ms Hamming frames) with formants taken as the
  narrow peaks (−3 dB width ≤ 500 Hz) of the LPC envelope rather than polynomial roots, which needs
  no eigenvalue solver and drops broad slopes; frames must be loud and periodic. No maintained Swift
  formant library exists; Praat's tracker is GPL, so only its well-known choices were used.
- **Resonance is read against Hillenbrand et al. (1995) vowel averages:** brightness is where the
  vowel sits between the men's and women's average of the nearest landmark, on log frequencies, so
  one number moves with resonance whatever the vowel.
- **The pitch target band defaults to typical speaking pitch** (women 165–255 Hz, men 85–155 Hz,
  Baken & Orlikoff); a glide target moves evenly in semitones.
- **GPL-3.0-only with an App Store permission** (`LICENSE`, `LICENSE-EXCEPTION.md`): every
  distributed version must publish its source; the section 7 permission lets the app, and forks
  that publish their source, ship through app stores. The engine, scoring, models and text are
  Euphona's own (permissive dependencies only, all GPL-3.0 compatible); Project Pitchee and Pitchee
  for Android are credited in About under "Inspired by".
- **The privacy manifest declares only what the app does:** no tracking and no collected data;
  `UserDefaults` for the app's own settings (`CA92.1`) and file metadata of bundled models, which
  ONNX Runtime reads (`C617.1`).
- **Feedback is a GitHub issue the person posts from their own account:** the app fills in the
  new-issue page (message, and diagnostics they can read first) and sends nothing itself, so the App
  Store label stays "Data Not Collected". Issues are public, so diagnostics leave out the voice goal.
- **The result chime is synthesized** (`ResultChime`: six stretched partials, per-partial decay, small
  room reverb) instead of a sample, so pitch and loudness follow the score without resampling.
  Players feed a mixer before the reverb: an effect unit has one input bus, and a second connection
  silently disconnects the first.
- **Scoring is computed, not stored** (`EuphonaResult.composite` from the components through
  `Scoring`): old results follow rule changes, and `HistoryStore.rescoreAnalyses` updates the stored
  overall score on launch. The pitch scale's ends are the centers of the typical bands (115 and
  205 Hz); its midpoint (153 Hz) is the pink/blue line of the charts and the orb, so they all agree
  with the score. Fluency is a smoothstep from 30 to 80 of the lower of flow and ease, floor 0.8.
- **Fluency has two separate readings, Flow and Ease**, as the voice-quality literature keeps them:
  strain is learned from strain ratings, and style is never a fault. Flow is a transparent measure (`SpeechFlow`, limits from
  `tools/voice-model/flow.py` on FLEURS): articulation rate over 5.4 syllables/s and a pause share
  over 28 % cost; slow speech has no limit of its own. Natural FLEURS speech falls below 80 in 0.3 %
  of clips; halting 76 %, rushed 40 %, dragged 8 % (the rate measure is only moderately sharp, AUC
  0.90, so its limit favours few false alarms).
- **Ease is ridge regression on ECAPA statistics** (`train_ease.py`) against PVQD CAPE-V strain (r 0.74
  cross-validated; CPPS, HNR, jitter, shimmer and spectral balance alone reached 0.49–0.63 and read
  healthy voices as strained). Calibrated on healthy FLEURS speech: up to its 95th percentile is
  ease 100, PVQD voices rated 50+ have a median ease of 50. Healthy voices below 80: women 2.4 %,
  men 0.4 %. It may only ship while that check passes.
- **The shared package `EuphonaKit` holds everything that isn't screens:** the engine, recording,
  settings, history and statistics. It is tested with `swift test`, with no simulator needed.

## Models

- **Training lives in `tools/voice-model/`** (a uv project; data and results under the git-ignored
  `.build/voice-model/`). PyTorch for the heads and the WORLD vocoder (`pyworld`, MIT/BSD) are
  standard, maintained tools; the heads are small enough that nothing heavier is needed.
- **Embeddings for training come from SpeechBrain's ECAPA on the GPU,** the same Apache-licensed
  weights the app runs as `EuphonaECAPA`.
- **Data is Common Voice 19 (CC0) through the `fsicoli/common_voice_19_0` mirror,** since Mozilla
  moved Common Voice off Hugging Face; dev and test splits only, up to 100 speakers per gender in each
  of 53 languages, five languages held out. FLEURS (CC BY 4.0) is the independent test set.
- **Timbre learns a smooth scale from gender morphs** (pitch and formants moved together with WORLD,
  the label following the morph), because no public speech data has perceived-femininity ratings.
- **The timbre head is trained on all 53 Common Voice languages:**
  AUC 0.989 on held-out speakers, 0.986 on unseen languages, 0.994 on FLEURS, typical voices at
  about 17 and 84. FLEURS Japanese is left out of testing: its FEMALE dev clips are male voices
  (median F0 106-120 Hz), so it measured the labels.
- **A new model version re-analyzes the saved recordings at launch** (`Reanalysis`), so the whole
  history is scored by the same models; analyses without their recording keep their scores.

## Recording

- **Speaking pitch is the median of the voiced 50 ms windows** (`F0Metrics.speakingHz`), for the
  whole recording, each segment and a lesson's pitch: a laugh, a squeal or music under the voice
  moves it only as long as it lasts. It is computed from the stored windows, so old results follow.
- **Audio and video files can be analyzed** (the analysis screen's Import, not inside lessons): the
  first 60 seconds, read through `AVAssetReader`, the one reader for every file, since `AVAudioFile`
  can't open video containers. Its blocking decode loop runs on a dispatch queue, not a Swift
  concurrency thread: a few parallel reads on a three-core CI machine took every pool thread and
  never finished.

- **Voice Quality records the unprocessed microphone signal and then brings it to a standard level.**
  That signal is much quieter than with voice processing, and both speech detection and the model
  depend on loudness. Quiet speech is boosted (never room noise), so speech gets counted
  and scores stay comparable.
- **The orb follows your pitch while you speak.** Pitch is measured on a musical (semitone) scale
  around 165 Hz, the line between feminine and masculine. A short median filter drops the pitch
  tracker's occasional octave errors, smoothing stops flicker, the color holds through short pauses,
  and then it eases back to rest.
- **Voice Quality checks the recording before estimating** (`RecordingCheck`): clipping above 0.1 %
  of speech, less than 15 dB between speech and pauses, or under 10 s of voiced speech show what to
  change instead of a number, since each would read as a rougher voice.
- **Closing the analysis or Voice Quality screen cancels whatever is in progress.** Nothing half-done is
  saved.
- **Recordings are stored compressed (AAC)** to keep iCloud use small. Analysis always uses the
  original audio.

## History and settings

- **History is stored with SwiftData and synced through the person's private iCloud database.**
- **A result is compared with the latest earlier analysis toward the same voice goal.** New results and records opened from history use the same rule, so a record
  shows the same comparison wherever it is opened.
- **Erase All Data deletes records one by one,** because bulk deletes don't reach iCloud. This way the
  erase also reaches the person's other devices.

## Coach

- **Targets are personal** (`CoachPlan`): the baseline is the median of the latest three analyses
  toward the goal; pitch bands start a semitone per level from the person's own average and stop at
  the typical range's center; timbre, flow and score goals start 8 points (plus 5 per level)
  above the baseline; after two measured tries an exercise's goal rises to its recent median plus 5.
  The plan is rebuilt after every try and every analysis, and a lesson's steps pick their exercise
  when they start.
- **No lesson before the first analysis toward the goal**: the Coach tab asks for one instead, since
  every target and level grows from it. Until then
  the plan accepts no requests (`isChanged(by:)` is false), so quick replies and the chat tool can't
  adjust anything, and "Tell the coach" is hidden.
- **Analyses place each skill on the path** (`Placement`): the measure its exercises judge (pitch
  progress, timbre, the lower of flow and score, score) read across the skill's levels.
  Lesson passes and misses move it from there; placing never completes a skill. So the path follows
  the analyses, not only the lessons.
- **The Coach tab is a column of cards like Today and Progress** (at most 720 points wide, a titled
  card per part, a tinted ring per skill), not a `List`: a list on Mac is a full-width plain table
  with system-blue gauges, out of step with the other tabs.
- **The coach's language model only suggests plan changes** (`SuggestChange`): the suggestion shows
  as a quick reply under its answer and only the learner's tap applies it, because a small on-device
  model reads small talk as a request too easily.
- **A request that changes nothing isn't stored** (`CoachPlan.isChanged(by:)`): the focus level is
  clamped to the skill's levels, and the quick reply or chat tool says so instead of claiming a
  change. The card and the path show today's level, with an arrow when a request moved it.
- **A pass 20 points past the goal moves up a level at once**; after a pass the coach (rules or
  model) can only move on or go harder.

## Look

- **Icon tiles follow the theme** (`IconTile`, `ThemeColors.tile`): the palette's deep tint, leaning 40 %
  toward each tool's own accent at the far corner, so tiles read as the theme and still differ.

## Export

- **Images and PDFs are drawn by SwiftUI's `ImageRenderer`** (PNG through ImageIO, PDF page by page
  into a Core Graphics PDF context), from report views laid out for A4 in light mode with fixed type
  sizes: no dependency, and the report reuses the app's own colors and formatting. PDF libraries
  (TPPDF and the like) would need a second layout of the same content.
- **An export holds only what finds its records** (`ExportFile`: a record ID or "all", the model
  container, the format) and draws when the share sheet or save panel asks, so offering it costs
  nothing. One Transferable type covers both formats with `exportingCondition`.
- **The list exports as a table**, newest first, 24 rows per PDF page and one long image; the analysis
  as one page with the score, components, what to work on and the pitch curve over the goal's range.
  On Mac the share menu also saves to a file, since the Mac share menu has no "Save to Files"; the
  sandbox grants read-write access to files the user picks, which saving needs.

## Text and languages

- **A count's words come from one plural string** (`today_streak`, the number drawn large inside it on
  the streak screen), never a number beside a separate label, which can't agree with the count.
- **All text is Euphona's own**, in `tools/strings/strings.json` (English and Simplified Chinese),
  built into the catalogs by `tools/strings/build_strings.py`, which keeps only the strings the code
  uses (by their generated symbol, or a `localized(key: "prefix_\(…)")` prefix). Every other language
  has one file, `translations/<code>.json`, with every key (checked by `check_translations.py`);
  permission prompts are in `infoplist_strings.json`, counted strings become plural variations
  (`plurals.json`) and Mac wording device variations (`mac.json`).
- **Numbers, units, signs and times go through one place** (`DesignSystem/Formatting.swift`), so they
  follow the locale (Measurement for Hz, percent style, signed changes instead of arrow characters,
  Duration for clocks).
- **Formulas are shown as text with typeset subscripts** (the scoring rules screen): no math renderer
  is needed; `X_r` becomes a lowered, smaller subscript, since Unicode subscript letters are missing
  from the italic system font.
- **Detail screens are grouped forms** (result, scoring rules, metric detail, Voice Quality result):
  inset cards on iPhone and iPad, System Settings-style groups on Mac, where a plain list drew a line
  under every row and made links clickable only on their text. Disclosure rows toggle from anywhere
  on the row (`RowDisclosureGroup`), and custom rows fill the row's width.

## Screens

- **The recording screen sits in a scroll view that never scrolls.** iOS 26 binds the navigation bar
  to the first scroll view it finds; when that was the reading passage, scrolling it changed the bar
  and pushed the page up for good. A UI test scrolls the passage and checks that
  the stage stays put.
- **The reading passage is one scrollable text,** so you can read ahead. Passages are switched from the passage's title on the recording screen, where you
  read them.
- **Every orb looks and moves the same way.** One function turns a balance into a color (mixed
  perceptually), used by the orb, its glow and the page tint. A slow swell rolls across every orb,
  small ones in lists included; the colors ride the swell around the balance, so the overall tone always
  matches the score.
- **The orb is a Metal shader** (`LiquidOrb.metal`, a SwiftUI `colorEffect`): two warped noise fields
  marble pink and blue light inside a lit glass sphere (fresnel rim, highlight, caustic), around the
  balance. A mesh gradient could not show flowing light. Its clock counts from launch, because the
  shader's 32-bit floats cannot resolve small steps of a reference-date time (the pattern froze).
  Hero orbs keep a thin, clear Liquid Glass bubble for the press response.
- **Practice tools share one `InstrumentPanel`**: live reading, one card, a Liquid Glass control
  bar; cards are `groupedCell` on the grouped background, like list rows.
- **Orbs inside lists have no glow.** List rows clip their content, which cut the glow into a visible
  rectangle; the page tint carries the color there instead.
- **Lists stay full width and center their content** (`readableContentWidth`), so on iPad the scroll
  bar stays at the window's edge instead of floating mid-screen.
- **Hero orbs grow with the window,** up to 1.5 times their iPhone size on iPad, by the tighter of width
  and height.
- **The orb's glow is a simple gradient drawn once, and a resting orb redraws 30 times a second and
  stops when off screen.** A glow re-blurred on every frame kept the device busy enough to make taps
  feel slow.
- **Links carry a destination value, and each stack maps values to screens in one place** (`Route`).
  Links that build their screen inline are matched by their position in the view tree, so a list that
  refreshed under the finger (a save, an iCloud change) could open another link's screen. A record is
  passed by its ID and looked up by the screen it opens. `EuphonaUITests` checks that each link opens
  its own screen.
- **On Mac, Analyze Voice opens its own centered window** (⌘R brings it to the front), closed with the
  window's own button, the way QuickTime opens a new recording. iPhone and iPad show it full screen.
- **Cards open with the standard slide; only Analyze Voice zooms open.** After going back from a
  zoom transition, iOS ignores taps until its spring has settled, so moving quickly from one card to
  the next felt stuck. The slide finishes quickly and never blocks the next tap.
- **Custom cards dip slightly the moment you touch them,** the way system buttons do, so a tap feels
  answered before the next screen opens.
- **The score count-up and its sound play once per result.** Lists rebuild rows as you scroll, so the
  result screen remembers that the reveal has played.
- **One recorder serves voice analysis and Voice Quality, one replay controller serves pitch and
  spectrum, and one `LiveInput` serves the live tools** (permission, start, failure, ordered feed).
- **Failures are shown, never swallowed** (`ErrorCenter`): a failed save, pin, delete or erase raises
  one system alert in the window in front; a store that cannot open falls back to memory and says so.
  Microphone failures show `CaptureFailureView` with the one action that fixes them.
- **Pin, share and delete are one modifier** (`recordActions`): the same context menu (and swipes in
  lists) everywhere a record appears.
- **Menu commands are scene-focused** (`AppCommands` with `focusedSceneValue`): File ▸ Analyze Voice
  (⌘R) and View ▸ tabs (⌘1…), on Mac and on iPad with a keyboard. The selected tab is restored.
- **Playback follows the display** (`TimelineView`) and the player's delegate reports the end, instead
  of a polling loop.
- **The app icon is drawn in code** (`swift tools/icon/render_icon.swift`): the voice orb inside the
  listening ring, in light, dark and tinted versions for iOS, and a Mac version with its own rounded
  square and margin as macOS 26 expects. Rerun it after changing the design.
- **Debug builds can open any screen with real sample analyses** (`-demo_audio <folder>`,
  `-demo_screen <name>`). `tools/screenshots/capture.sh` uses this to screenshot every screen, in light
  or dark mode. On Mac, `tools/screenshots/capture_mac.sh` captures each window without seeding demo
  data, because the Mac store is the person's real, iCloud-synced history.
- **The Mac Settings window uses the standard toolbar tabs** (General, Advanced, About), each sized to
  its content; iPhone and iPad keep the list with pushed pages. Mac forms label on the left and use
  radio groups and right-aligned buttons; sliders snap through their binding instead of `step:`, which
  draws a tick mark per step on Mac.
