using MiniArcade.MiniGames.CoinRush;
using MiniArcade.MiniGames.MiniGolf;
using MiniArcade.MiniGames.Reaction;

namespace MiniArcade.MiniGames
{
    /// <summary>
    /// Registry of available mini-games. The free tier exposes this fixed
    /// rotation (spec section 6); the match cycles through it.
    /// </summary>
    public static class MiniGameCatalog
    {
        public static readonly string[] Ids = { "mini_golf", "coin_rush", "reaction" };

        public static IMiniGame Create(string id)
        {
            switch (id)
            {
                case "mini_golf": return new MiniGolfGame();
                case "reaction": return new ReactionGame();
                case "coin_rush":
                default: return new CoinRushGame();
            }
        }

        public static string DisplayName(string id)
        {
            switch (id)
            {
                case "mini_golf": return "Party Mini Golf";
                case "reaction": return "Reaction Duel";
                case "coin_rush": return "Coin Rush";
                default: return id;
            }
        }
    }
}
