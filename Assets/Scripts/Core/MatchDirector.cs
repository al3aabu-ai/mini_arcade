using System;
using System.Collections.Generic;
using MiniArcade.MiniGames;
using MiniArcade.Players;
using MiniArcade.Session;

namespace MiniArcade.Core
{
    /// <summary>
    /// Runs a match: a sequence of mini-game rounds, awarding coins and wins
    /// after each (spec section 5). The host opens a bidding phase between rounds and
    /// feeds the winning bidder's advantage back in via
    /// <see cref="ContinueWithAdvantage"/>.
    /// </summary>
    public class MatchDirector
    {
        public int TotalRounds { get; private set; }
        public int Round { get; private set; }         // 0-based index of the current/last round
        public IMiniGame Current { get; private set; }
        public MiniGameResult LastResult { get; private set; }
        public bool IsComplete => Round >= TotalRounds;

        /// <summary>Raised when a mini-game finishes (host then opens bidding or final results).</summary>
        public event Action RoundFinished;

        private readonly SessionData _session;
        private readonly List<string> _sequence = new List<string>();
        private Dictionary<string, int> _pendingAdvantage = new Dictionary<string, int>();

        public MatchDirector(SessionData session) { _session = session; }

        public string CurrentGameName =>
            (Round >= 0 && Round < _sequence.Count) ? MiniGameCatalog.DisplayName(_sequence[Round]) : "";

        public void StartMatch(int rounds)
        {
            TotalRounds = Math.Max(1, rounds);
            _sequence.Clear();
            var selected = _session.SelectedMiniGames;
            if (selected != null && selected.Count > 0)
            {
                for (int i = 0; i < TotalRounds; i++)
                    _sequence.Add(selected[i % selected.Count]);
            }
            else
            {
                for (int i = 0; i < TotalRounds; i++)
                    _sequence.Add(MiniGameCatalog.Ids[i % MiniGameCatalog.Ids.Length]);
            }
            Round = 0;
            _pendingAdvantage = new Dictionary<string, int>();
            BeginRound();
        }

        public void ContinueWithAdvantage(Dictionary<string, int> advantage)
        {
            _pendingAdvantage = advantage ?? new Dictionary<string, int>();
            BeginRound();
        }

        private void BeginRound()
        {
            Current = MiniGameCatalog.Create(_sequence[Round]);
            Current.Finished += OnGameFinished;
            Current.Begin(_session.Players, _pendingAdvantage);
            _pendingAdvantage = new Dictionary<string, int>();
        }

        private void OnGameFinished(MiniGameResult result)
        {
            LastResult = result;
            AwardCoins(result);
            Round++;
            RoundFinished?.Invoke();
        }

        public void Tick(float deltaTime)
        {
            if (Current != null && Current.Running) Current.Tick(deltaTime);
        }

        public void HandleInput(string playerId, string action) => Current?.HandleInput(playerId, action);

        private void AwardCoins(MiniGameResult result)
        {
            foreach (var p in _session.Players)
            {
                int collected = result.CoinsCollected.TryGetValue(p.Id, out int c) ? c : 0;
                int place = result.Placements.TryGetValue(p.Id, out int pl) ? pl : 0;
                int payout = collected + PlacementPayout(place);
                p.Coins += payout;
                p.TotalCoinsEarned += payout;
                if (place == 1) p.Wins++;
            }
        }

        public static int PlacementPayout(int place)
        {
            switch (place) { case 1: return 100; case 2: return 60; case 3: return 30; default: return 10; }
        }
    }
}
