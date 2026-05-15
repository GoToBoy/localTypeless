import XCTest
@testable import LocalTypeless

/// Wiring contract for `EngineFactory` and the two concrete engines.
/// The test runs in both build flavors — the `#if` branches assert that the
/// factory hands back the right engine and that engine's invariants hold.
@MainActor
final class EngineFactoryTests: XCTestCase {

    func test_factory_returns_non_nil_engine_with_consistent_required_models() {
        let store = ModelStatusStore()
        let engine = EngineFactory.make(store: store)

        // requiredModelKinds must be a stable, finite list.
        let kinds = engine.requiredModelKinds
        XCTAssertEqual(Set(kinds).count, kinds.count, "requiredModelKinds must not contain duplicates")
        XCTAssertEqual(engine.modelSlots.map(\.kind), kinds)
        XCTAssertEqual(engine.modelSlots.filter { $0.role == .speech }.count, 1)
    }

    func test_factory_returns_apple_silicon_engine_on_apple_silicon_build() {
        let store = ModelStatusStore()
        let engine = EngineFactory.make(store: store)

        #if APPLE_SILICON_ENGINE
        XCTAssertTrue(engine is AppleSiliconEngine,
                      "APPLE_SILICON_ENGINE build must return AppleSiliconEngine, got \(type(of: engine))")
        XCTAssertNotNil(engine.polish, "Apple Silicon engine must provide polish")
        XCTAssertEqual(Set(engine.requiredModelKinds),
                       [.asrWhisperLargeV3Turbo, .polishQwen25_3bInstruct4bit])
        XCTAssertEqual(engine.modelSlots, [
            EngineModelSlot(role: .speech, kind: .asrWhisperLargeV3Turbo),
            EngineModelSlot(role: .polish, kind: .polishQwen25_3bInstruct4bit)
        ])
        #else
        XCTAssertTrue(engine is PortableEngine,
                      "Portable build must return PortableEngine, got \(type(of: engine))")
        XCTAssertNil(engine.polish, "Portable engine must not provide polish (Intel has no MLX)")
        XCTAssertEqual(Set(engine.requiredModelKinds), [.asrWhisperCppSmall])
        XCTAssertEqual(engine.modelSlots, [
            EngineModelSlot(role: .speech, kind: .asrWhisperCppSmall)
        ])
        #endif
    }

    func test_engine_rejects_unknown_model_kinds() async {
        let store = ModelStatusStore()
        let engine = EngineFactory.make(store: store)

        // Pick a kind from the *other* engine's required set so the test stays
        // meaningful even if requiredModelKinds grows.
        #if APPLE_SILICON_ENGINE
        let foreign: ModelKind = .asrWhisperCppSmall
        #else
        let foreign: ModelKind = .asrWhisperLargeV3Turbo
        #endif
        XCTAssertFalse(engine.requiredModelKinds.contains(foreign),
                       "foreign kind \(foreign) must not be owned by this engine — test would silently pass")

        // download(_:) for a kind this engine doesn't own should throw, not crash.
        do {
            try await engine.download(foreign)
            XCTFail("expected throw for unsupported kind \(foreign)")
        } catch {
            // expected — any error type is fine; we just don't want a crash or silent success
        }
    }
}
