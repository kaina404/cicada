import Testing
@testable import Cicada

@MainActor
struct FastReadingAlignTests {
    let script = CoachScript.words("""
    I would use Kotlin coroutines with Jetpack Compose. Then I cache the first screen in Room, \
    so the user sees data right away. Next I measure the startup time with Macrobenchmark.
    """)

    func words(_ text: String) -> [String] { CoachScript.words(text) }

    @Test func exactReadingMovesToTheLastHeardWord() {
        #expect(FastReadingAlign.advance(heard: words("I would use Kotlin coroutines"), script: script, cursor: 0) == 5)
    }

    @Test func accentedAndMisheardWordsStillFollow() {
        // d/t voicing, dropped endings, l/r swap, and "Kotlin" heard as "cotton".
        let heard = words("I would use cotton coroutine wiz jet pack compose")
        #expect(FastReadingAlign.advance(heard: heard, script: script, cursor: 0) == 8)
        let later = words("then I catch the first sclean in loom")
        #expect(FastReadingAlign.advance(heard: later, script: script, cursor: 8) == 16)
    }

    @Test func fillersAndRepeatsDoNotStopOrSkip() {
        let heard = words("um so the user the user sees uh data")
        #expect(FastReadingAlign.advance(heard: heard, script: script, cursor: 16) == 21)
    }

    @Test func oneLuckyWordCannotJumpAhead() {
        #expect(FastReadingAlign.advance(heard: words("startup"), script: script, cursor: 0) == nil)
        #expect(FastReadingAlign.advance(heard: words("okay so um startup"), script: script, cursor: 0) == nil)
    }

    @Test func unrelatedSpeechStaysPut() {
        #expect(FastReadingAlign.advance(heard: words("sorry can you repeat the question please"), script: script, cursor: 5) == nil)
    }

    @Test func rereadingEarlierWordsNeverMovesBack() {
        #expect(FastReadingAlign.advance(heard: words("I would use Kotlin coroutines"), script: script, cursor: 12) == nil)
    }

    @Test func shortWordsAreNotSoundAlikes() {
        #expect(FastReadingAlign.similarity("it", "at") <= 0.5)
        #expect(FastReadingAlign.similarity("cotton", "kotlin") >= 0.6)
        #expect(FastReadingAlign.similarity("sclean", "screen") >= 0.6)
    }

    @Test func draftsAndFinalsMoveTheDisplayCursorOnlyForward() {
        let follow = FastReadingFollow()
        var coach = CoachScript()
        coach.replacePending("I would use Kotlin coroutines with Jetpack Compose.", since: [])
        // Text is fed directly, as the recognizer would, so the test needs no microphone.
        follow.update(enabled: true, script: coach)
        follow.hear("I would use cotton", final: false)
        #expect(follow.word == 4)
        follow.hear("I would", final: false)
        #expect(follow.word == 4, "A revised, shorter draft does not move back")
        follow.hear("I would use cotton coroutine", final: true)
        follow.hear("wiz jet pack", final: false)
        #expect(follow.word == 7)
        #expect(coach.cursor == 0, "The script's own reading progress is untouched")
        follow.update(enabled: false, script: coach)
        #expect(follow.word == nil && follow.status == .off)
    }

    @Test func leadRunsAheadAtReadingPaceButStopsAtTheSentenceEnd() {
        let follow = FastReadingFollow()
        var clock = 0.0
        follow.now = { clock }
        var coach = CoachScript()
        coach.replacePending("I would use Kotlin coroutines with Jetpack Compose. Then I cache the first screen.", since: [])
        follow.update(enabled: true, script: coach, lead: 2)
        follow.hear("I would", final: false)
        #expect(follow.heard == 2 && follow.word == 7, "2 s at a default 2.5 words a second")
        clock = 2; follow.hear("I would use Kotlin coroutines with", final: false)
        #expect(follow.heard == 6 && follow.word == 8, "Never past Compose, the end of the sentence")
        clock = 4; follow.hear("with jet pack compose", final: true)
        #expect(follow.heard == 8 && follow.word == 8, "A finished sentence gets no lead into the next")
        follow.update(enabled: false, script: coach)
    }

    @Test func watchPositionReplacesFastFollowPosition() {
        let follow = FastReadingFollow()
        var coach = CoachScript()
        coach.replacePending("I would use Kotlin coroutines with Jetpack Compose. Then I cache the first screen.", since: [])
        follow.update(enabled: true, script: coach)
        follow.hear("I would use Kotlin coroutines", final: true)
        #expect(follow.word == 5)
        follow.move(to: 8)
        #expect(follow.word == 8 && follow.heard == 8)
        // Old speech no longer aligns; reading on from the new place does.
        follow.hear("then I cache the", final: false)
        #expect(follow.word == 12)
        follow.move(to: 2)
        #expect(follow.word == 2, "The watch may move back too")
        follow.update(enabled: false, script: coach)
    }
}
