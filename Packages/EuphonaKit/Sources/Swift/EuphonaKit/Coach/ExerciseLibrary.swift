import Foundation

/// Euphona's exercises. The coach (rules or a language model) only ever picks from these, so every
/// instruction a person gets was written and checked here. `CoachPlan` fits their targets to the
/// person.
///
/// The progression follows common voice-training practice: warm up with semi-occluded vocal tract
/// work (straw, lip trills, humming), find and hold a target pitch, then move resonance, then
/// intonation, then carry it into reading and speaking freely.
public enum ExerciseLibrary {
    /// `band` gives the pitch band for each level of the pitch skill; the glides are built around it.
    public static func exercises(for goal: VoiceGoal, band: (Int) -> PitchTarget) -> [Exercise] {
        let direction = goal == .feminine ? "bright" : "dark"
        func judged(_ measure: Measure, _ pass: Double, _ close: Double) -> ExerciseGoal {
            ExerciseGoal(measure: measure, pass: pass, close: close)
        }
        func around(_ target: PitchTarget, below: Double, above: Double, period: Double) -> PitchTarget {
            let range = target.range(at: 0)
            let center = (range.lowerBound * range.upperBound).squareRoot()
            return .glide(low: center / pow(2, below / 12), high: center * pow(2, above / 12), period: period, toleranceSemitones: 1.5)
        }
        return [
            Exercise(id: "straw", key: "straw", skill: nil, level: 1, tool: .timed, seconds: 60, goal: judged(.completed, 90, 50)),
            Exercise(id: "lip_trill", key: "lip_trill", skill: nil, level: 1, tool: .timed, seconds: 45, goal: judged(.completed, 90, 50)),
            Exercise(id: "hum", key: "hum", skill: nil, level: 1, tool: .timed, seconds: 60, goal: judged(.completed, 90, 50)),

            Exercise(id: "pitch_hold", key: "pitch_hold", skill: .pitch, level: 1, tool: .pitch(band(1)), seconds: 30, goal: judged(.onTarget, 60, 40)),
            Exercise(id: "pitch_siren", key: "pitch_siren", skill: .pitch, level: 2,
                     tool: .pitch(around(band(2), below: 6, above: 8, period: 4)), seconds: 30, goal: judged(.onTarget, 50, 30)),
            Exercise(id: "pitch_count", key: "pitch_count", skill: .pitch, level: 3, tool: .pitch(band(3)), seconds: 40, goal: judged(.onTarget, 70, 50)),
            Exercise(id: "pitch_sentences", key: "pitch_sentences", skill: .pitch, level: 4, tool: .pitch(band(4)), seconds: 60, goal: judged(.onTarget, 75, 55)),

            Exercise(id: "vowel_\(direction)", key: "vowel_\(direction)", skill: .resonance, level: 1, tool: .resonance, seconds: 30, goal: judged(.brightness, 55, 40)),
            Exercise(id: "dog_\(direction)", key: "dog_\(direction)", skill: .resonance, level: 2, tool: .resonance, seconds: 30, goal: judged(.brightness, 60, 45)),
            Exercise(id: "timbre_words", key: "timbre_words", skill: .resonance, level: 3, tool: .timbre, seconds: 40, goal: judged(.timbre, 55, 40)),
            Exercise(id: "timbre_sentences", key: "timbre_sentences", skill: .resonance, level: 4, tool: .timbre, seconds: 60, goal: judged(.timbre, 60, 45)),

            Exercise(id: "question_rise", key: "question_rise", skill: .intonation, level: 1,
                     tool: .pitch(around(band(4), below: 1, above: 4, period: 2.5)), seconds: 30, goal: judged(.onTarget, 50, 30)),
            Exercise(id: "reading_flow", key: "reading_flow", skill: .intonation, level: 2, tool: .reading, seconds: 40, goal: judged(.flow, 60, 45)),
            Exercise(id: "reading_score", key: "reading_score", skill: .intonation, level: 3, tool: .reading, seconds: 40, goal: judged(.score, 55, 40)),
            Exercise(id: "reading_score_high", key: "reading_score", skill: .intonation, level: 4, tool: .reading, seconds: 40, goal: judged(.score, 65, 50)),

            Exercise(id: "talk_short", key: "talk", skill: .carryOver, level: 1, tool: .conversation, seconds: 30, goal: judged(.score, 55, 40)),
            Exercise(id: "talk_long", key: "talk", skill: .carryOver, level: 2, tool: .conversation, seconds: 60, goal: judged(.score, 60, 45)),
            Exercise(id: "talk_high", key: "talk", skill: .carryOver, level: 3, tool: .conversation, seconds: 60, goal: judged(.score, 70, 55)),
        ]
    }

    public static func levels(of skill: Skill) -> Int {
        exercises(for: .feminine) { _ in .typicalBand(for: .feminine) }.filter { $0.skill == skill }.count
    }
}
