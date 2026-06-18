using System;
using System.Collections.Generic;
using UnityEngine;
using MiniArcade.Players;

namespace MiniArcade.MiniGames.Reaction
{
    /// <summary>
    /// "Reaction Duel" - wait for GO, then tap. The faster your valid tap, the
    /// higher your score; tapping before GO is a false start (zero, locked out).
    /// Different skill, same one-button input, and score stays "higher = better"
    /// so the match economy and bidding advantage apply uniformly.
    /// </summary>
    public class ReactionGame : IMiniGame
    {
        private const int MaxScore = 5000;   // instant reaction
        private const float MaxWindow = 5f;  // seconds allowed to react after GO

        public string Id => "reaction";
        public string DisplayName => "Reaction Duel";
        public string Prompt => !_running ? "Get ready..." : (_go ? "GO! TAP!" : "Wait for it...");
        public bool Running => _running;
        public float TimeLeft => _go ? Mathf.Max(0f, _window) : 0f;
        public IReadOnlyDictionary<string, int> Scores => _scores;

        public event Action<MiniGameResult> Finished;

        private readonly Dictionary<string, int> _scores = new Dictionary<string, int>();
        private readonly Dictionary<string, int> _bonus = new Dictionary<string, int>();
        private readonly HashSet<string> _locked = new HashSet<string>(); // scored or false-started
        private List<PlayerData> _players = new List<PlayerData>();
        private bool _running;
        private bool _go;
        private float _countdown; // until GO
        private float _window;    // remaining after GO

        public void Begin(IReadOnlyList<PlayerData> players, IReadOnlyDictionary<string, int> startingBonus)
        {
            _players = new List<PlayerData>(players);
            _scores.Clear(); _bonus.Clear(); _locked.Clear();
            foreach (var p in _players)
            {
                _scores[p.Id] = 0;
                _bonus[p.Id] = (startingBonus != null && startingBonus.TryGetValue(p.Id, out int b)) ? b : 0;
            }
            _go = false;
            _countdown = UnityEngine.Random.Range(2f, 4.5f);
            _window = MaxWindow;
            _running = true;
        }

        public void Tick(float deltaTime)
        {
            if (!_running) return;
            if (!_go)
            {
                _countdown -= deltaTime;
                if (_countdown <= 0f) _go = true;
                return;
            }
            _window -= deltaTime;
            if (_window <= 0f || _locked.Count >= _players.Count) End();
        }

        public void HandleInput(string playerId, string action)
        {
            if (!_running || _locked.Contains(playerId) || (!string.IsNullOrEmpty(action) && action != "tap")) return;
            if (!_go)
            {
                _locked.Add(playerId); // false start: stays at 0
                _scores[playerId] = 0;
                return;
            }
            int reaction = Mathf.Max(1, Mathf.RoundToInt((_window / MaxWindow) * MaxScore));
            int bonus = _bonus.TryGetValue(playerId, out int b) ? b : 0;
            _scores[playerId] = reaction + bonus;
            _locked.Add(playerId);
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
                result.Placements[p.Id] = place;
                result.CoinsCollected[p.Id] = place == 1 ? 30 : (ScoreOf(p.Id) > 0 ? 10 : 0);
                place++;
            }
            Finished?.Invoke(result);
        }

        private int ScoreOf(string id) => _scores.TryGetValue(id, out int s) ? s : 0;
    }
}
