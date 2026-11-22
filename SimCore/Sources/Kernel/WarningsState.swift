import SimCoreContract

/// State section of the Warnings module. Only the Warnings module writes it.
public struct WarningsState: Sendable, Equatable {
    public var audio: AudioState

    public init(audio: AudioState = .blank) {
        self.audio = audio
    }
}
