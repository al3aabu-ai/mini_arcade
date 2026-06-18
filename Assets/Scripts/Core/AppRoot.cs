using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using MiniArcade.Economy;
using MiniArcade.MiniGames;
using MiniArcade.Networking;
using MiniArcade.Players;
using MiniArcade.Session;
using MiniArcade.Display;

namespace MiniArcade.Core
{
    /// <summary>
    /// Code-driven prototype entry point. It owns the host/controller role flow,
    /// both controller transports, the multi-round match director, and simple
    /// IMGUI screens so the project can run without hand-wired Unity scenes.
    /// </summary>
    public class AppRoot : MonoBehaviour
    {
        public static AppRoot Instance { get; private set; }

        public const int Port = 7777;
        public const int WebPort = 8080;

        private const string HostPlayerId = "HOST";
        private const float BroadcastInterval = 0.1f;
        private const float BiddingDuration = 8f;
        private const float BotTapInterval = 0.18f;
        private const int BidAdvantageScore = 10;

        private readonly GameStateMachine _sm = new GameStateMachine();
        private readonly SessionData _session = new SessionData();
        private readonly BiddingSystem _bidding = new BiddingSystem();

        private DeviceRole _role = DeviceRole.Undecided;
        private TcpHostService _host;
        private WebControllerServer _web;
        private TcpClientService _client;
        private TcpClientService _bot;
        private MatchDirector _match;

        private bool _hasBot;
        private string _webUrl = "";
        private string _myId;
        private string _myName = "Player";
        private string _joinIp = "127.0.0.1";
        private string _statusMessage = "";
        private string _advantageNotice = "";
        private string _webHostPlayerId;

        private int _totalRounds = 3;
        private int _hostBidAmount;
        private int _controllerBidAmount;
        private float _broadcastTimer;
        private float _botTapTimer;
        private float _biddingTimer;

        private LobbyStateDto _lobby;
        private MiniGameStateDto _mgState;
        private BiddingStateDto _bidState;
        private ResultsDto _results;
        private Rect _uiRect;
        private GUIStyle _tikiHeaderStyle;
        private GUIStyle _tikiLabelStyle;
        private GUIStyle _tikiButtonStyle;
        private GUIStyle _tikiShootButtonStyle;
        private GUIStyle _tikiFieldStyle;
        private GUIStyle _tikiToggleStyle;
        private GUIStyle _tikiPanelStyle;
        private GUIStyle _miniMutedStyle;
        private GUIStyle _miniCenterStyle;
        private GUIStyle _miniRoomCodeStyle;
        private GUIStyle _miniCardStyle;
        private GUIStyle _miniPillStyle;
        private GUIStyle _miniSecondaryButtonStyle;
        private GUIStyle _miniDangerButtonStyle;
        private GUIStyle _miniAvatarStyle;
        private Texture2D _woodTexture;
        private Texture2D _bambooTexture;
        private Texture2D _hotTexture;
        private Texture2D _panelTexture;
        private Texture2D _backgroundTexture;
        private Texture2D _glowTexture;
        private Texture2D _secondaryTexture;
        private Texture2D _fieldTexture;
        private Texture2D _pillTexture;
        private Texture2D _avatarYellowTexture;
        private Texture2D _avatarPinkTexture;
        private Texture2D _avatarGreenTexture;
        private Texture2D _pixelTexture;
        private Font _arcadeFont;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Boot()
        {
            if (Instance != null) return;

            var go = new GameObject("MiniArcadeApp");
            DontDestroyOnLoad(go);
            go.AddComponent<MainThreadDispatcher>();
            go.AddComponent<DisplayManager>();

            var camGo = new GameObject("AppCamera");
            camGo.transform.SetParent(go.transform);
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.09f, 0.10f, 0.13f);
            cam.targetDisplay = DisplayManager.PrivateDisplayIndex;

            Instance = go.AddComponent<AppRoot>();
        }

        private void Awake()
        {
            Instance = this;
            _sm.Set(AppState.Onboarding);
            Debug.Log("[AppRoot] Ready. Use the on-screen buttons to host or join.");
        }

        // ---------------- Host setup ----------------

        private void StartHost(bool withBot)
        {
            ShutdownServices();

            _role = DeviceRole.Host;
            _hasBot = withBot;
            _myId = HostPlayerId;
            _results = null;
            _mgState = null;
            _bidState = null;
            _advantageNotice = "";
            _webHostPlayerId = null;

            _host = new TcpHostService();
            _host.ClientDisconnected += OnHostClientDisconnected;
            _host.MessageReceived += OnHostMessage;
            _host.StartHost(Port);

            _web = new WebControllerServer();
            _web.ClientDisconnected += OnHostClientDisconnected;
            _web.MessageReceived += OnHostMessage;
            _web.StartServer(WebPort);
            _webUrl = $"http://{GetLocalIPv4()}:{WebPort}";

            _session.Players.Clear();
            _session.SelectedMiniGames.Clear();
            _session.CurrentRound = 0;
            _session.RoomCode = GenerateRoomCode();

            string hostName = string.IsNullOrWhiteSpace(_myName) ? "Host" : _myName + " (Host)";
            _session.Players.Add(new PlayerData(HostPlayerId, hostName)
            {
                AvatarIndex = 0,
                Color = "#FFD23F"
            });

            _sm.Set(AppState.Lobby);
            BroadcastLobby();

            if (withBot) StartBot();
            _statusMessage = $"Hosting. Unity controllers use port {Port}; browsers use {_webUrl}";
        }

        private void StartBot()
        {
            _bot = new TcpClientService();
            _bot.Connected += () =>
                _bot.Send(new NetworkMessage(MessageType.JoinRequest, null,
                    JsonUtility.ToJson(new JoinRequestDto { DisplayName = "Bot" })));
            _bot.Connect("127.0.0.1", Port);
        }

        private void OnHostClientDisconnected(string id)
        {
            var p = FindPlayer(id);
            if (p != null) _session.Players.Remove(p);
            if (_webHostPlayerId == id) _webHostPlayerId = null;
            if (_sm.Current == AppState.Lobby) BroadcastLobby();
        }

        private void OnHostMessage(NetworkMessage m)
        {
            switch (m.Type)
            {
                case MessageType.CreateRoom:
                    HandleCreateRoom(m);
                    break;
                case MessageType.JoinRoom:
                    HandleJoinRoom(m);
                    break;
                case MessageType.Profile:
                    HandleProfile(m);
                    break;
                case MessageType.StartPick:
                    HandleStartPick(m);
                    break;
                case MessageType.PickStart:
                    HandlePickStart(m);
                    break;
                case MessageType.Leave:
                    HandleLeave(m);
                    break;
                case MessageType.JoinRequest:
                    HandleJoinRequest(m);
                    break;
                case MessageType.ControllerInput:
                    if (_sm.Current == AppState.MiniGame)
                    {
                        var input = JsonUtility.FromJson<InputDto>(m.Payload);
                        _match?.HandleInput(m.SenderId, input != null ? input.Action : "tap");
                    }
                    break;
                case MessageType.Bid:
                    HandleBid(m);
                    break;
            }
        }

        private void HandleCreateRoom(NetworkMessage m)
        {
            if (_sm.Current != AppState.Lobby)
            {
                SendWebError(m.SenderId, "A match is already running.");
                return;
            }

            var dto = JsonUtility.FromJson<CreateRoomDto>(m.Payload);
            if (string.IsNullOrWhiteSpace(_session.RoomCode))
                _session.RoomCode = GenerateRoomCode();

            _webHostPlayerId = m.SenderId;

            var localHost = FindPlayer(HostPlayerId);
            if (localHost != null)
                _session.Players.Remove(localHost);

            AddOrUpdateWebPlayer(m.SenderId, dto != null ? dto.name : null, dto != null ? dto.color : null,
                dto != null ? dto.avatar : 0, true);

            HostSendTo(m.SenderId, new NetworkMessage(MessageType.RoomCreated, null,
                JsonUtility.ToJson(new RoomCreatedDto { code = _session.RoomCode })));
            BroadcastLobby();
            _statusMessage = $"Room {_session.RoomCode} is live at {_webUrl}";
        }

        private void HandleJoinRoom(NetworkMessage m)
        {
            if (_sm.Current != AppState.Lobby)
            {
                SendWebError(m.SenderId, "A match is already running.");
                return;
            }

            var dto = JsonUtility.FromJson<JoinRoomDto>(m.Payload);
            string code = dto != null ? NormalizeRoomCode(dto.code) : "";
            if (!string.Equals(code, _session.RoomCode, StringComparison.OrdinalIgnoreCase))
            {
                SendWebError(m.SenderId, "Room code not found.");
                return;
            }

            if (!_session.Players.Any(p => p.Id == m.SenderId) && _session.Players.Count >= _session.MaxPlayers)
            {
                SendWebError(m.SenderId, "Room is full.");
                return;
            }

            AddOrUpdateWebPlayer(m.SenderId, dto != null ? dto.name : null, dto != null ? dto.color : null,
                dto != null ? dto.avatar : 0, false);
            BroadcastLobby();
        }

        private void HandleProfile(NetworkMessage m)
        {
            var dto = JsonUtility.FromJson<CreateRoomDto>(m.Payload);
            var player = FindPlayer(m.SenderId);
            if (player == null || dto == null) return;

            player.DisplayName = SafePlayerName(dto.name, player.DisplayName);
            player.Color = SafeColor(dto.color, player.Color);
            player.AvatarIndex = Mathf.Clamp(dto.avatar, 0, 99);
            BroadcastLobby();
        }

        private void HandleStartPick(NetworkMessage m)
        {
            if (!IsWebHost(m.SenderId))
            {
                SendWebError(m.SenderId, "Only the host can pick games.");
                return;
            }

            HostSendTo(m.SenderId, new NetworkMessage(MessageType.GoPick, null, "{}"));
        }

        private void HandlePickStart(NetworkMessage m)
        {
            if (!IsWebHost(m.SenderId))
            {
                SendWebError(m.SenderId, "Only the host can start the match.");
                return;
            }

            var dto = JsonUtility.FromJson<PickStartDto>(m.Payload);
            var sequence = MapWebGameKeys(dto != null ? dto.games : null).ToList();
            if (sequence.Count == 0)
                sequence.AddRange(MiniGameCatalog.Ids);

            StartMatch(sequence);
        }

        private void HandleLeave(NetworkMessage m)
        {
            var p = FindPlayer(m.SenderId);
            if (p != null)
                _session.Players.Remove(p);
            if (_webHostPlayerId == m.SenderId)
                _webHostPlayerId = null;
            BroadcastLobby();
        }

        private void AddOrUpdateWebPlayer(string id, string name, string color, int avatar, bool isHost)
        {
            if (string.IsNullOrEmpty(id)) return;
            var player = FindPlayer(id);
            if (player == null)
            {
                player = new PlayerData(id, SafePlayerName(name, isHost ? "Host" : id));
                _session.Players.Add(player);
            }
            else
            {
                player.DisplayName = SafePlayerName(name, player.DisplayName);
            }

            player.Color = SafeColor(color, isHost ? "#FFD23F" : player.Color);
            player.AvatarIndex = Mathf.Clamp(avatar, 0, 99);
            player.IsConnected = true;
        }

        private bool IsWebHost(string senderId)
        {
            return !string.IsNullOrEmpty(senderId) &&
                   (senderId == _webHostPlayerId || (string.IsNullOrEmpty(_webHostPlayerId) && senderId == HostPlayerId));
        }

        private void SendWebError(string clientId, string message)
        {
            if (string.IsNullOrEmpty(clientId)) return;
            HostSendTo(clientId, new NetworkMessage(MessageType.Error, null,
                JsonUtility.ToJson(new ErrorDto { msg = message })));
        }

        private void HandleJoinRequest(NetworkMessage m)
        {
            if (_sm.Current != AppState.Lobby)
            {
                Debug.LogWarning("[Host] Rejected join request because a match is already running.");
                return;
            }

            var dto = JsonUtility.FromJson<JoinRequestDto>(m.Payload);
            string name = dto != null && !string.IsNullOrWhiteSpace(dto.DisplayName) ? dto.DisplayName : m.SenderId;

            if (!_session.Players.Any(x => x.Id == m.SenderId))
            {
                if (_session.Players.Count >= _session.MaxPlayers)
                {
                    Debug.LogWarning($"[Host] Room full ({_session.MaxPlayers}); rejected {name}.");
                    return;
                }
                _session.Players.Add(new PlayerData(m.SenderId, name));
            }

            HostSendTo(m.SenderId, new NetworkMessage(MessageType.JoinAccepted, null,
                JsonUtility.ToJson(new JoinAcceptedDto { AssignedId = m.SenderId })));
            BroadcastLobby();
        }

        private void HandleBid(NetworkMessage m)
        {
            if (_sm.Current != AppState.Bidding || !_bidding.IsOpen) return;

            var dto = JsonUtility.FromJson<BidDto>(m.Payload);
            var player = FindPlayer(m.SenderId);
            int amount = dto != null ? dto.Amount : 0;
            if (_bidding.PlaceBid(player, amount))
            {
                SendBiddingState(player);
                BroadcastBiddingStatus();
            }
        }

        private void HostBroadcast(NetworkMessage m)
        {
            _host?.Send(m);
            _web?.Send(m);
        }

        private void HostSendTo(string id, NetworkMessage m)
        {
            _host?.SendTo(id, m);
            _web?.SendTo(id, m);
        }

        private void BroadcastLobby()
        {
            var dto = new LobbyStateDto
            {
                PlayerIds = _session.Players.Select(p => p.Id).ToArray(),
                PlayerNames = _session.Players.Select(p => p.DisplayName).ToArray(),
                MatchStarting = false
            };
            _host?.Send(new NetworkMessage(MessageType.LobbyState, null, JsonUtility.ToJson(dto)));
            BroadcastWebLobby();
        }

        private void BroadcastWebLobby()
        {
            if (_web == null) return;

            foreach (var target in _session.Players)
            {
                if (target == null || string.IsNullOrEmpty(target.Id) || !target.Id.StartsWith("W", StringComparison.Ordinal))
                    continue;

                var dto = BuildWebLobby(target.Id);
                _web.SendTo(target.Id, new NetworkMessage(MessageType.WebLobby, null, JsonUtility.ToJson(dto)));
            }
        }

        private WebLobbyDto BuildWebLobby(string targetId)
        {
            string hostId = !string.IsNullOrEmpty(_webHostPlayerId) ? _webHostPlayerId : HostPlayerId;
            var host = _session.Players.FirstOrDefault(p => p.Id == hostId) ?? _session.Players.FirstOrDefault();
            return new WebLobbyDto
            {
                players = _session.Players.Select(p => new WebPlayerDto
                {
                    id = p.Id,
                    name = p.DisplayName,
                    color = SafeColor(p.Color, p.Id == hostId ? "#FFD23F" : "#FF5DA2"),
                    isHost = p.Id == hostId,
                    you = p.Id == targetId,
                    avatar = p.AvatarIndex
                }).ToArray(),
                code = _session.RoomCode,
                hostName = host != null ? host.DisplayName : "Host",
                premium = _session.IsPremiumHost
            };
        }

        private static string GenerateRoomCode()
        {
            const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ";
            var rng = new System.Random();
            char[] code = new char[4];
            for (int i = 0; i < code.Length; i++)
                code[i] = chars[rng.Next(chars.Length)];
            return new string(code);
        }

        private static string NormalizeRoomCode(string code)
        {
            if (string.IsNullOrEmpty(code)) return "";
            var chars = code.ToUpperInvariant().Where(char.IsLetterOrDigit).Take(4).ToArray();
            return new string(chars);
        }

        private static string SafePlayerName(string value, string fallback)
        {
            string trimmed = string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
            if (string.IsNullOrWhiteSpace(trimmed)) trimmed = "Player";
            return trimmed.Length <= 16 ? trimmed : trimmed.Substring(0, 16);
        }

        private static string SafeColor(string value, string fallback)
        {
            if (string.IsNullOrWhiteSpace(value)) return string.IsNullOrWhiteSpace(fallback) ? "#FF5DA2" : fallback;
            string c = value.Trim();
            if (c.Length == 7 && c[0] == '#' && c.Skip(1).All(Uri.IsHexDigit)) return c;
            return string.IsNullOrWhiteSpace(fallback) ? "#FF5DA2" : fallback;
        }

        private static IEnumerable<string> MapWebGameKeys(string[] keys)
        {
            if (keys == null) yield break;
            foreach (string raw in keys)
            {
                switch ((raw ?? "").Trim().ToLowerInvariant())
                {
                    case "golf":
                        yield return "mini_golf";
                        break;
                    case "sumo":
                        yield return "coin_rush";
                        break;
                    case "bomb":
                        yield return "reaction";
                        break;
                }
            }
        }

        // ---------------- Match flow ----------------

        private void StartMatch()
        {
            StartMatch(null);
        }

        private void StartMatch(IEnumerable<string> selectedMiniGames)
        {
            _session.SelectedMiniGames.Clear();
            if (selectedMiniGames != null)
            {
                foreach (var id in selectedMiniGames)
                    if (!string.IsNullOrWhiteSpace(id))
                        _session.SelectedMiniGames.Add(id);
            }

            if (_session.SelectedMiniGames.Count == 0)
            {
                for (int i = 0; i < _totalRounds; i++)
                    _session.SelectedMiniGames.Add(MiniGameCatalog.Ids[i % MiniGameCatalog.Ids.Length]);
            }

            _totalRounds = Mathf.Max(1, _session.SelectedMiniGames.Count);
            _session.ResetForNewSession();

            _match = new MatchDirector(_session);
            _match.RoundFinished += OnRoundFinished;
            _match.StartMatch(_totalRounds);

            _results = null;
            _bidState = null;
            _advantageNotice = "";
            _hostBidAmount = 0;
            _controllerBidAmount = 0;
            _broadcastTimer = 0f;
            _botTapTimer = 0f;

            _sm.Set(AppState.MiniGame);
            BroadcastMiniGameState(MessageType.MiniGameStart);
        }

        private void OnRoundFinished()
        {
            if (_match == null) return;

            _results = BuildRoundResults(_match.LastResult);
            HostBroadcast(new NetworkMessage(MessageType.Results, null, JsonUtility.ToJson(_results)));

            if (_match.IsComplete)
            {
                _results = BuildFinalResults();
                HostBroadcast(new NetworkMessage(MessageType.Results, null, JsonUtility.ToJson(_results)));
                _sm.Set(AppState.Results);
                _statusMessage = "Match complete.";
                return;
            }

            OpenBidding();
        }

        private void OpenBidding()
        {
            _bidding.OpenWindow();
            _biddingTimer = BiddingDuration;
            _hostBidAmount = 0;
            _controllerBidAmount = 0;
            _advantageNotice = "Secret bidding is open for the next round.";
            _sm.Set(AppState.Bidding);
            BroadcastBiddingStatus();
        }

        private void ResolveBiddingAndContinue()
        {
            if (_match == null || _sm.Current != AppState.Bidding) return;

            var bids = _bidding.CloseWindow();
            var advantage = new Dictionary<string, int>();

            int highest = 0;
            int topCount = 0;
            string winnerId = null;

            foreach (var bid in bids)
            {
                if (bid.Value > highest)
                {
                    highest = bid.Value;
                    topCount = highest > 0 ? 1 : 0;
                    winnerId = bid.Key;
                }
                else if (bid.Value == highest && highest > 0)
                {
                    topCount++;
                }
            }

            if (highest > 0 && topCount == 1 && winnerId != null)
            {
                var winner = FindPlayer(winnerId);
                if (winner != null)
                {
                    winner.Coins = Mathf.Max(0, winner.Coins - highest);
                    advantage[winner.Id] = BidAdvantageScore;
                    _advantageNotice = winner.DisplayName + " won a hidden advantage for the next round.";
                }
            }
            else if (highest > 0)
            {
                _advantageNotice = "The highest bid tied, so no advantage was awarded.";
            }
            else
            {
                _advantageNotice = "No advantage was purchased.";
            }

            BroadcastBiddingStatus();

            _match.ContinueWithAdvantage(advantage);
            _broadcastTimer = 0f;
            _botTapTimer = 0f;
            _sm.Set(AppState.MiniGame);
            BroadcastMiniGameState(MessageType.MiniGameStart);
        }

        private ResultsDto BuildRoundResults(MiniGameResult result)
        {
            string[] ids = _session.Players.Select(p => p.Id).ToArray();
            int round = _match != null ? Mathf.Clamp(_match.Round, 1, _match.TotalRounds) : 1;

            return new ResultsDto
            {
                MiniGameId = result != null ? result.MiniGameId : "",
                PlayerIds = ids,
                PlayerNames = _session.Players.Select(p => p.DisplayName).ToArray(),
                Placements = ids.Select(id => result != null && result.Placements.TryGetValue(id, out int pl) ? pl : 0).ToArray(),
                CoinsCollected = ids.Select(id =>
                {
                    int place = result != null && result.Placements.TryGetValue(id, out int pl) ? pl : 0;
                    int collected = result != null && result.CoinsCollected.TryGetValue(id, out int c) ? c : 0;
                    return collected + MatchDirector.PlacementPayout(place);
                }).ToArray(),
                Final = false,
                Round = round,
                TotalRounds = _match != null ? _match.TotalRounds : _totalRounds,
                Wins = _session.Players.Select(p => p.Wins).ToArray(),
                TotalCoins = _session.Players.Select(p => p.TotalCoinsEarned).ToArray()
            };
        }

        private ResultsDto BuildFinalResults()
        {
            var ordered = _session.Players
                .OrderByDescending(p => p.Wins)
                .ThenByDescending(p => p.TotalCoinsEarned)
                .ThenBy(p => p.DisplayName)
                .ToList();

            var placeById = new Dictionary<string, int>();
            for (int i = 0; i < ordered.Count; i++)
                placeById[ordered[i].Id] = i + 1;

            string[] ids = _session.Players.Select(p => p.Id).ToArray();
            return new ResultsDto
            {
                MiniGameId = "match_final",
                PlayerIds = ids,
                PlayerNames = _session.Players.Select(p => p.DisplayName).ToArray(),
                Placements = ids.Select(id => placeById.TryGetValue(id, out int pl) ? pl : 0).ToArray(),
                CoinsCollected = ids.Select(_ => 0).ToArray(),
                Final = true,
                Round = _match != null ? _match.TotalRounds : _totalRounds,
                TotalRounds = _match != null ? _match.TotalRounds : _totalRounds,
                Wins = _session.Players.Select(p => p.Wins).ToArray(),
                TotalCoins = _session.Players.Select(p => p.TotalCoinsEarned).ToArray()
            };
        }

        private MiniGameStateDto BuildMiniGameState()
        {
            var current = _match?.Current;
            string[] ids = _session.Players.Select(p => p.Id).ToArray();

            return new MiniGameStateDto
            {
                MiniGameId = current != null ? current.Id : "",
                GameName = current != null ? current.DisplayName : "",
                Prompt = current != null ? current.Prompt : "",
                Round = _match != null ? Mathf.Min(_match.Round + 1, _match.TotalRounds) : 1,
                TotalRounds = _match != null ? _match.TotalRounds : _totalRounds,
                PlayerIds = ids,
                PlayerNames = _session.Players.Select(p => p.DisplayName).ToArray(),
                Scores = ids.Select(id => current != null && current.Scores.TryGetValue(id, out int s) ? s : 0).ToArray(),
                TimeLeft = current != null ? current.TimeLeft : 0f,
                Running = current != null && current.Running
            };
        }

        private void BroadcastMiniGameState(MessageType type)
        {
            var dto = BuildMiniGameState();
            HostBroadcast(new NetworkMessage(type, null, JsonUtility.ToJson(dto)));
        }

        private void BroadcastBiddingStatus()
        {
            foreach (var p in _session.Players)
                SendBiddingState(p);
        }

        private void SendBiddingState(PlayerData p)
        {
            if (p == null) return;
            var dto = new BiddingStateDto
            {
                Open = _bidding.IsOpen,
                TimeLeft = Mathf.Max(0f, _biddingTimer),
                YourCoins = p.Coins,
                HasSubmitted = _bidding.HasBid(p.Id)
            };

            if (p.Id == HostPlayerId)
                _bidState = dto;
            else
                HostSendTo(p.Id, new NetworkMessage(MessageType.BiddingState, null, JsonUtility.ToJson(dto)));
        }

        private bool EveryoneHasBid()
        {
            return _session.Players.Count > 0 && _session.Players.All(p => _bidding.HasBid(p.Id));
        }

        private void SubmitHostBid()
        {
            var host = FindPlayer(HostPlayerId);
            if (host == null) return;
            _hostBidAmount = Mathf.Clamp(_hostBidAmount, 0, host.Coins);
            if (_bidding.PlaceBid(host, _hostBidAmount))
            {
                _statusMessage = "Host bid submitted.";
                BroadcastBiddingStatus();
            }
        }

        // ---------------- Controller (Unity app) ----------------

        private void StartClient(string ip)
        {
            ShutdownServices();
            _role = DeviceRole.Controller;
            _client = new TcpClientService();
            _client.Connected += OnClientConnected;
            _client.ConnectFailed += () =>
            {
                _statusMessage = "Could not reach host.";
                _role = DeviceRole.Undecided;
                _sm.Set(AppState.Onboarding);
            };
            _client.Disconnected += () => { _statusMessage = "Disconnected from host."; };
            _client.MessageReceived += OnClientMessage;
            _statusMessage = $"Connecting to {ip}:{Port}...";
            _client.Connect(ip, Port);
        }

        private void OnClientConnected()
        {
            _client.Send(new NetworkMessage(MessageType.JoinRequest, null,
                JsonUtility.ToJson(new JoinRequestDto { DisplayName = _myName })));
            _statusMessage = "Connected. Waiting for host...";
            _sm.Set(AppState.Lobby);
        }

        private void OnClientMessage(NetworkMessage m)
        {
            switch (m.Type)
            {
                case MessageType.JoinAccepted:
                {
                    var ja = JsonUtility.FromJson<JoinAcceptedDto>(m.Payload);
                    if (ja != null) _myId = ja.AssignedId;
                    break;
                }
                case MessageType.LobbyState:
                    _lobby = JsonUtility.FromJson<LobbyStateDto>(m.Payload);
                    if (_sm.Current == AppState.Onboarding) _sm.Set(AppState.Lobby);
                    break;
                case MessageType.MiniGameStart:
                    _results = null;
                    _bidState = null;
                    _mgState = JsonUtility.FromJson<MiniGameStateDto>(m.Payload);
                    _sm.Set(AppState.MiniGame);
                    break;
                case MessageType.MiniGameState:
                    _mgState = JsonUtility.FromJson<MiniGameStateDto>(m.Payload);
                    if (_sm.Current != AppState.MiniGame) _sm.Set(AppState.MiniGame);
                    break;
                case MessageType.BiddingState:
                    _bidState = JsonUtility.FromJson<BiddingStateDto>(m.Payload);
                    _sm.Set(AppState.Bidding);
                    break;
                case MessageType.Results:
                    _results = JsonUtility.FromJson<ResultsDto>(m.Payload);
                    _sm.Set(AppState.Results);
                    break;
            }
        }

        private void SubmitControllerBid()
        {
            if (_bidState == null || _bidState.HasSubmitted) return;
            _controllerBidAmount = Mathf.Clamp(_controllerBidAmount, 0, _bidState.YourCoins);
            _client?.Send(new NetworkMessage(MessageType.Bid, null,
                JsonUtility.ToJson(new BidDto { Amount = _controllerBidAmount })));
            _bidState.HasSubmitted = true;
            _statusMessage = "Bid submitted.";
        }

        private int MyScoreFromState()
        {
            if (_mgState?.PlayerIds == null || _mgState.Scores == null) return 0;
            for (int i = 0; i < _mgState.PlayerIds.Length; i++)
                if (_mgState.PlayerIds[i] == _myId && i < _mgState.Scores.Length)
                    return _mgState.Scores[i];
            return 0;
        }

        // ---------------- Lifecycle ----------------

        private void Update()
        {
            if (_role != DeviceRole.Host) return;

            if (_sm.Current == AppState.MiniGame && _match?.Current != null)
            {
                float dt = Time.deltaTime;
                _match.Tick(dt);
                if (_sm.Current != AppState.MiniGame) return;

                _broadcastTimer -= dt;
                if (_broadcastTimer <= 0f)
                {
                    _broadcastTimer = BroadcastInterval;
                    BroadcastMiniGameState(MessageType.MiniGameState);
                }

                DriveBotInput(dt);
            }
            else if (_sm.Current == AppState.Bidding && _bidding.IsOpen)
            {
                float dt = Time.deltaTime;
                _biddingTimer -= dt;
                MaybeBotBid();

                _broadcastTimer -= dt;
                if (_broadcastTimer <= 0f)
                {
                    _broadcastTimer = 0.25f;
                    BroadcastBiddingStatus();
                }

                if (_biddingTimer <= 0f || EveryoneHasBid())
                    ResolveBiddingAndContinue();
            }
        }

        private void DriveBotInput(float dt)
        {
            if (!_hasBot || _bot == null || _match?.Current == null || !_match.Current.Running) return;

            if (_match.Current.Id == "reaction" && !_match.Current.Prompt.StartsWith("GO", StringComparison.Ordinal))
                return;

            _botTapTimer -= dt;
            if (_botTapTimer <= 0f)
            {
                _botTapTimer = BotTapInterval;
                _bot.Send(new NetworkMessage(MessageType.ControllerInput, null,
                    JsonUtility.ToJson(new InputDto { Action = "tap" })));
            }
        }

        private void MaybeBotBid()
        {
            if (!_hasBot || _biddingTimer > BiddingDuration - 1f) return;

            var bot = _session.Players.FirstOrDefault(p => p.DisplayName == "Bot");
            if (bot == null || _bidding.HasBid(bot.Id)) return;

            int bid = Mathf.Min(bot.Coins, 20);
            _bidding.PlaceBid(bot, bid);
            BroadcastBiddingStatus();
        }

        private void QuitToRoleSelect()
        {
            ShutdownServices();
            _match = null;
            _lobby = null;
            _mgState = null;
            _bidState = null;
            _results = null;
            _session.Players.Clear();
            _session.RoomCode = "";
            _role = DeviceRole.Undecided;
            _myId = null;
            _webHostPlayerId = null;
            _statusMessage = "";
            _advantageNotice = "";
            _sm.Set(AppState.Onboarding);
        }

        private void ShutdownServices()
        {
            _host?.Shutdown();
            _web?.Shutdown();
            _client?.Shutdown();
            _bot?.Shutdown();
            _host = null;
            _web = null;
            _client = null;
            _bot = null;
        }

        private void OnDestroy()
        {
            ShutdownServices();
        }

        private PlayerData FindPlayer(string id)
        {
            return _session.Players.FirstOrDefault(p => p.Id == id);
        }

        private static string GetLocalIPv4()
        {
            try
            {
                foreach (var ip in System.Net.Dns.GetHostEntry(System.Net.Dns.GetHostName()).AddressList)
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && !System.Net.IPAddress.IsLoopback(ip))
                        return ip.ToString();
            }
            catch { }
            return "127.0.0.1";
        }

        private static Rect GuiSafeArea()
        {
            Rect safe = Screen.safeArea;
            return new Rect(safe.x, Screen.height - safe.yMax, safe.width, safe.height);
        }

        private static GUISkin EnsureRuntimeGuiSkin()
        {
            var skin = GUI.skin;
            if (skin == null)
            {
                return null;
            }

            skin.label ??= new GUIStyle();
            skin.button ??= new GUIStyle();
            skin.textField ??= new GUIStyle();
            skin.toggle ??= new GUIStyle();
            skin.box ??= new GUIStyle();
            return skin;
        }

        private GUILayoutOption UiHeight(float safeHeightPercent)
        {
            return GUILayout.Height(_uiRect.height * safeHeightPercent);
        }

        private GUILayoutOption UiWidth(float safeWidthPercent)
        {
            return GUILayout.Width(_uiRect.width * safeWidthPercent);
        }

        private void UiSpace(float safeHeightPercent)
        {
            GUILayout.Space(_uiRect.height * safeHeightPercent);
        }

        private void EnsureTikiSkin(int baseFont)
        {
            if (_woodTexture == null)
            {
                _backgroundTexture = MakeMiniArcadeBackgroundTexture();
                _glowTexture = MakeRadialGlowTexture(new Color(0.85f, 0.45f, 1f, 0.48f));
                _woodTexture = MakeRoundedRectTexture(new Color(0.18f, 0.03f, 0.40f, 0.88f), new Color(0.11f, 0.02f, 0.25f, 0.92f), 18);
                _bambooTexture = MakeRoundedRectTexture(new Color(1f, 0.89f, 0.48f), new Color(1f, 0.76f, 0.10f), 20);
                _hotTexture = MakeRoundedRectTexture(new Color(1f, 0.55f, 0.10f), new Color(1f, 0.22f, 0.03f), 20);
                _panelTexture = MakeRoundedRectTexture(new Color(1f, 1f, 1f, 0.13f), new Color(1f, 1f, 1f, 0.08f), 22);
                _secondaryTexture = MakeRoundedRectTexture(new Color(1f, 1f, 1f, 0.16f), new Color(1f, 1f, 1f, 0.10f), 16);
                _fieldTexture = MakeRoundedRectTexture(new Color(1f, 1f, 1f, 0.14f), new Color(1f, 1f, 1f, 0.09f), 16);
                _pillTexture = MakeRoundedRectTexture(new Color(1f, 0.82f, 0.25f, 0.22f), new Color(1f, 0.82f, 0.25f, 0.12f), 14);
                _avatarYellowTexture = MakeRoundedRectTexture(new Color(1f, 0.89f, 0.48f), new Color(1f, 0.70f, 0f), 32);
                _avatarPinkTexture = MakeRoundedRectTexture(new Color(1f, 0.36f, 0.64f), new Color(0.64f, 0.18f, 0.93f), 32);
                _avatarGreenTexture = MakeRoundedRectTexture(new Color(0.71f, 1f, 0.29f), new Color(0.26f, 0.75f, 0.18f), 32);
                _pixelTexture = MakeSolidTexture(Color.white);
            }

            if (_arcadeFont == null)
            {
                _arcadeFont = GUI.skin.font;
            }

            _tikiLabelStyle = new GUIStyle(GUI.skin.label)
            {
                fontSize = baseFont,
                fontStyle = FontStyle.Bold,
                wordWrap = true,
                padding = new RectOffset(4, 4, 3, 3)
            };
            _tikiLabelStyle.normal.textColor = Color.white;
            if (_arcadeFont != null) _tikiLabelStyle.font = _arcadeFont;

            _tikiHeaderStyle = new GUIStyle(_tikiLabelStyle)
            {
                fontSize = Mathf.RoundToInt(baseFont * 1.9f),
                alignment = TextAnchor.MiddleCenter,
                padding = new RectOffset(8, 8, 8, 8)
            };
            _tikiHeaderStyle.normal.textColor = new Color(1f, 0.82f, 0.25f);

            _miniMutedStyle = new GUIStyle(_tikiLabelStyle)
            {
                fontSize = Mathf.Max(12, Mathf.RoundToInt(baseFont * 0.82f)),
                fontStyle = FontStyle.Bold,
                alignment = TextAnchor.MiddleLeft
            };
            _miniMutedStyle.normal.textColor = new Color(1f, 1f, 1f, 0.72f);

            _miniCenterStyle = new GUIStyle(_tikiLabelStyle)
            {
                alignment = TextAnchor.MiddleCenter
            };

            _miniRoomCodeStyle = new GUIStyle(_tikiHeaderStyle)
            {
                fontSize = Mathf.RoundToInt(baseFont * 2.5f)
            };

            _tikiButtonStyle = new GUIStyle(GUI.skin.button)
            {
                fontSize = Mathf.RoundToInt(baseFont * 1.05f),
                fontStyle = FontStyle.Bold,
                wordWrap = true,
                alignment = TextAnchor.MiddleCenter,
                padding = new RectOffset(14, 14, 10, 10),
                margin = new RectOffset(4, 4, 5, 6),
                border = new RectOffset(20, 20, 20, 20)
            };
            _tikiButtonStyle.normal.background = _bambooTexture;
            _tikiButtonStyle.hover.background = _hotTexture;
            _tikiButtonStyle.active.background = _hotTexture;
            _tikiButtonStyle.normal.textColor = new Color(0.23f, 0.05f, 0.45f);
            _tikiButtonStyle.hover.textColor = new Color(0.23f, 0.05f, 0.45f);
            _tikiButtonStyle.active.textColor = Color.white;
            if (_arcadeFont != null) _tikiButtonStyle.font = _arcadeFont;

            _miniSecondaryButtonStyle = new GUIStyle(_tikiButtonStyle)
            {
                border = new RectOffset(16, 16, 16, 16)
            };
            _miniSecondaryButtonStyle.normal.background = _secondaryTexture;
            _miniSecondaryButtonStyle.hover.background = _fieldTexture;
            _miniSecondaryButtonStyle.active.background = _hotTexture;
            _miniSecondaryButtonStyle.normal.textColor = Color.white;
            _miniSecondaryButtonStyle.hover.textColor = Color.white;
            _miniSecondaryButtonStyle.active.textColor = Color.white;

            _miniDangerButtonStyle = new GUIStyle(_miniSecondaryButtonStyle);
            _miniDangerButtonStyle.normal.textColor = new Color(1f, 0.82f, 0.25f);

            _tikiShootButtonStyle = new GUIStyle(_tikiButtonStyle)
            {
                fontSize = Mathf.RoundToInt(baseFont * 1.38f)
            };
            _tikiShootButtonStyle.normal.background = _hotTexture;
            _tikiShootButtonStyle.normal.textColor = Color.white;
            _tikiShootButtonStyle.hover.textColor = Color.white;

            _tikiFieldStyle = new GUIStyle(GUI.skin.textField)
            {
                fontSize = baseFont,
                fontStyle = FontStyle.Bold,
                padding = new RectOffset(14, 14, 10, 10),
                border = new RectOffset(16, 16, 16, 16)
            };
            _tikiFieldStyle.normal.background = _fieldTexture;
            _tikiFieldStyle.normal.textColor = Color.white;
            if (_arcadeFont != null) _tikiFieldStyle.font = _arcadeFont;

            _tikiToggleStyle = new GUIStyle(GUI.skin.toggle)
            {
                fontSize = baseFont,
                fontStyle = FontStyle.Bold
            };
            _tikiToggleStyle.normal.textColor = new Color(1f, 1f, 1f, 0.82f);
            _tikiToggleStyle.onNormal.textColor = new Color(1f, 0.82f, 0.25f);
            if (_arcadeFont != null) _tikiToggleStyle.font = _arcadeFont;

            _tikiPanelStyle = new GUIStyle(GUI.skin.box)
            {
                padding = new RectOffset(18, 18, 18, 18),
                border = new RectOffset(22, 22, 22, 22)
            };
            _tikiPanelStyle.normal.background = _panelTexture;

            _miniCardStyle = new GUIStyle(GUI.skin.box)
            {
                padding = new RectOffset(14, 14, 12, 12),
                margin = new RectOffset(0, 0, 6, 8),
                border = new RectOffset(22, 22, 22, 22)
            };
            _miniCardStyle.normal.background = _panelTexture;

            _miniPillStyle = new GUIStyle(_miniCenterStyle)
            {
                fontSize = Mathf.Max(11, Mathf.RoundToInt(baseFont * 0.78f)),
                padding = new RectOffset(10, 10, 6, 6),
                margin = new RectOffset(4, 4, 3, 3),
                border = new RectOffset(14, 14, 14, 14)
            };
            _miniPillStyle.normal.background = _pillTexture;
            _miniPillStyle.normal.textColor = new Color(1f, 0.82f, 0.25f);

            _miniAvatarStyle = new GUIStyle(_miniCenterStyle)
            {
                fontSize = Mathf.RoundToInt(baseFont * 1.3f),
                fontStyle = FontStyle.Bold,
                alignment = TextAnchor.MiddleCenter,
                padding = new RectOffset(0, 0, 0, 0),
                border = new RectOffset(28, 28, 28, 28)
            };
            _miniAvatarStyle.normal.background = _avatarYellowTexture;
            _miniAvatarStyle.normal.textColor = new Color(0.23f, 0.05f, 0.45f);
        }

        private static Texture2D MakeMiniArcadeBackgroundTexture()
        {
            var tex = new Texture2D(96, 96, TextureFormat.RGBA32, false);
            tex.wrapMode = TextureWrapMode.Clamp;
            var top = new Color(0.64f, 0.21f, 0.93f);
            var mid = new Color(0.43f, 0.16f, 0.85f);
            var bottom = new Color(0.23f, 0.05f, 0.45f);
            for (int y = 0; y < 96; y++)
            for (int x = 0; x < 96; x++)
            {
                float v = y / 95f;
                Color c = v < 0.45f ? Color.Lerp(top, mid, v / 0.45f) : Color.Lerp(mid, bottom, (v - 0.45f) / 0.55f);
                float dx = (x / 95f) - 0.5f;
                float dy = (y / 95f) + 0.12f;
                float glow = Mathf.Clamp01(1f - Mathf.Sqrt(dx * dx * 1.8f + dy * dy * 1.2f) / 0.78f);
                c = Color.Lerp(c, new Color(0.85f, 0.45f, 1f), glow * 0.28f);
                tex.SetPixel(x, y, c);
            }
            tex.Apply();
            return tex;
        }

        private static Texture2D MakeRadialGlowTexture(Color glow)
        {
            const int size = 128;
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            tex.wrapMode = TextureWrapMode.Clamp;
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float dx = (x + 0.5f) / size - 0.5f;
                float dy = (y + 0.5f) / size - 0.5f;
                float a = Mathf.Clamp01(1f - Mathf.Sqrt(dx * dx + dy * dy) * 2f);
                a *= a;
                var c = glow;
                c.a *= a;
                tex.SetPixel(x, y, c);
            }
            tex.Apply();
            return tex;
        }

        private static Texture2D MakeRoundedRectTexture(Color top, Color bottom, int radius)
        {
            const int size = 96;
            radius = Mathf.Clamp(radius, 0, size / 2);
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
            tex.wrapMode = TextureWrapMode.Clamp;

            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float cx = Mathf.Clamp(x, radius, size - radius - 1);
                float cy = Mathf.Clamp(y, radius, size - radius - 1);
                float dist = Vector2.Distance(new Vector2(x, y), new Vector2(cx, cy));
                float alpha = dist <= radius ? 1f : 0f;
                Color c = Color.Lerp(bottom, top, y / (float)(size - 1));
                c.a *= alpha;
                tex.SetPixel(x, y, c);
            }

            tex.Apply();
            return tex;
        }

        private static Texture2D MakeSolidTexture(Color color)
        {
            var tex = new Texture2D(1, 1, TextureFormat.RGBA32, false);
            tex.SetPixel(0, 0, color);
            tex.Apply();
            return tex;
        }

        private Rect BuildMiniArcadePanelRect(Rect safe)
        {
            float side = Mathf.Max(14f, safe.width * 0.035f);
            float top = Mathf.Max(12f, safe.height * 0.025f);
            float bottom = Mathf.Max(14f, safe.height * 0.035f);
            bool landscape = safe.width > safe.height * 1.15f;
            bool gameplayHost = _sm.Current == AppState.MiniGame && _role == DeviceRole.Host;
            float availableWidth = Mathf.Max(1f, safe.width - side * 2f);

            if (gameplayHost && landscape)
            {
                float width = Mathf.Min(availableWidth, Mathf.Clamp(safe.width * 0.30f, 360f, 520f));
                return new Rect(safe.x + safe.width - width - side, safe.y + top, width, safe.height - top - bottom);
            }

            float targetWidth = landscape ? Mathf.Min(availableWidth, Mathf.Min(safe.width * 0.46f, 520f)) : availableWidth;
            targetWidth = Mathf.Max(Mathf.Min(340f, availableWidth), targetWidth);
            float height = safe.height - top - bottom;
            return new Rect(safe.x + (safe.width - targetWidth) * 0.5f, safe.y + top, targetWidth, height);
        }

        private void DrawMiniArcadeBackground(Rect safe)
        {
            GUI.DrawTexture(new Rect(0f, 0f, Screen.width, Screen.height), _backgroundTexture, ScaleMode.StretchToFill);

            float glowSize = Mathf.Min(safe.width, safe.height) * 0.55f;
            GUI.DrawTexture(
                new Rect(safe.center.x - glowSize * 0.5f, safe.y + safe.height * 0.02f, glowSize, glowSize),
                _glowTexture,
                ScaleMode.StretchToFill);

            DrawConfettiBlock(new Rect(safe.x + safe.width * 0.08f, safe.y + safe.height * 0.17f, 20f, 20f), new Color(1f, 0.82f, 0.25f));
            DrawConfettiBlock(new Rect(safe.x + safe.width * 0.87f, safe.y + safe.height * 0.13f, 16f, 16f), new Color(0.22f, 0.88f, 1f));
            DrawConfettiBlock(new Rect(safe.x + safe.width * 0.11f, safe.y + safe.height * 0.58f, 18f, 18f), new Color(1f, 0.36f, 0.64f));
            DrawConfettiBlock(new Rect(safe.x + safe.width * 0.84f, safe.y + safe.height * 0.72f, 22f, 22f), new Color(0.71f, 1f, 0.29f));
            DrawConfettiBlock(new Rect(safe.x + safe.width * 0.18f, safe.y + safe.height * 0.82f, 14f, 14f), new Color(1f, 0.55f, 0.10f));
        }

        private void DrawConfettiBlock(Rect rect, Color color)
        {
            Color old = GUI.color;
            GUI.color = color;
            GUI.DrawTexture(rect, _pixelTexture);
            GUI.color = old;
        }

        private void DrawMiniArcadeLogo()
        {
            GUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.Box("MA", _miniAvatarStyle, GUILayout.Width(_uiRect.height * 0.065f), GUILayout.Height(_uiRect.height * 0.065f));
            GUILayout.FlexibleSpace();
            GUILayout.EndHorizontal();
            GUILayout.Label("MINI ARCADE", _tikiHeaderStyle);
            GUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.Label("FREE 2 PLAYERS  /  3 GAMES", _miniPillStyle, GUILayout.Width(_uiRect.width * 0.64f));
            GUILayout.FlexibleSpace();
            GUILayout.EndHorizontal();
            UiSpace(0.012f);
        }

        // ---------------- IMGUI runtime UI ----------------

        private void OnGUI()
        {
            Rect safe = GuiSafeArea();
            int baseFont = Mathf.Clamp(Mathf.RoundToInt(safe.height * 0.023f), 13, 30);
            var skin = EnsureRuntimeGuiSkin();
            if (skin == null) return;
            skin.label.fontSize = baseFont;
            skin.button.fontSize = baseFont;
            skin.textField.fontSize = baseFont;
            skin.toggle.fontSize = baseFont;
            EnsureTikiSkin(baseFont);
            skin.label = _tikiLabelStyle;
            skin.button = _tikiButtonStyle;
            skin.textField = _tikiFieldStyle;
            skin.toggle = _tikiToggleStyle;

            DrawMiniArcadeBackground(safe);
            _uiRect = BuildMiniArcadePanelRect(safe);

            GUILayout.BeginArea(_uiRect);
            GUILayout.BeginVertical(_tikiPanelStyle);
            DrawMiniArcadeLogo();

            switch (_sm.Current)
            {
                case AppState.Lobby:
                    if (_role == DeviceRole.Host) DrawLobbyHost(); else DrawLobbyController();
                    break;
                case AppState.MiniGame:
                    if (_role == DeviceRole.Host) DrawMiniGameHost(); else DrawMiniGameController();
                    break;
                case AppState.Bidding:
                    if (_role == DeviceRole.Host) DrawBiddingHost(); else DrawBiddingController();
                    break;
                case AppState.Results:
                    if (_role == DeviceRole.Host) DrawResultsHost(); else DrawResultsController();
                    break;
                default:
                    DrawRoleSelect();
                    break;
            }

            if (!string.IsNullOrEmpty(_statusMessage))
            {
                GUILayout.FlexibleSpace();
                GUILayout.Label(_statusMessage, _miniMutedStyle);
            }

            GUILayout.EndVertical();
            GUILayout.EndArea();
        }

        private static string InitialFor(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return "G";
            foreach (char c in value.Trim())
                if (char.IsLetterOrDigit(c))
                    return char.ToUpperInvariant(c).ToString();
            return "G";
        }

        private string DisplayRoomCode()
        {
            string code = string.IsNullOrWhiteSpace(_session.RoomCode) ? "----" : _session.RoomCode;
            return string.Join(" ", code.ToCharArray());
        }

        private void DrawPlayerRow(string name, string meta, bool host, int index)
        {
            Texture2D oldBackground = _miniAvatarStyle.normal.background;
            _miniAvatarStyle.normal.background = index % 3 == 0 ? _avatarYellowTexture : (index % 3 == 1 ? _avatarPinkTexture : _avatarGreenTexture);

            GUILayout.BeginHorizontal(_miniCardStyle);
            GUILayout.Box(InitialFor(name), _miniAvatarStyle, GUILayout.Width(_uiRect.height * 0.06f), GUILayout.Height(_uiRect.height * 0.06f));
            GUILayout.BeginVertical();
            GUILayout.Label(name, _tikiLabelStyle);
            GUILayout.Label(host ? "HOST" : meta, host ? _miniPillStyle : _miniMutedStyle);
            GUILayout.EndVertical();
            GUILayout.EndHorizontal();

            _miniAvatarStyle.normal.background = oldBackground;
        }

        private void DrawScoreRows(MiniGameStateDto state)
        {
            for (int i = 0; i < state.PlayerIds.Length; i++)
            {
                int score = i < state.Scores.Length ? state.Scores[i] : 0;
                string name = i < state.PlayerNames.Length ? state.PlayerNames[i] : state.PlayerIds[i];
                string bar = new string('#', Mathf.Min(Mathf.Max(score, 0), 18));
                GUILayout.BeginVertical(_miniCardStyle);
                GUILayout.Label(name, _tikiLabelStyle);
                GUILayout.Label($"{score}  {bar}", _miniMutedStyle);
                GUILayout.EndVertical();
            }
        }

        private void DrawRoleSelect()
        {
            GUILayout.BeginHorizontal();
            GUILayout.Box(InitialFor(_myName), _miniAvatarStyle, GUILayout.Width(_uiRect.height * 0.055f), GUILayout.Height(_uiRect.height * 0.055f));
            GUILayout.BeginVertical();
            GUILayout.Label("Guest", _tikiLabelStyle);
            GUILayout.Label("Phones are controllers. Mirror the host to the TV.", _miniMutedStyle);
            GUILayout.EndVertical();
            GUILayout.Label("EN", _miniPillStyle, GUILayout.Width(_uiRect.width * 0.16f));
            GUILayout.EndHorizontal();
            UiSpace(0.018f);

            GUILayout.Label("PLAYER NAME", _miniMutedStyle);
            GUILayout.BeginHorizontal();
            _myName = GUILayout.TextField(_myName ?? "Player", GUILayout.Height(_uiRect.height * 0.058f));
            GUILayout.EndHorizontal();
            UiSpace(0.018f);

            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.Label("HOST", _miniMutedStyle);
            GUILayout.Label("Host a Game", _tikiLabelStyle);
            GUILayout.Label("Play on the TV. Everyone joins from their phones.", _miniMutedStyle);
            if (GUILayout.Button("HOST A GAME", UiHeight(0.075f))) StartHost(false);
            if (GUILayout.Button("HOST + BOT TEST", _miniSecondaryButtonStyle, UiHeight(0.055f))) StartHost(true);
            GUILayout.EndVertical();

            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.Label("JOIN", _miniMutedStyle);
            GUILayout.Label("Join a Game", _tikiLabelStyle);
            GUILayout.Label("Unity-app controller address", _miniMutedStyle);
            GUILayout.BeginHorizontal();
            _joinIp = GUILayout.TextField(_joinIp ?? "127.0.0.1", GUILayout.Height(_uiRect.height * 0.055f));
            GUILayout.EndHorizontal();
            if (GUILayout.Button("JOIN", _miniSecondaryButtonStyle, UiHeight(0.058f))) StartClient(_joinIp);
            GUILayout.EndVertical();

            UiSpace(0.014f);
            GUILayout.Label("Same Wi-Fi required. Browser controllers use the URL shown after hosting.", _miniMutedStyle);
        }

        private void DrawLobbyHost()
        {
            GUILayout.Label("Game Lobby", _miniCenterStyle);

            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.Label("ROOM CODE", _miniCenterStyle);
            GUILayout.Label(DisplayRoomCode(), _miniRoomCodeStyle);
            GUILayout.Label("PHONE BROWSER", _miniMutedStyle);
            GUILayout.Label(_webUrl, _tikiLabelStyle);
            GUILayout.Label($"Local test on host: http://localhost:{WebPort}", _miniMutedStyle);
            GUILayout.EndVertical();

            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.BeginHorizontal();
            GUILayout.Label($"Players  {_session.Players.Count}/{_session.MaxPlayers}", _tikiLabelStyle);
            GUILayout.FlexibleSpace();
            GUILayout.Label(_session.IsPremiumHost ? "PREMIUM" : "FREE", _miniPillStyle, GUILayout.Width(_uiRect.width * 0.25f));
            GUILayout.EndHorizontal();
            for (int i = 0; i < _session.Players.Count; i++)
                DrawPlayerRow(_session.Players[i].DisplayName, "Connected", _session.Players[i].Id == HostPlayerId, i);
            if (_session.Players.Count < _session.MaxPlayers)
                GUILayout.Label(_session.IsPremiumHost ? "Waiting for more players..." : "Free rooms support 2 players.", _miniMutedStyle);
            GUILayout.EndVertical();

            _session.IsPremiumHost = GUILayout.Toggle(_session.IsPremiumHost, "Unlock 4+ players with Premium");

            GUILayout.BeginHorizontal();
            GUILayout.Label("Rounds", _miniMutedStyle, UiWidth(0.20f));
            if (GUILayout.Button("-", _miniSecondaryButtonStyle, UiWidth(0.14f))) _totalRounds = Mathf.Max(1, _totalRounds - 1);
            GUILayout.Label(_totalRounds.ToString(), _miniCenterStyle, UiWidth(0.12f));
            if (GUILayout.Button("+", _miniSecondaryButtonStyle, UiWidth(0.14f))) _totalRounds = Mathf.Min(9, _totalRounds + 1);
            GUILayout.EndHorizontal();

            UiSpace(0.012f);
            GUI.enabled = _session.Players.Count >= 1;
            if (GUILayout.Button("PICK MINI-GAMES", UiHeight(0.075f))) StartMatch();
            GUI.enabled = true;

            UiSpace(0.01f);
            if (GUILayout.Button("LEAVE LOBBY", _miniSecondaryButtonStyle, UiHeight(0.052f))) QuitToRoleSelect();
        }

        private void DrawLobbyController()
        {
            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.Box(InitialFor(_myName), _miniAvatarStyle, GUILayout.Width(_uiRect.height * 0.085f), GUILayout.Height(_uiRect.height * 0.085f));
            GUILayout.Label("You're in!", _tikiHeaderStyle);
            GUILayout.Label("Hosted by Guest  /  Room " + DisplayRoomCode().Replace(" ", ""), _miniCenterStyle);
            GUILayout.EndVertical();

            if (_lobby?.PlayerNames != null)
            {
                GUILayout.BeginVertical(_miniCardStyle);
                GUILayout.Label("Players", _tikiLabelStyle);
                for (int i = 0; i < _lobby.PlayerNames.Length; i++)
                    DrawPlayerRow(_lobby.PlayerNames[i], i == 0 ? "HOST" : "Connected", i == 0, i);
                GUILayout.EndVertical();
            }
            UiSpace(0.012f);
            GUILayout.Label("Waiting for the host to start...", _miniCenterStyle);
            UiSpace(0.012f);
            if (GUILayout.Button("LEAVE", _miniSecondaryButtonStyle, UiHeight(0.052f))) QuitToRoleSelect();
        }

        private void DrawMiniGameHost()
        {
            var state = BuildMiniGameState();
            GUILayout.Label(state.GameName.ToUpperInvariant(), _miniCenterStyle);
            GUILayout.Label($"ROUND {state.Round}/{state.TotalRounds}  /  {state.TimeLeft:0.0}s", _miniPillStyle);

            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.Label(state.Prompt, _tikiLabelStyle);
            if (!string.IsNullOrEmpty(_advantageNotice))
                GUILayout.Label(_advantageNotice, _miniMutedStyle);
            GUILayout.EndVertical();
            UiSpace(0.012f);

            DrawScoreRows(state);

            GUILayout.FlexibleSpace();
            if (state.MiniGameId == "mini_golf")
            {
                DrawGolfHostControls();
                GUILayout.Label("Golf controls are private on player phones.", _miniMutedStyle);
            }
            else
            {
                if (GUILayout.Button("TAP", UiHeight(0.12f)))
                    _match?.HandleInput(HostPlayerId, "tap");
                GUILayout.Label("Other players tap from Unity controllers or web browsers.", _miniMutedStyle);
            }
        }

        private void DrawMiniGameController()
        {
            GUILayout.Label((_mgState != null ? _mgState.GameName : "Mini-game").ToUpperInvariant(), _miniCenterStyle);
            if (_mgState != null)
            {
                GUILayout.Label($"ROUND {_mgState.Round}/{_mgState.TotalRounds}  /  {_mgState.TimeLeft:0.0}s", _miniPillStyle);
                GUILayout.BeginVertical(_miniCardStyle);
                GUILayout.Label(_mgState.Prompt, _tikiLabelStyle);
                GUILayout.EndVertical();
            }
            GUILayout.Label($"Your score: {MyScoreFromState()}", _miniCenterStyle);
            GUILayout.FlexibleSpace();
            if (_mgState != null && _mgState.MiniGameId == "mini_golf")
                DrawGolfControllerControls();
            else if (GUILayout.Button("TAP", UiHeight(0.26f)))
                SendControllerAction("tap");
        }

        private void DrawGolfHostControls()
        {
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("AIM LEFT", _miniSecondaryButtonStyle, UiHeight(0.075f))) _match?.HandleInput(HostPlayerId, "aim_left");
            if (GUILayout.Button("AIM RIGHT", _miniSecondaryButtonStyle, UiHeight(0.075f))) _match?.HandleInput(HostPlayerId, "aim_right");
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("POWER -", _miniSecondaryButtonStyle, UiHeight(0.075f))) _match?.HandleInput(HostPlayerId, "power_down");
            if (GUILayout.Button("POWER +", _miniSecondaryButtonStyle, UiHeight(0.075f))) _match?.HandleInput(HostPlayerId, "power_up");
            GUILayout.EndHorizontal();
            if (GUILayout.Button("SHOOT", _tikiShootButtonStyle, UiHeight(0.12f))) _match?.HandleInput(HostPlayerId, "shoot");
        }

        private void DrawGolfControllerControls()
        {
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("AIM LEFT", _miniSecondaryButtonStyle, UiHeight(0.085f))) SendControllerAction("aim_left");
            if (GUILayout.Button("AIM RIGHT", _miniSecondaryButtonStyle, UiHeight(0.085f))) SendControllerAction("aim_right");
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("POWER -", _miniSecondaryButtonStyle, UiHeight(0.085f))) SendControllerAction("power_down");
            if (GUILayout.Button("POWER +", _miniSecondaryButtonStyle, UiHeight(0.085f))) SendControllerAction("power_up");
            GUILayout.EndHorizontal();
            if (GUILayout.Button("SHOOT", _tikiShootButtonStyle, UiHeight(0.16f))) SendControllerAction("shoot");
        }

        private void SendControllerAction(string action)
        {
            _client?.Send(new NetworkMessage(MessageType.ControllerInput, null,
                JsonUtility.ToJson(new InputDto { Action = action })));
        }

        private void DrawBiddingHost()
        {
            GUILayout.Label("ROUND RESULTS", _miniCenterStyle);
            GUILayout.BeginVertical(_miniCardStyle);
            DrawResultsTable();
            GUILayout.EndVertical();
            UiSpace(0.015f);

            GUILayout.BeginVertical(_miniCardStyle);
            GUILayout.Label("SECRET BID", _tikiLabelStyle);
            GUILayout.Label($"Next game: {_match?.CurrentGameName}", _miniMutedStyle);
            GUILayout.Label($"Time left: {Mathf.Max(0f, _biddingTimer):0.0}s", _miniPillStyle);
            GUILayout.Label($"Submitted: {_bidding.BidCount}/{_session.Players.Count}", _miniMutedStyle);
            GUILayout.Label("TV view hides all balances and bid amounts.", _miniMutedStyle);
            GUILayout.EndVertical();
            UiSpace(0.012f);

            var host = FindPlayer(HostPlayerId);
            if (host != null)
            {
                GUILayout.Label($"Host private coins: {host.Coins}", _miniCenterStyle);
                DrawBidControls(ref _hostBidAmount, host.Coins, SubmitHostBid, _bidding.HasBid(HostPlayerId));
            }

            UiSpace(0.012f);
            if (GUILayout.Button("RESOLVE BIDDING", UiHeight(0.064f))) ResolveBiddingAndContinue();
        }

        private void DrawBiddingController()
        {
            GUILayout.Label("SECRET BID", _miniCenterStyle);
            if (_results != null)
            {
                GUILayout.BeginVertical(_miniCardStyle);
                GUILayout.Label("Last round", _tikiLabelStyle);
                DrawResultsTable();
                GUILayout.EndVertical();
                UiSpace(0.012f);
            }

            if (_bidState == null)
            {
                GUILayout.Label("Waiting for private bid state...", _miniCenterStyle);
                return;
            }

            GUILayout.Label($"Time left: {_bidState.TimeLeft:0.0}s", _miniPillStyle);
            GUILayout.Label($"Your private coins: {_bidState.YourCoins}", _miniCenterStyle);
            DrawBidControls(ref _controllerBidAmount, _bidState.YourCoins, SubmitControllerBid, _bidState.HasSubmitted);
        }

        private void DrawBidControls(ref int amount, int max, Action submit, bool submitted)
        {
            amount = Mathf.Clamp(amount, 0, max);
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("-10", _miniSecondaryButtonStyle, UiWidth(0.18f))) amount = Mathf.Max(0, amount - 10);
            if (GUILayout.Button("+10", _miniSecondaryButtonStyle, UiWidth(0.18f))) amount = Mathf.Min(max, amount + 10);
            if (GUILayout.Button("ALL", _miniSecondaryButtonStyle, UiWidth(0.18f))) amount = max;
            GUILayout.EndHorizontal();
            GUILayout.Label("Bid: " + amount, _miniRoomCodeStyle);

            GUI.enabled = !submitted;
            if (GUILayout.Button(submitted ? "BID SUBMITTED" : "SUBMIT BID", UiHeight(0.067f))) submit?.Invoke();
            GUI.enabled = true;
        }

        private void DrawResultsHost()
        {
            GUILayout.Label(_results != null && _results.Final ? "FINAL RESULTS" : "RESULTS", _miniCenterStyle);
            GUILayout.BeginVertical(_miniCardStyle);
            DrawResultsTable();
            GUILayout.EndVertical();
            UiSpace(0.015f);
            if (GUILayout.Button("BACK TO LOBBY", UiHeight(0.07f)))
            {
                _match = null;
                _results = null;
                _mgState = null;
                _bidState = null;
                _sm.Set(AppState.Lobby);
                BroadcastLobby();
            }
            UiSpace(0.01f);
            if (GUILayout.Button("QUIT HOSTING", _miniSecondaryButtonStyle, UiHeight(0.052f))) QuitToRoleSelect();
        }

        private void DrawResultsController()
        {
            GUILayout.Label(_results != null && _results.Final ? "FINAL RESULTS" : "RESULTS", _miniCenterStyle);
            GUILayout.BeginVertical(_miniCardStyle);
            DrawResultsTable();
            GUILayout.EndVertical();
            UiSpace(0.012f);
            GUILayout.Label(_results != null && _results.Final
                ? "Match complete."
                : "Waiting for the next phase...", _miniCenterStyle);
        }

        private void DrawResultsTable()
        {
            if (_results?.PlayerIds == null)
            {
                GUILayout.Label("(no results)", _miniMutedStyle);
                return;
            }

            var order = Enumerable.Range(0, _results.PlayerIds.Length)
                .OrderBy(i => i < _results.Placements.Length ? _results.Placements[i] : 999)
                .ToList();

            foreach (int i in order)
            {
                string name = i < _results.PlayerNames.Length ? _results.PlayerNames[i] : _results.PlayerIds[i];
                int place = i < _results.Placements.Length ? _results.Placements[i] : 0;
                int wins = _results.Wins != null && i < _results.Wins.Length ? _results.Wins[i] : 0;
                int totalCoins = _results.TotalCoins != null && i < _results.TotalCoins.Length ? _results.TotalCoins[i] : 0;

                if (_results.Final)
                    GUILayout.Label($"#{place}   {name}   wins: {wins}   total coins: {totalCoins}", _miniMutedStyle);
                else
                {
                    int payout = i < _results.CoinsCollected.Length ? _results.CoinsCollected[i] : 0;
                    GUILayout.Label($"#{place}   {name}   +{payout} coins   wins: {wins}   total coins: {totalCoins}", _miniMutedStyle);
                }
            }
        }
    }
}
