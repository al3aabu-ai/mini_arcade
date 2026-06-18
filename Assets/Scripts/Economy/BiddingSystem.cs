using System.Collections.Generic;
using MiniArcade.Players;

namespace MiniArcade.Economy
{
    /// <summary>
    /// Handles the secret blind-bidding phase between rounds (spec 5.3).
    /// Balances and bid amounts are private and never surfaced to the public view;
    /// only whether a player <em>has</em> bid is observable.
    /// </summary>
    public class BiddingSystem
    {
        private readonly Dictionary<string, int> _bids = new Dictionary<string, int>();

        public bool IsOpen { get; private set; }
        public int BidCount => _bids.Count;

        public void OpenWindow()
        {
            _bids.Clear();
            IsOpen = true;
        }

        public bool HasBid(string playerId) => _bids.ContainsKey(playerId);

        /// <summary>Record a player's blind bid, rejecting anything unaffordable.</summary>
        public bool PlaceBid(PlayerData player, int amount)
        {
            if (!IsOpen || player == null || amount < 0 || amount > player.Coins)
                return false;

            _bids[player.Id] = amount;
            return true;
        }

        /// <summary>Close bidding and return the sealed bids for resolution.</summary>
        public IReadOnlyDictionary<string, int> CloseWindow()
        {
            IsOpen = false;
            return _bids;
        }
    }
}
