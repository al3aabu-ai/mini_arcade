using System;

namespace MiniArcade.Networking
{
    // Payload DTOs carried (as JSON) inside NetworkMessage.Payload. JsonUtility
    // serializes public fields and supports arrays as fields of a [Serializable]
    // class, so the collections below are plain arrays.

    [Serializable]
    public class JoinRequestDto
    {
        public string DisplayName;
    }

    [Serializable]
    public class JoinAcceptedDto
    {
        public string AssignedId;
    }

    [Serializable]
    public class LobbyStateDto
    {
        public string[] PlayerIds;
        public string[] PlayerNames;
        public bool MatchStarting;
    }

    [Serializable]
    public class InputDto
    {
        public string Action; // e.g. "tap"
    }

    [Serializable]
    public class MiniGameStateDto
    {
        public string MiniGameId;
        public string GameName;
        public string Prompt;
        public int Round;        // 1-based for display
        public int TotalRounds;
        public string[] PlayerIds;
        public string[] PlayerNames;
        public int[] Scores;     // higher = better, indexed alongside PlayerIds
        public float TimeLeft;
        public bool Running;
    }

    [Serializable]
    public class BiddingStateDto
    {
        public bool Open;
        public float TimeLeft;
        public int YourCoins;    // private: only sent to the owning controller
        public bool HasSubmitted;
    }

    [Serializable]
    public class BidDto
    {
        public int Amount;
    }

    [Serializable]
    public class ResultsDto
    {
        public string MiniGameId;
        public string[] PlayerIds;
        public string[] PlayerNames;
        public int[] Placements;     // 1 = winner of the round
        public int[] CoinsCollected; // this round (collected + placement payout)
        public bool Final;           // true = end-of-match standings
        public int Round;            // 1-based
        public int TotalRounds;
        public int[] Wins;           // total wins so far (for final tie-break)
        public int[] TotalCoins;     // total coins so far (for final tie-break)
    }

    [Serializable]
    public class WebPlayerDto
    {
        public string id;
        public string name;
        public string color;
        public bool isHost;
        public bool you;
        public int avatar;
    }

    [Serializable]
    public class WebLobbyDto
    {
        public WebPlayerDto[] players;
        public string code;
        public string hostName;
        public bool premium;
    }

    [Serializable]
    public class CreateRoomDto
    {
        public string name;
        public string color;
        public int avatar;
        public string code;
    }

    [Serializable]
    public class JoinRoomDto
    {
        public string name;
        public string color;
        public int avatar;
        public string code;
    }

    [Serializable]
    public class PickStartDto
    {
        public string[] games;
        public string mode;
    }

    [Serializable]
    public class RoomCreatedDto
    {
        public string code;
    }

    [Serializable]
    public class ErrorDto
    {
        public string msg;
    }
}
