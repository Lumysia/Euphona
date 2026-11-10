# Roadmap

What Euphona is meant to be: the product decisions behind it.

## Scope

- Euphona's own voice training app, inspired by
  [Pitchee for Android](https://github.com/Project-Pitchee/Pitchee-Android): its own engine, models,
  scoring, Coach and text, designed to feel at home on Apple devices.
- One app for iPhone, iPad and Mac, for iOS, iPadOS and macOS 26 or later. Newer system features are
  used where available.
- History syncs between devices with iCloud.

## Scoring models

- Euphona trains its own timbre and ease models on public, openly licensed recordings in as
  many languages as possible.
- **Timbre** is a smooth scale, not a yes/no call: typical feminine voices land around 85–90, typical
  masculine voices around 10–15, and voices in between land in between, so every step of progress
  moves the score.
- **Flow and Ease** make up fluency. Flow is an even pace with ordinary pauses; Ease is the
  absence of audible squeezing or strain. Both count in the overall score through the lower of the
  two (at most a fifth off). Style is not penalized: a slow, flat, lively or light (falsetto-like)
  delivery is not a fault, because a score that punishes gender-nonconforming voices would be
  biased. Pitch raised without resonance shows in timbre and the resonance chart instead.
- **Voice Quality** is an estimate of how a voice sounds to listeners
  (dysphonia-like roughness, breathiness, strain), not a medical diagnosis. It needs about 20 seconds
  of talking (15 s of detected speech, after which it starts by itself), checks the recording first (clipping, noise, too little voicing), and shows the user's
  own comfort report beside the estimate.
- **The overall score is even and gentle.** One formula for both goals, with no caps or cut-offs, so
  a small change in the voice is a small change in the score and every bit of progress shows:
  Voice = 0.6 × Timbre + 0.4 × Pitch (pitch counted evenly in semitones from typical masculine to
  typical feminine speech), times a fluency factor. Faults such as a pressed or squeezed voice cost
  points, but at most a fifth of the score, and nothing is counted twice. Full marks need both
  timbre and pitch at the goal. When the rules change, stored scores follow.
- **Later: a voluntary "help improve scoring" program**, where people can donate recordings or rate
  others' with informed consent, to build the listener-rated data that better scores need. It needs
  a server and ideally ethics review, so it is not part of the current work.

## Layout

- Four tabs: **Today**, **Practice** (live pitch, live timbre, resonance, spectrum, piano, Voice Quality),
  **Progress** (trends, calendar, all recordings) and **Coach**.
- **Coach** teaches with the app's own tools. A fixed skill path (pitch control → resonance →
  intonation and flow → everyday speech) and one lesson a day of about ten minutes. Each step
  explains what to do and why, lets you try it with a tool built into the lesson (live pitch with a
  target band, live timbre, the piano for reference notes, a short recorded reading), measures the
  try, and then reviews it and decides the next step: again, easier, harder or on. Lessons,
  attempts and the coach's notes are kept and synced, and each skill shows how far along it is.
- Coaching uses Apple's own language models: on the device by default, or Private Cloud Compute, or
  none; chosen in the welcome sheet and in Settings. Exercises come from Euphona's own library, so
  the coach chooses and tunes them but never invents one; pain or a very tired voice steers to rest and
  relaxation. Without a model the same lessons run with written explanations. Live hints while you
  speak come from rules, since a language model is too slow for that.
- **Talking to the coach.** Quick replies on the Coach tab, in lessons and in the conversation (too
  easy, too hard, my voice is tired, practise a skill, back to my plan), and a conversation page for
  anything else when a language model is on. A quick reply changes today's plan at once and the
  coach answers in a sentence; in the conversation the coach suggests a change, which applies when
  it is tapped. Tomorrow the plan follows the results again.
- **After an analysis**, a reveal page comes first: the orb settles while a short piano phrase rises
  from low to high and stops where this result lands, with a few simple numbers. When the day extends
  the streak, a streak celebration comes before it. "Next" opens the full results. A day counts for
  the streak with a full analysis or a finished coach lesson.
- **Feedback** from Settings: free text plus anonymous diagnostics (device model, system, app and
  model versions, language, recent scores; never audio, never an identifier), stored in the app's
  CloudKit public database. The App Store review prompt appears only after good moments.
- **Analyze Voice** is always one tap away: a floating button above the tabs on iPhone and iPad, a
  toolbar button and ⌘R on Mac. Recording and results take the full screen.
- The signature visual is the **voice orb**, a sphere of liquid light: pink and blue light flowing
  inside clear glass, like Siri's glow. Pink means feminine and blue means masculine, and its mix
  shows the balance. While you speak, the light swells and follows your pitch live. The exact numbers
  are always shown next to it.
- **Practice** pages are one family of instrument panels: a large live reading on top (such as
  "182 Hz · F♯3"), one large chart card, and a Liquid Glass control bar at the bottom (start, pause,
  look back). The piano is a native keyboard in the spirit of GarageBand, with the current pitch and
  the target range lit on the keys. Color is the theme color plus pink and blue.
- Pink, blue and every chart color lean a little toward the chosen theme color, so each theme looks
  like one family of colors; pink still means feminine and blue masculine.

## Design principles

The bar for every screen, old and new (the Coach and every new tool included): Apple-native taste,
beautiful, simple, powerful and elegant. A fix or a new feature that makes a screen busier or less
native is not done.

1. **Glass for controls, not content.** The tab bar, toolbars and floating buttons use Liquid Glass.
   Scores, charts and cards sit on plain backgrounds.
2. **One big thing per screen.** A large number or the orb first, then a short summary, then the
   details in grouped lists, like the Health and Fitness apps.
3. **System parts first.** System lists, charts, menus and symbols, so the app behaves like the rest
   of the device, including dark mode, text size and accessibility.
4. **Color only where it means something.** The theme color for actions; pink, blue and the score
   colors only on data.
5. **Everything responds.** Taps answer immediately, screens move with transitions, and key moments
   (enough speech recorded, a result ready) give a light haptic.
6. **Each device its own way.** Touch on iPhone, pointer hover on iPad, and menus, hover and keyboard
   shortcuts on Mac.
