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
            _webRoot = Path.Combine(Application.streamingAssetsPath, "web");
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

        // The browser controller (served on GET /). Uses single quotes throughout
        // so it embeds cleanly in this verbatim C# string.
        private const string ControllerPageHtml = @"<!doctype html>
<html>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'>
<title>Mini Arcade Controller</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600;700&display=swap');
  :root{--top:12svh;--bottom:20svh;--gap:1.35svh;--pad-x:6vw;--purple:#6d28d9;--deep:#3b0d73;--pink:#ff5da2;--yellow:#ffd23f;--cyan:#38e1ff;--green:#b6ff4b;}
  html,body{margin:0;height:100%;font-family:Fredoka,system-ui,sans-serif;background:radial-gradient(135% 95% at 50% -12%,#a435ee 0%,#6d28d9 44%,#3b0d73 100%);color:white;-webkit-user-select:none;user-select:none;overflow:hidden;}
  body:before{content:'';position:fixed;top:3svh;left:50%;width:74vw;max-width:22rem;aspect-ratio:1;border-radius:50%;transform:translateX(-50%);background:radial-gradient(circle,rgba(216,112,255,.45) 0%,rgba(216,112,255,0) 70%);pointer-events:none;}
  body:after{content:'';position:fixed;inset:0;pointer-events:none;background:radial-gradient(circle at 9% 18%,#ffd23f 0 .45rem,transparent .5rem),radial-gradient(circle at 89% 14%,#38e1ff 0 .4rem,transparent .45rem),radial-gradient(circle at 87% 74%,#b6ff4b 0 .48rem,transparent .55rem),radial-gradient(circle at 12% 62%,#ff5da2 0 .42rem,transparent .48rem);}
  #app{position:relative;display:flex;flex-direction:column;min-height:100svh;box-sizing:border-box;padding:calc(env(safe-area-inset-top) + 3svh) calc(env(safe-area-inset-right) + var(--pad-x)) calc(env(safe-area-inset-bottom) + 3svh) calc(env(safe-area-inset-left) + var(--pad-x));}
  h1{font-size:clamp(1.65rem,7vw,2.45rem);margin:0 0 var(--gap);color:#ffd23f;text-align:center;font-weight:700;font-style:italic;text-shadow:.13rem .13rem 0 #d98c00,0 .45rem .8rem rgba(0,0,0,.32);}
  .muted{color:rgba(255,255,255,.72);font-size:clamp(.95rem,4vw,1.28rem);font-weight:600;}
  .stat{font-size:clamp(1rem,4.7vw,1.55rem);margin:.7svh 0;color:#fff;font-weight:700;}
  #joinView,#waitView,#bidView,#resultView{border-radius:1.4rem;background:rgba(255,255,255,.10);border:.1rem solid rgba(255,255,255,.18);padding:1.2rem;box-shadow:0 1rem 1.6rem rgba(0,0,0,.22);}
  input{font-size:clamp(1.05rem,5vw,1.6rem);padding:1.2svh 4vw;border-radius:1rem;border:.1rem solid rgba(255,255,255,.24);background:rgba(255,255,255,.12);color:#fff;width:100%;box-sizing:border-box;font-family:inherit;font-weight:700;outline:none;}
  button{font-size:clamp(1.05rem,5vw,1.65rem);padding:1.55svh 3vw;margin-top:var(--gap);border:0;border-radius:1.25rem;background:linear-gradient(180deg,#ffe27a,#ffc21a);color:#3b0d73;width:100%;min-height:8svh;font-family:inherit;font-weight:700;box-shadow:0 .45rem 0 #d99700,0 1rem 1.4rem rgba(0,0,0,.26);}
  button:active{transform:translateY(.18rem);box-shadow:0 .2rem 0 #d99700,0 .45rem .9rem rgba(0,0,0,.22);}
  button:disabled{opacity:.55;filter:saturate(.5);}
  #tap{flex:1;font-size:clamp(2.3rem,12vw,4rem);background:linear-gradient(180deg,#ff8b19,#ff3d63);color:#fff;margin-top:2svh;min-height:30svh;text-shadow:0 .16rem 0 rgba(59,13,115,.4);box-shadow:0 .55rem 0 #a41443,0 0 1.2rem rgba(255,93,162,.85);}
  #tap:active{background:linear-gradient(180deg,#ffb11c,#d91955);}
  .row{display:flex;gap:2.6vw;}
  .row button{flex:1;}
  #shoot{font-size:clamp(1.9rem,9vw,3.4rem);background:linear-gradient(180deg,#ff8b19,#ff3d63);color:white;min-height:16svh;text-shadow:0 .2rem 0 rgba(59,13,115,.45);box-shadow:0 .6rem 0 #a41443,0 0 1.2rem rgba(255,93,162,.95);}
  #gameView{display:flex;flex-direction:column;min-height:calc(100svh - var(--top));}
  #gameView .stat,#gameView #prompt{border-radius:1rem;background:rgba(255,255,255,.10);border:.1rem solid rgba(255,255,255,.16);padding:.8rem .95rem;}
  #golfControls{margin-top:auto;padding-bottom:calc(env(safe-area-inset-bottom) + 1svh);}
  .hidden{display:none!important;}
</style>
</head>
<body>
<div id='app'>
  <h1>Mini Arcade</h1>
  <div id='status' class='muted'>Connecting...</div>

  <div id='joinView' class='hidden'>
    <p>Enter your name:</p>
    <input id='name' value='Player' maxlength='16'>
    <button id='joinBtn'>Join game</button>
  </div>

  <div id='waitView' class='hidden'>
    <div class='stat'>You are in! Waiting for the host to start...</div>
    <div id='roster' class='muted'></div>
  </div>

  <div id='gameView' class='hidden'>
    <h1 id='gameTitle'>Mini-game</h1>
    <div class='stat' id='prompt'>Ready</div>
    <div class='stat'>Round <span id='round'>-</span>/<span id='rounds'>-</span></div>
    <div class='stat'>Time left: <span id='time'>-</span>s</div>
    <div class='stat'>Your score: <span id='score'>0</span></div>
    <div id='golfControls' class='hidden'>
      <div class='row'><button id='aimLeft'>Aim Left</button><button id='aimRight'>Aim Right</button></div>
      <div class='row'><button id='powerDown'>Power -</button><button id='powerUp'>Power +</button></div>
      <button id='shoot'>SHOOT</button>
    </div>
    <button id='tap'>TAP!</button>
  </div>

  <div id='bidView' class='hidden'>
    <h1>Secret Bid</h1>
    <div class='stat'>Time left: <span id='bidTime'>-</span>s</div>
    <div class='stat'>Your private coins: <span id='coins'>0</span></div>
    <div class='stat'>Bid: <span id='bidAmount'>0</span></div>
    <button id='minus'>-10</button>
    <button id='plus'>+10</button>
    <button id='all'>All</button>
    <button id='submitBid'>Submit bid</button>
  </div>

  <div id='resultView' class='hidden'>
    <h1>Results</h1>
    <div id='results' class='stat'></div>
    <div class='muted'>See the TV. Waiting for the next round...</div>
  </div>
</div>
<script>
  var ws, myId=null, bidAmount=0, bidMax=0, bidSubmitted=false;
  var $=function(id){return document.getElementById(id);};
  function show(v){['joinView','waitView','gameView','bidView','resultView'].forEach(function(x){$(x).classList.add('hidden');});$(v).classList.remove('hidden');}
  function isGame(){return !$('gameView').classList.contains('hidden');}
  function connect(){
    ws=new WebSocket('ws://'+location.host+'/');
    ws.onopen=function(){$('status').textContent='Connected';show('joinView');};
    ws.onclose=function(){$('status').textContent='Disconnected - reload to retry';};
    ws.onmessage=function(e){
      var m;try{m=JSON.parse(e.data);}catch(err){return;}
      var d=m.d||{};
      if(m.t==='joined'){myId=d.AssignedId;}
      else if(m.t==='lobby'){$('roster').textContent='In the room: '+((d.PlayerNames||[]).join(', '));if(!isGame())show('waitView');}
      else if(m.t==='game'){onGame(d);}
      else if(m.t==='bidding'){onBidding(d);}
      else if(m.t==='results'){onResults(d);}
    };
  }
  function onGame(d){
    show('gameView');
    $('gameTitle').textContent=d.GameName||'Mini-game';
    $('prompt').textContent=d.Prompt||'';
    $('round').textContent=d.Round||'-';
    $('rounds').textContent=d.TotalRounds||'-';
    $('time').textContent=(d.TimeLeft||0).toFixed(1);
    if(d.MiniGameId==='mini_golf'){
      $('golfControls').classList.remove('hidden');
      $('tap').classList.add('hidden');
    }else{
      $('golfControls').classList.add('hidden');
      $('tap').classList.remove('hidden');
    }
    var s=0,ids=d.PlayerIds||[],sc=d.Scores||[];
    for(var i=0;i<ids.length;i++){if(ids[i]===myId)s=sc[i];}
    $('score').textContent=s;
  }
  function setBid(v){
    bidAmount=Math.max(0,Math.min(bidMax,v));
    $('bidAmount').textContent=bidAmount;
  }
  function onBidding(d){
    show('bidView');
    bidMax=d.YourCoins||0;
    bidSubmitted=!!d.HasSubmitted;
    setBid(Math.min(bidAmount,bidMax));
    $('bidTime').textContent=(d.TimeLeft||0).toFixed(1);
    $('coins').textContent=bidMax;
    $('submitBid').textContent=bidSubmitted?'Bid submitted':'Submit bid';
    $('submitBid').disabled=bidSubmitted;
  }
  function onResults(d){
    show('resultView');
    var names=d.PlayerNames||[],pl=d.Placements||[],co=d.CoinsCollected||[];
    var order=names.map(function(_,i){return i;}).sort(function(a,b){return pl[a]-pl[b];});
    if(d.Final){
      var wins=d.Wins||[],tot=d.TotalCoins||[];
      $('results').innerHTML=order.map(function(i){return '#'+pl[i]+'  '+names[i]+'  wins: '+(wins[i]||0)+'  total coins: '+(tot[i]||0);}).join('<br>');
    }else{
      $('results').innerHTML=order.map(function(i){return '#'+pl[i]+'  '+names[i]+'  (+'+(co[i]||0)+' coins)';}).join('<br>');
    }
  }
  $('joinBtn').onclick=function(){var n=$('name').value||'Player';ws.send(JSON.stringify({t:'join',name:n}));show('waitView');};
  function sendInput(action,ev){if(ev){ev.preventDefault();}if(ws&&ws.readyState===1){ws.send(JSON.stringify({t:'input',action:action}));}}
  function sendTap(ev){sendInput('tap',ev);}
  $('tap').addEventListener('touchstart',sendTap,{passive:false});
  $('tap').addEventListener('mousedown',sendTap);
  $('aimLeft').onclick=function(){sendInput('aim_left');};
  $('aimRight').onclick=function(){sendInput('aim_right');};
  $('powerDown').onclick=function(){sendInput('power_down');};
  $('powerUp').onclick=function(){sendInput('power_up');};
  $('shoot').onclick=function(){sendInput('shoot');};
  $('minus').onclick=function(){setBid(bidAmount-10);};
  $('plus').onclick=function(){setBid(bidAmount+10);};
  $('all').onclick=function(){setBid(bidMax);};
  $('submitBid').onclick=function(){if(ws&&ws.readyState===1&&!bidSubmitted){ws.send(JSON.stringify({t:'bid',amount:bidAmount}));bidSubmitted=true;$('submitBid').textContent='Bid submitted';$('submitBid').disabled=true;}};
  connect();
</script>
</body>
</html>";
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
