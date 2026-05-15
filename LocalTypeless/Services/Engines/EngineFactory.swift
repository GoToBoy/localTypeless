import Foundation

/// Picks the right `DictationEngine` for the current build at startup.
///
/// `APPLE_SILICON_ENGINE` is set in the build settings of the Apple Silicon
/// xcodeproj (generated from `project.yml`). The portable build (generated
/// from `project.portable.yml`) leaves it undefined.
enum EngineFactory {
    @MainActor
    static func make(store: ModelStatusStore) -> any DictationEngine {
        #if APPLE_SILICON_ENGINE
        return AppleSiliconEngine(store: store)
        #else
        return PortableEngine(store: store)
        #endif
    }
}
