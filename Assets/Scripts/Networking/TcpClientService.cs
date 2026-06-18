using System;
using System.Net.Sockets;
using System.Threading;
using UnityEngine;
using MiniArcade.Core;

namespace MiniArcade.Networking
{
    /// <summary>
    /// Controller-side LAN service. Connects to a host over TCP on a background
    /// thread so the main thread never blocks. Events are raised on the Unity
    /// main thread via <see cref="MainThreadDispatcher"/>.
    /// </summary>
    public class TcpClientService : INetworkService
    {
        private TcpClient _tcp;
        private NetworkStream _stream;
        private Thread _recvThread;
        private volatile bool _running;
        private readonly object _writeLock = new object();

        public bool IsRunning => _running;

        // Part of the shared interface but only meaningful host-side; unused here.
#pragma warning disable 67
        public event Action<string> ClientConnected;
        public event Action<string> ClientDisconnected;
#pragma warning restore 67
        public event Action<NetworkMessage> MessageReceived;

        // Controller-side connection lifecycle.
        public event Action Connected;
        public event Action ConnectFailed;
        public event Action Disconnected;

        public void Connect(string host, int port)
        {
            if (_running) return;
            var thread = new Thread(() => ConnectWorker(host, port)) { IsBackground = true, Name = "MiniArcade-Connect" };
            thread.Start();
        }

        private void ConnectWorker(string host, int port)
        {
            try
            {
                var tcp = new TcpClient();
                tcp.Connect(host, port);
                _tcp = tcp;
                _stream = tcp.GetStream();
                _running = true;
                _recvThread = new Thread(ReceiveLoop) { IsBackground = true, Name = "MiniArcade-ClientRecv" };
                _recvThread.Start();
                MainThreadDispatcher.Enqueue(() => Connected?.Invoke());
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[Client] Connect failed: {e.Message}");
                MainThreadDispatcher.Enqueue(() => ConnectFailed?.Invoke());
            }
        }

        private void ReceiveLoop()
        {
            try
            {
                while (_running)
                {
                    if (!MessageCodec.TryRead(_stream, out NetworkMessage msg))
                        break;
                    MainThreadDispatcher.Enqueue(() => MessageReceived?.Invoke(msg));
                }
            }
            catch { }
            finally
            {
                _running = false;
                MainThreadDispatcher.Enqueue(() => Disconnected?.Invoke());
            }
        }

        public void Send(NetworkMessage message)
        {
            var stream = _stream;
            if (stream == null) return;
            byte[] frame = MessageCodec.Encode(message);
            try { lock (_writeLock) { stream.Write(frame, 0, frame.Length); } }
            catch (Exception e) { Debug.LogWarning($"[Client] Send failed: {e.Message}"); }
        }

        public void Shutdown()
        {
            _running = false;
            try { _stream?.Close(); _tcp?.Close(); } catch { }
        }
    }
}
