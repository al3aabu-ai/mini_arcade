using System;
using System.IO;
using System.Text;
using UnityEngine;

namespace MiniArcade.Networking
{
    /// <summary>
    /// Length-prefixed JSON framing for <see cref="NetworkMessage"/> over a TCP
    /// stream. Frame = [4-byte big-endian length][UTF-8 JSON].
    /// </summary>
    public static class MessageCodec
    {
        private const int MaxFrameBytes = 16 * 1024 * 1024; // sanity cap

        public static byte[] Encode(NetworkMessage message)
        {
            string json = JsonUtility.ToJson(message);
            byte[] payload = Encoding.UTF8.GetBytes(json);
            byte[] frame = new byte[4 + payload.Length];
            frame[0] = (byte)((payload.Length >> 24) & 0xFF);
            frame[1] = (byte)((payload.Length >> 16) & 0xFF);
            frame[2] = (byte)((payload.Length >> 8) & 0xFF);
            frame[3] = (byte)(payload.Length & 0xFF);
            Buffer.BlockCopy(payload, 0, frame, 4, payload.Length);
            return frame;
        }

        /// <summary>
        /// Blocking read of exactly one framed message. Returns false when the
        /// stream ends or a malformed frame is seen.
        /// </summary>
        public static bool TryRead(Stream stream, out NetworkMessage message)
        {
            message = null;

            byte[] header = new byte[4];
            if (!ReadFully(stream, header, 4))
                return false;

            int length = (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
            if (length <= 0 || length > MaxFrameBytes)
                return false;

            byte[] payload = new byte[length];
            if (!ReadFully(stream, payload, length))
                return false;

            string json = Encoding.UTF8.GetString(payload);
            message = JsonUtility.FromJson<NetworkMessage>(json);
            return message != null;
        }

        private static bool ReadFully(Stream stream, byte[] buffer, int count)
        {
            int offset = 0;
            while (offset < count)
            {
                int read = stream.Read(buffer, offset, count - offset);
                if (read <= 0)
                    return false; // stream closed
                offset += read;
            }
            return true;
        }
    }
}
