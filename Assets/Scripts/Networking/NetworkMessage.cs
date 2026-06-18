using System;

namespace MiniArcade.Networking
{
    public enum MessageType
    {
        None = 0,
        JoinRequest,      // controller -> host (payload: JoinRequestDto)
        JoinAccepted,     // host -> controller (payload: JoinAcceptedDto)
        LobbyState,       // host -> all (payload: LobbyStateDto)
        MiniGameStart,    // host -> all (payload: MiniGameStateDto)
        MiniGameState,    // host -> all (payload: MiniGameStateDto)
        ControllerInput,  // controller -> host (payload: InputDto)
        Results,          // host -> all (payload: ResultsDto) - round or final
        BiddingState,     // host -> ONE controller, privately (payload: BiddingStateDto)
        Bid,              // controller -> host, secret blind bid (payload: BidDto)
        SecretTask,       // host -> one controller, private task (spec 4.2) - later
        CreateRoom,       // browser host phone -> Unity host (payload: CreateRoomDto)
        JoinRoom,         // browser player phone -> Unity host (payload: JoinRoomDto)
        Profile,          // browser phone -> Unity host profile update (payload: CreateRoomDto)
        StartPick,        // browser host phone -> Unity host
        PickStart,        // browser host phone -> Unity host (payload: PickStartDto)
        Leave,            // browser phone -> Unity host
        RoomCreated,      // Unity host -> browser host phone (payload: RoomCreatedDto)
        WebLobby,         // Unity host -> browser phones (payload: WebLobbyDto)
        GoPick,           // Unity host -> browser host phone
        Error             // Unity host -> browser phone (payload: ErrorDto)
    }

    /// <summary>
    /// Envelope for everything sent between controllers and host. Serialized as
    /// JSON via <c>JsonUtility</c>; <see cref="Payload"/> carries a nested JSON
    /// DTO (see Dtos.cs). A class (not struct) so JsonUtility round-trips cleanly.
    /// </summary>
    [Serializable]
    public class NetworkMessage
    {
        public MessageType Type;
        public string SenderId;
        public string Payload;

        public NetworkMessage() { }

        public NetworkMessage(MessageType type, string senderId, string payload)
        {
            Type = type;
            SenderId = senderId;
            Payload = payload;
        }
    }
}
