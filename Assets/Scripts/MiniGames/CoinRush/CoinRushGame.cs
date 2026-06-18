using System;
using System.Collections.Generic;
using MiniArcade.Players;

namespace MiniArcade.MiniGames.CoinRush
{
    /// <summary>
    /// "Coin Rush" - a tap race. Tap as fast as you can before the timer ends;
    /// each tap is worth one point/coin. Score = taps (higher better). The
    /// bidding advantage is applied as a head-start to the score.
    /// </summary>
    public class CoinRushGame : IMiniGame
    {
        public const float Duration = 12f;

        public string Id => "coin_rush";
        public string DisplayName => "Coin Rush";
        public string Prompt => _running ? "Tap as fast as you can!" : "Get ready...";
        public bool Running => _running;
        public float TimeLeft => _timeLeft;
        public IReadOnlyDictionary<string, int> Scores => _scores;

        public event Action<MiniGameResult> Finished;

        private readonly Dictionary<string, int> _scores = new Dictionary<string, int>();
        private List<PlayerData> _players = new List<PlayerData>();
        private float _timeLeft;
        private bool _running;

        public void Begin(IReadOnlyList<PlayerData> players, IReadOnlyDictionary<string, int> startingBonus)
        {
            _players = new List<PlayerData>(players);
            _scores.Clear();
            foreach (var p in _players)
            {
                int bonus = (startingBonus != null && startingBonus.TryGetValue(p.Id, out int b)) ? b : 0;
                _scores[p.Id] = bonus; // advantage = head-start taps
            }
            _timeLeft = Duration;
            _running = true;
        }

        public void Tick(float deltaTime)
        {
            if (!_running) return;
            _timeLeft -= deltaTime;
            if (_timeLeft <= 0f) { _timeLeft = 0f; End(); }
        }

        public void HandleInput(string playerId, string action)
        {
            if (!_running || (!string.IsNullOrEmpty(action) && action != "tap")) return;
            _scores.TryGetValue(playerId, out int s);
            _scores[playerId] = s + 1;
        }

        public void End()
        {
            if (!_running) return;
            _running = false;

            var ordered = new List<PlayerData>(_players);
            ordered.Sort((a, b) => ScoreOf(b.Id).CompareTo(ScoreOf(a.Id)));

            var result = new MiniGameResult { MiniGameId = Id };
            int place = 1;
            foreach (var p in ordered)
            {
                result.Placements[p.Id] = place++;
                result.CoinsCollected[p.Id] = ScoreOf(p.Id); // 1 coin per tap (incl. head start)
            }
            Finished?.Invoke(result);
        }

        private int ScoreOf(string id) => _scores.TryGetValue(id, out int s) ? s : 0;
    }
}
