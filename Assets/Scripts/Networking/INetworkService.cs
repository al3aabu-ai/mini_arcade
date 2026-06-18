using System;

namespace MiniArcade.Networking
{
    /// <summary>
    /// Shared messaging surface for the LAN session. Host- and controller-side
    /// concrete services (<see cref="TcpHostService"/>, <see cref="TcpClientService"/>)
    /// add their own start/connect methods. All events are raised on the Unity
    /// main thread.
    /// </summary>
    public interface INetworkService
    {
        bool IsRunning { get; }

        /// <summary>Host-only: a controller connected (arg = assigned client id).</summary>
        event Action<string> ClientConnected;

        /// <summary>Host-only: a controller dropped (arg = client id).</summary>
        event Action<string> ClientDisconnected;

        /// <summary>A message arrived. On the host, SenderId is the authoritative client id.</summary>
        event Action<NetworkMessage> MessageReceived;

        /// <summary>Host: broadcast to every controller. Controller: send to the host.</summary>
        void Send(NetworkMessage message);

        void Shutdown();
    }
}
