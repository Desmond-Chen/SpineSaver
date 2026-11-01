import XCTest
import SpineSaverCore

final class ReminderSceneTests: XCTestCase {
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    func testCatalog() {
        XCTAssertEqual(ReminderSceneCatalog.all.count, 6)
        XCTAssertEqual(Set(ReminderSceneCatalog.all.map(\.id)).count, 6)
        XCTAssertEqual(ReminderSceneCatalog.fallback.id, .walk)
    }

    func testPickerNeverRepeats() {
        var generator = Seeded(state: 42)
        var picker = ReminderScenePicker()
        var previous: SceneID?
        for _ in 0..<50 {
            let id = picker.next(using: &generator).id
            XCTAssertNotEqual(id, previous)
            previous = id
        }
    }

    func testPickerIsDeterministic() {
        var generatorA = Seeded(state: 7)
        var pickerA = ReminderScenePicker()
        let runA = (0..<12).map { _ in pickerA.next(using: &generatorA).id.rawValue }
        var generatorB = Seeded(state: 7)
        var pickerB = ReminderScenePicker()
        let runB = (0..<12).map { _ in pickerB.next(using: &generatorB).id.rawValue }
        XCTAssertEqual(runA, runB)
    }

    func testPickerAvoidsPrevious() {
        var generator = Seeded(state: 99)
        var picker = ReminderScenePicker(lastID: .walk)
        XCTAssertNotEqual(picker.next(using: &generator).id, .walk)
    }

    func testSymbolFallback() {
        let scene = ReminderSceneCatalog.scene(for: .restroom)
        XCTAssertEqual(SceneSymbolResolver.resolvedSymbol(for: scene, isAvailable: { _ in false }), "figure.walk")
        XCTAssertEqual(SceneSymbolResolver.resolvedSymbol(for: scene, isAvailable: { _ in true }), "toilet.fill")
    }

    func testCopyDoesNotClaimCompletion() {
        let banned = ["已起身", "已休息", "你完成了", "你已"]
        for scene in ReminderSceneCatalog.all {
            for word in banned {
                XCTAssertFalse(scene.title.contains(word))
                XCTAssertFalse(scene.detail.contains(word))
            }
        }
    }
}
