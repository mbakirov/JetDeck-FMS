import SimCoreContract

/// State section of the Displays module. Only the Displays module writes it.
public struct DisplaysState: Sendable, Equatable {
    public var pfd: PFDData
    public var nd: NDData
    public var ewd: EWDData
    public var mcdu: MCDUScreen
    public var fcu: FCUDisplay

    public init(
        pfd: PFDData = .blank, nd: NDData = .blank, ewd: EWDData = .blank,
        mcdu: MCDUScreen = .blank, fcu: FCUDisplay = .blank
    ) {
        self.pfd = pfd
        self.nd = nd
        self.ewd = ewd
        self.mcdu = mcdu
        self.fcu = fcu
    }
}
