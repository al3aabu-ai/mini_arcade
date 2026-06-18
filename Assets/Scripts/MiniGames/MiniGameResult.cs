using System.Collections.Generic;

namespace MiniArcade.MiniGames
{
    /// <summary>
    /// Outcome of a single mini-game: final placement and coins collected,
    /// keyed by player id (spec 5.2 & 5.4).
    /// </summary>
    public class MiniGameResult
    {
        public string MiniGameId;

        /// <summary>Player id -> finishing place (1 = winner).</summary>
        public readonly Dictionary<string, int> Placements = new Dictionary<string, int>();

        /// <summary>Player id -> coins collected during the round.</summary>
        public readonly Dictionary<string, int> CoinsCollected = new Dictionary<string, int>();
    }
}
