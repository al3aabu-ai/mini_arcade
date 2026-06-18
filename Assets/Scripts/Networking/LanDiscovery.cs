using System;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace MiniArcade.Networking
{
    /// <summary>
    /// Minimal UDP broadcast beacon so controllers can auto-discover a host on
    /// the same Wi-Fi network (spec section 3). The host periodically broadcasts
    /// its address; controllers listen for it.
    ///
    /// This is scaffolding: it sends/receives a single beacon and does not yet
    /// handle retries, multiple network interfaces, or threading. Wired into the
    /// lobby flow in a later milestone.
    /// </summary>
    public class LanDiscovery : IDisposable
    {
        public const int DiscoveryPort = 47777;
        private const string Magic = "MINIARCADE_HOST";

        private UdpClient _socket;

        /// <summary>Host side: broadcast a beacon advertising the given game port.</summary>
        public void BroadcastBeacon(int gamePort)
        {
            using (var client = new UdpClient())
            {
                client.EnableBroadcast = true;
                byte[] data = Encoding.UTF8.GetBytes($"{Magic}:{gamePort}");
                var target = new IPEndPoint(IPAddress.Broadcast, DiscoveryPort);
                client.Send(data, data.Length, target);
            }
        }

        /// <summary>
        /// Controller side: block briefly waiting for a host beacon.
        /// Returns the host IP + game port, or null if none heard before timeout.
        /// </summary>
        public (string host, int port)? Listen(int timeoutMs)
        {
            try
            {
                _socket = new UdpClient(DiscoveryPort) { EnableBroadcast = true };
                _socket.Client.ReceiveTimeout = timeoutMs;

                var remote = new IPEndPoint(IPAddress.Any, 0);
                byte[] data = _socket.Receive(ref remote);
                string text = Encoding.UTF8.GetString(data);

                if (text.StartsWith(Magic + ":") &&
                    int.TryParse(text.Substring(Magic.Length + 1), out int port))
                {
                    return (remote.Address.ToString(), port);
                }
            }
            catch (SocketException)
            {
                // Timed out or socket error: no host found on this attempt.
            }
            finally
            {
                _socket?.Dispose();
                _socket = null;
            }

            return null;
        }

        public void Dispose()
        {
            _socket?.Dispose();
            _socket = null;
        }
    }
}
