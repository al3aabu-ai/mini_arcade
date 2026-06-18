using System;
using System.Collections.Generic;
using MiniArcade.Players;

namespace MiniArcade.MiniGames
{
    /// <summary>
    /// Contract every mini-game implements so the match layer can run and score
    /// them interchangeably (spec section 5). Scores are integers where
    /// <b>higher is better</b>, so the economy and the bidding "advantage"
    /// (a starting-score bonus) apply uniformly across games.
    /// </summary>
    public interface IMiniGame
    {
        string Id { get; }
        string DisplayName { get; }

        /// <summary>Short live instruction shown on the TV/controllers (e.g. "GO!").</summary>
        string Prompt { get; }

        bool Running { get; }
        float TimeLeft { get; }

        /// <summary>Live scores per player id (higher = better).</summary>
        IReadOnlyDictionary<string, int> Scores { get; }

        /// <summary>Raised once with per-player placements + collected coins.</summary>
        event Action<MiniGameResult> Finished;

        /// <param name="players">Roster for this round.</param>
        /// <param name="startingBonus">Per-player head-start score from bidding (may be empty).</param>
        void Begin(IReadOnlyList<PlayerData> players, IReadOnlyDictionary<string, int> startingBonus);

        void Tick(float deltaTime);

        /// <summary>A controller action from the given player.</summary>
        void HandleInput(string playerId, string action);

        void End();
    }
}
