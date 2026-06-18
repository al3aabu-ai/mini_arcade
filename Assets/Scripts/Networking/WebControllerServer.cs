using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using UnityEngine;
using MiniArcade.Core;

namespace MiniArcade.Networking
{
    /// <summary>
    /// Lets a phone act as a controller from a plain web browser (no app install)
    /// and bridges it into the same session as the Unity-app controllers. One raw
    /// <see cref="TcpListener"/> handles both roles on a single port: a normal
    /// HTTP GET returns the controller web page; a WebSocket upgrade becomes a
    /// live controller connection (RFC 6455 handshake + framing, implemented here
    /// so we avoid HttpListener's Windows URL-ACL/admin requirements).
    ///
    /// Incoming browser JSON is translated into <see cref="NetworkMessage"/> so
    /// AppRoot handles web and app controllers identically; outgoing host messages
    /// are translated back into a small browser JSON shape. Events are raised on
    /// the Unity main thread via <see cref="MainThreadDispatcher"/>.
    /// </summary>
    public class WebControllerServer
    {
        private sealed class WsConn
        {
            public string Id;
            public TcpClient Tcp;
            public NetworkStream Stream;
            public readonly object WriteLock = new object();
        }

        private const string WsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

        private TcpListener _listener;
        private Thread _acceptThread;
        private volatile bool _running;
        private int _idCounter;
        private string _webRoot;

        private readonly object _gate = new object();
        private readonly Dictionary<string, WsConn> _conns = new Dictionary<string, WsConn>();

        public bool IsRunning => _running;

        public event Action<string> ClientConnected;
        public event Action<string> ClientDisconnected;
        public event Action<NetworkMessage> MessageReceived;

        public void StartServer(int port)
        {
            if (_running) return;
#if UNITY_EDITOR
            // In the Editor, serve the canonical source straight from the repo's
            // top-level web/ folder so edits go live with no copy step. Player
            // builds use the StreamingAssets copy WebSync mirrors at build time.
            _webRoot = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "web"));
            if (!Directory.Exists(_webRoot))
                _webRoot = Path.Combine(Application.streamingAssetsPath, "web");
#else
            _webRoot = Path.Combine(Application.streamingAssetsPath, "web");
#endif
            _listener = new TcpListener(IPAddress.Any, port);
            _listener.Start();
            _running = true;
            _acceptThread = new Thread(AcceptLoop) { IsBackground = true, Name = "MiniArcade-Web-Accept" };
            _acceptThread.Start();
            Debug.Log($"[Web] Controller server listening on port {port}.");
        }

        private void AcceptLoop()
        {
            while (_running)
            {
                TcpClient tcp;
                try { tcp = _listener.AcceptTcpClient(); }
                catch { break; }
                var t = new Thread(() => HandleConnection(tcp)) { IsBackground = true, Name = "MiniArcade-Web-Conn" };
                t.Start();
            }
        }

        private void HandleConnection(TcpClient tcp)
        {
            try
            {
                var stream = tcp.GetStream();
                string request = ReadHttpRequest(stream);
                if (request == null) { tcp.Close(); return; }

                if (request.IndexOf("upgrade: websocket", StringComparison.OrdinalIgnoreCase) >= 0)
                    HandleWebSocket(tcp, stream, request);
                else
                    ServeFile(stream, tcp, request);
            }
            catch { try { tcp.Close(); } catch { } }
        }

        // ---------------- HTTP ----------------

        private static string ReadHttpRequest(NetworkStream stream)
        {
            var sb = new StringBuilder();
            var buf = new byte[1];
            int newlineRun = 0;
            while (sb.Length < 16384) // read until blank line ends the headers
            {
                int n = stream.Read(buf, 0, 1);
                if (n <= 0) return null;
                char c = (char)buf[0];
                sb.Append(c);
                if (c == '\n') { if (++newlineRun == 2) break; }
                else if (c != '\r') newlineRun = 0;
            }
            return sb.ToString();
        }

        private void ServeFile(NetworkStream stream, TcpClient tcp, string request)
        {
            try
            {
                string rel = RequestPathToRelativeFile(request);
                if (string.IsNullOrEmpty(_webRoot) || string.IsNullOrEmpty(rel))
                {
                    WriteHttp(stream, 400, "text/plain; charset=utf-8", Encoding.UTF8.GetBytes("Bad request"));
                    return;
                }

                string full = Path.GetFullPath(Path.Combine(_webRoot, rel));
                string root = Path.GetFullPath(_webRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(full))
                {
                    WriteHttp(stream, 404, "text/plain; charset=utf-8", Encoding.UTF8.GetBytes("Not found"));
                    return;
                }

                WriteHttp(stream, 200, ContentTypeFor(full), File.ReadAllBytes(full));
            }
            catch
            {
                try { WriteHttp(stream, 500, "text/plain; charset=utf-8", Encoding.UTF8.GetBytes("Server error")); } catch { }
            }
            finally
            {
                try { tcp.Close(); } catch { }
            }
        }

        private static string RequestPathToRelativeFile(string request)
        {
            if (string.IsNullOrEmpty(request)) return null;
            string first = request.Split('\n')[0].Trim();
            string[] parts = first.Split(' ');
            if (parts.Length < 2 || parts[0] != "GET") return null;
            string path = parts[1];
            int q = path.IndexOf('?');
            if (q >= 0) path = path.Substring(0, q);
            path = Uri.UnescapeDataString(path).Replace('\\', '/').TrimStart('/');
            if (string.IsNullOrEmpty(path)) path = "index.html";
            if (path.Contains("..")) return null;
            return path;
        }

        private static string ContentTypeFor(string path)
        {
            switch (Path.GetExtension(path).ToLowerInvariant())
            {
                case ".html": return "text/html; charset=utf-8";
                case ".js": return "application/javascript; charset=utf-8";
                case ".css": return "text/css; charset=utf-8";
                case ".svg": return "image/svg+xml";
                case ".png": return "image/png";
                case ".jpg":
                case ".jpeg": return "image/jpeg";
                default: return "application/octet-stream";
            }
        }

        private static void WriteHttp(NetworkStream stream, int status, string contentType, byte[] body)
        {
            string reason = status == 200 ? "OK" : (status == 400 ? "Bad Request" : (status == 404 ? "Not Found" : "Internal Server Error"));
            string header = "HTTP/1.1 " + status + " " + reason + "\r\n" +
                            "Content-Type: " + contentType + "\r\n" +
                            "Content-Length: " + body.Length + "\r\n" +
                            "Connection: close\r\n\r\n";
            byte[] head = Encoding.ASCII.GetBytes(header);
            stream.Write(head, 0, head.Length);
            stream.Write(body, 0, body.Length);
            stream.Flush();
        }

        // ---------------- WebSocket ----------------

        private void HandleWebSocket(TcpClient tcp, NetworkStream stream, string request)
        {
            string key = ExtractHeader(request, "sec-websocket-key");
            if (string.IsNullOrEmpty(key)) { tcp.Close(); return; }

            string accept;
            using (var sha1 = SHA1.Create())
            {
                byte[] hash = sha1.ComputeHash(Encoding.ASCII.GetBytes(key + WsGuid));
                accept = Convert.ToBase64String(hash);
            }
            string resp = "HTTP/1.1 101 Switching Protocols\r\n" +
                          "Upgrade: websocket\r\n" +
                          "Connection: Upgrade\r\n" +
                          "Sec-WebSocket-Accept: " + accept + "\r\n\r\n";
            byte[] respBytes = Encoding.ASCII.GetBytes(resp);
            stream.Write(respBytes, 0, respBytes.Length);
            stream.Flush();

            string id = "W" + Interlocked.Increment(ref _idCounter);
            var conn = new WsConn { Id = id, Tcp = tcp, Stream = stream };
            lock (_gate) { _conns[id] = conn; }
            MainThreadDispatcher.Enqueue(() => ClientConnected?.Invoke(id));

            WsReceiveLoop(conn);
        }

        private void WsReceiveLoop(WsConn conn)
        {
            try
            {
                var fragment = new List<byte>();
                int fragOpcode = 0;
                while (_running)
                {
                    if (!ReadWsFrame(conn.Stream, out int opcode, out bool fin, out byte[] payload))
                        break;

                    if (opcode == 0x8) break;                 // close
                    if (opcode == 0x9) { SendControl(conn, 0xA, payload); continue; } // ping -> pong
                    if (opcode == 0xA) continue;              // pong

                    if (opcode == 0x0) { fragment.AddRange(payload); }
                    else { fragment.Clear(); fragOpcode = opcode; fragment.AddRange(payload); }

                    if (fin)
                    {
                        if (fragOpcode == 0x1) // complete text message
                            HandleWsText(conn, Encoding.UTF8.GetString(fragment.ToArray()));
                        fragment.Clear();
                    }
                }
            }
            catch { }
            finally { RemoveConn(conn); }
        }

        private void HandleWsText(WsConn conn, string text)
        {
            WebInbound inbound;
            try { inbound = JsonUtility.FromJson<WebInbound>(text); }
            catch { return; }
            if (inbound == null || string.IsNullOrEmpty(inbound.t)) return;

            NetworkMessage msg = null;
            if (inbound.t == "createRoom")
            {
                msg = new NetworkMessage(MessageType.CreateRoom, conn.Id,
                    JsonUtility.ToJson(new CreateRoomDto
                    {
                        name = inbound.name,
                        avatar = inbound.avatar,
                        color = inbound.color
                    }));
            }
            else if (inbound.t == "join")
            {
                msg = new NetworkMessage(MessageType.JoinRoom, conn.Id,
                    JsonUtility.ToJson(new JoinRoomDto
                    {
                        code = inbound.code,
                        name = inbound.name,
                        avatar = inbound.avatar,
                        color = inbound.color
                    }));
            }
            else if (inbound.t == "profile")
            {
                msg = new NetworkMessage(MessageType.Profile, conn.Id,
                    JsonUtility.ToJson(new CreateRoomDto
                    {
                        name = inbound.name,
                        avatar = inbound.avatar,
                        color = inbound.color
                    }));
            }
            else if (inbound.t == "startPick")
            {
                msg = new NetworkMessage(MessageType.StartPick, conn.Id, "{}");
            }
            else if (inbound.t == "pickStart")
            {
                msg = new NetworkMessage(MessageType.PickStart, conn.Id,
                    JsonUtility.ToJson(new PickStartDto
                    {
                        games = inbound.games,
                        mode = inbound.mode
                    }));
            }
            else if (inbound.t == "leave")
            {
                msg = new NetworkMessage(MessageType.Leave, conn.Id, "{}");
            }
            else if (inbound.t == "tap")
            {
                msg = new NetworkMessage(MessageType.ControllerInput, conn.Id,
                    JsonUtility.ToJson(new InputDto { Action = "tap" }));
            }
            else if (inbound.t == "input")
            {
                string action = string.IsNullOrWhiteSpace(inbound.action) ? "tap" : inbound.action;
                msg = new NetworkMessage(MessageType.ControllerInput, conn.Id,
                    JsonUtility.ToJson(new InputDto { Action = action }));
            }
            else if (inbound.t == "bid")
            {
                msg = new NetworkMessage(MessageType.Bid, conn.Id,
                    JsonUtility.ToJson(new BidDto { Amount = Mathf.Max(0, inbound.amount) }));
            }
            else if (inbound.t == "pickUpdate")
            {
                return;
            }
            else if (inbound.t == "legacyJoin")
            {
                string name = string.IsNullOrWhiteSpace(inbound.name) ? conn.Id : inbound.name;
                msg = new NetworkMessage(MessageType.JoinRequest, conn.Id,
                    JsonUtility.ToJson(new JoinRequestDto { DisplayName = name }));
            }

            if (msg != null)
            {
                NetworkMessage delivered = msg;
                MainThreadDispatcher.Enqueue(() => MessageReceived?.Invoke(delivered));
            }
        }

        // Decode one masked client frame. Returns false on stream end / bad frame.
        private static bool ReadWsFrame(NetworkStream stream, out int opcode, out bool fin, out byte[] payload)
        {
            opcode = 0; fin = false; payload = null;

            byte[] h = new byte[2];
            if (!ReadFully(stream, h, 2)) return false;
            fin = (h[0] & 0x80) != 0;
            opcode = h[0] & 0x0F;
            bool masked = (h[1] & 0x80) != 0;
            long len = h[1] & 0x7F;

            if (len == 126)
            {
                byte[] e = new byte[2];
                if (!ReadFully(stream, e, 2)) return false;
                len = (e[0] << 8) | e[1];
            }
            else if (len == 127)
            {
                byte[] e = new byte[8];
                if (!ReadFully(stream, e, 8)) return false;
                len = 0;
                for (int i = 0; i < 8; i++) len = (len << 8) | e[i];
            }
            if (len < 0 || len > 1024 * 1024) return false;

            byte[] mask = new byte[4];
            if (masked && !ReadFully(stream, mask, 4)) return false;

            payload = new byte[len];
            if (len > 0 && !ReadFully(stream, payload, (int)len)) return false;
            if (masked)
                for (int i = 0; i < payload.Length; i++)
                    payload[i] ^= mask[i % 4];
            return true;
        }

        public void Send(NetworkMessage message)
        {
            byte[] frame = BuildWebFrame(message);
            if (frame == null) return;
            List<WsConn> targets;
            lock (_gate) { targets = new List<WsConn>(_conns.Values); }
            foreach (var c in targets) WriteRaw(c, frame);
        }

        public void SendTo(string clientId, NetworkMessage message)
        {
            WsConn c;
            lock (_gate) { _conns.TryGetValue(clientId, out c); }
            if (c == null) return;
            byte[] frame = BuildWebFrame(message);
            if (frame != null) WriteRaw(c, frame);
        }

        // NetworkMessage -> browser frame: {"t":<type>,"d":<original payload JSON>}.
        private static byte[] BuildWebFrame(NetworkMessage message)
        {
            string t;
            switch (message.Type)
            {
                case MessageType.JoinAccepted: t = "joined"; break;
                case MessageType.RoomCreated: t = "roomCreated"; break;
                case MessageType.WebLobby: t = "lobby"; break;
                case MessageType.GoPick: t = "goPick"; break;
                case MessageType.Error: t = "error"; break;
                case MessageType.MiniGameStart:
                case MessageType.MiniGameState: t = "game"; break;
                case MessageType.BiddingState: t = "bidding"; break;
                case MessageType.Results: t = "results"; break;
                default: return null; // nothing else is relevant to the browser
            }
            string payload = string.IsNullOrEmpty(message.Payload) ? "{}" : message.Payload;
            return EncodeText("{\"t\":\"" + t + "\",\"d\":" + payload + "}");
        }

        private static byte[] EncodeText(string text)
        {
            byte[] data = Encoding.UTF8.GetBytes(text);
            byte[] header;
            if (data.Length < 126)
                header = new byte[] { 0x81, (byte)data.Length };
            else if (data.Length < 65536)
                header = new byte[] { 0x81, 126, (byte)(data.Length >> 8), (byte)(data.Length & 0xFF) };
            else
            {
                header = new byte[10];
                header[0] = 0x81; header[1] = 127;
                long l = data.Length;
                for (int i = 9; i >= 2; i--) { header[i] = (byte)(l & 0xFF); l >>= 8; }
            }
            byte[] frame = new byte[header.Length + data.Length];
            Buffer.BlockCopy(header, 0, frame, 0, header.Length);
            Buffer.BlockCopy(data, 0, frame, header.Length, data.Length);
            return frame;
        }

        private void SendControl(WsConn conn, int opcode, byte[] payload)
        {
            payload = payload ?? Array.Empty<byte>();
            if (payload.Length >= 126) return; // control frames are tiny
            byte[] frame = new byte[2 + payload.Length];
            frame[0] = (byte)(0x80 | opcode);
            frame[1] = (byte)payload.Length;
            Buffer.BlockCopy(payload, 0, frame, 2, payload.Length);
            WriteRaw(conn, frame);
        }

        private void WriteRaw(WsConn c, byte[] frame)
        {
            try { lock (c.WriteLock) { c.Stream.Write(frame, 0, frame.Length); } }
            catch { RemoveConn(c); }
        }

        private void RemoveConn(WsConn conn)
        {
            bool removed;
            lock (_gate) { removed = _conns.Remove(conn.Id); }
            try { conn.Stream?.Close(); conn.Tcp?.Close(); } catch { }
            if (removed)
                MainThreadDispatcher.Enqueue(() => ClientDisconnected?.Invoke(conn.Id));
        }

        public void Shutdown()
        {
            _running = false;
            try { _listener?.Stop(); } catch { }
            List<WsConn> all;
            lock (_gate) { all = new List<WsConn>(_conns.Values); _conns.Clear(); }
            foreach (var c in all) { try { c.Stream?.Close(); c.Tcp?.Close(); } catch { } }
        }

        private static bool ReadFully(NetworkStream stream, byte[] buffer, int count)
        {
            int offset = 0;
            while (offset < count)
            {
                int read = stream.Read(buffer, offset, count - offset);
                if (read <= 0) return false;
                offset += read;
            }
            return true;
        }

        private static string ExtractHeader(string request, string name)
        {
            foreach (var line in request.Split('\n'))
            {
                int colon = line.IndexOf(':');
                if (colon <= 0) continue;
                if (line.Substring(0, colon).Trim().Equals(name, StringComparison.OrdinalIgnoreCase))
                    return line.Substring(colon + 1).Trim();
            }
            return null;
        }

    }

    [Serializable]
    public class WebInbound
    {
        public string t;
        public string name;
        public string code;
        public string color;
        public int avatar;
        public string[] games;
        public string mode;
        public string action;
        public int amount;
    }
}
