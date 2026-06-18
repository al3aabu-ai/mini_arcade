namespace MiniArcade.Core
{
    /// <summary>
    /// High-level application / session states that drive the whole experience.
    /// Mirrors the game loop in the design spec:
    /// Lobby -> Mini-Game Select -> Mini-Game -> Bidding -> Results.
    /// </summary>
    public enum AppState
    {
        Boot,
        Onboarding,     // Guest vs. Login gateway (spec section 2)
        Lobby,          // Players join the host's room (spec 4.1)
        MiniGameSelect, // Host picks the three mini-games
        MiniGame,       // A mini-game is being played
        Bidding,        // Secret blind-bidding phase between rounds (spec 5.3)
        Results         // Final rankings / tie-breaker (spec 5.4)
    }
}
