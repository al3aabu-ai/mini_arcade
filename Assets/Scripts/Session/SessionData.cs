using System.Collections.Generic;
using MiniArcade.Players;

namespace MiniArcade.Session
{
    /// <summary>
    /// Authoritative state for one game session, owned by the Host.
    /// </summary>
    public class SessionData
    {
        public readonly List<PlayerData> Players = new List<PlayerData>();

        /// <summary>Mini-game ids the host selected for this match (3 per spec).</summary>
        public readonly List<string> SelectedMiniGames = new List<string>();

        public string RoomCode;
        public int CurrentRound;       // 0-based index into SelectedMiniGames
        public bool IsPremiumHost;     // Unlocks >2 players + full game library (spec 6)

        /// <summary>Free tier caps the room at two players (spec 6).</summary>
        public int MaxPlayers => IsPremiumHost ? 8 : 2;

        public void ResetForNewSession()
        {
            foreach (var p in Players)
            {
                p.Coins = 0;
                p.TotalCoinsEarned = 0;
                p.Wins = 0;
            }
            CurrentRound = 0;
        }
    }
}
