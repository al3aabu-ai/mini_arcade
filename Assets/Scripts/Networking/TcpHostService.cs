using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using UnityEngine;
using MiniArcade.Core;

namespace MiniArcade.Networking
{
    /// <summary>
    /// Host-side LAN service. Listens for controller connections over TCP and
    /// exchanges length-prefixed JSON messages. Every public event is raised on
    /// the Unity main thread via <see cref="MainThreadDispatcher"/>.
    /// </summary>
    public class TcpHostService : INetworkService
    {
        private sealed class Conn
        {
            public string Id;
            public TcpClient Tcp;
            public NetworkStream Stream;
            public Thread Thread;
            public readonly object WriteLock = new object();
        }

        private TcpListener _listener;
        private Thread _acceptThread;
        private volatile bool _running;
        private int _idCounter;

        private readonly object _gate = new object();
        private readonly Dictionary<string, Conn> _clients = new Dictionary<string, Conn>();

        public bool IsRunning => _running;

        public event Action<string> ClientConnected;
        public event Action<string> ClientDisconnected;
        public event Action<NetworkMessage> MessageReceived;

        public IReadOnlyCollection<string> ConnectedClients
        {
            get { lock (_gate) { return new List<string>(_clients.Keys); } }
        }

        public void StartHost(int port)
        {
            if (_running) return;
            _listener = new TcpListener(IPAddress.Any, port);
            _listener.Start();
            _running = true;
            _acceptThread = new Thread(AcceptLoop) { IsBackground = true, Name = "MiniArcade-Accept" };
            _acceptThread.Start();
            Debug.Log($"[Host] Listening on port {port}.");
        }

        private void AcceptLoop()
        {
            while (_running)
            {
                TcpClient tcp;
                try { tcp = _listener.AcceptTcpClient(); }
                catch { break; } // listener stopped

                string id = "P" + Interlocked.Increment(ref _idCounter);
                var conn = new Conn { Id = id, Tcp = tcp, Stream = tcp.GetStream() };
                conn.Thread = new Thread(() => ReceiveLoop(conn)) { IsBackground = true, Name = "MiniArcade-Recv-" + id };

                lock (_gate) { _clients[id] = conn; }
                conn.Thread.Start();

                MainThreadDispatcher.Enqueue(() => ClientConnected?.Invoke(id));
            }
        }

        private void ReceiveLoop(Conn conn)
        {
            try
            {
                while (_running)
                {
                    if (!MessageCodec.TryRead(conn.Stream, out NetworkMessage msg))
                        break;
                    msg.SenderId = conn.Id; // authoritative: trust the connection, not the payload
                    MainThreadDispatcher.Enqueue(() => MessageReceived?.Invoke(msg));
                }
            }
            catch { /* connection error */ }
            finally
            {
                RemoveClient(conn);
            }
        }

        private void RemoveClient(Conn conn)
        {
            bool removed;
            lock (_gate) { removed = _clients.Remove(conn.Id); }
            try { conn.Stream?.Close(); conn.Tcp?.Close(); } catch { }
            if (removed)
                MainThreadDispatcher.Enqueue(() => ClientDisconnected?.Invoke(conn.Id));
        }

        /// <summary>Broadcast to every connected controller.</summary>
        public void Send(NetworkMessage message)
        {
            byte[] frame = MessageCodec.Encode(message);
            List<Conn> targets;
            lock (_gate) { targets = new List<Conn>(_clients.Values); }
            foreach (var c in targets)
                WriteFrame(c, frame);
        }

        /// <summary>Send to a single controller (e.g. a private secret task).</summary>
        public void SendTo(string clientId, NetworkMessage message)
        {
            Conn c;
            lock (_gate) { _clients.TryGetValue(clientId, out c); }
            if (c != null)
                WriteFrame(c, MessageCodec.Encode(message));
        }

        private void WriteFrame(Conn c, byte[] frame)
        {
            try
            {
                lock (c.WriteLock) { c.Stream.Write(frame, 0, frame.Length); }
            }
            catch { RemoveClient(c); }
        }

        public void Shutdown()
        {
            _running = false;
            try { _listener?.Stop(); } catch { }

            List<Conn> all;
            lock (_gate) { all = new List<Conn>(_clients.Values); _clients.Clear(); }
            foreach (var c in all)
            {
                try { c.Stream?.Close(); c.Tcp?.Close(); } catch { }
            }
            Debug.Log("[Host] Shut down.");
        }
    }
}
