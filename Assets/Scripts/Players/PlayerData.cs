using System;

namespace MiniArcade.Players
{
    /// <summary>
    /// Per-player session state. Coin balances are intentionally private and
    /// must never be shown on the public TV view (spec 5.3).
    /// </summary>
    [Serializable]
    public class PlayerData
    {
        public string Id;
        public string DisplayName;
        public int AvatarIndex;
        public string Color = "#FF5DA2";

        /// <summary>Hidden currency. Starts at zero every session (spec 5.1).</summary>
        public int Coins;

        /// <summary>Total coins earned across the match, used for the final tie-breaker.</summary>
        public int TotalCoinsEarned;

        /// <summary>Mini-game wins, the primary victory metric (spec 5.4).</summary>
        public int Wins;

        public bool IsConnected = true;

        public PlayerData(string id, string displayName)
        {
            Id = id;
            DisplayName = displayName;
        }
    }
}
