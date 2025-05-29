#!/usr/bin/env python3

import re
import socket
import struct
import os
from scapy.all import wrpcap, IP, TCP, Raw
import hpack
import json

# Try to import hpack for proper HTTP/2 header decompression

# Global variables to track HTTP/2 stream data
http2_streams = {}
hpack_decoder = None


def create_directories():
    """Create output directories."""
    os.makedirs("capture/audio", exist_ok=True)
    os.makedirs("capture/events", exist_ok=True)


def parse_traffic_file(filename):
    """Parse the network traffic file and extract hex data segments with direction."""

    data_segments = []

    with open(filename, "r") as f:
        content = f.read()

    # Find all "Data is sent:" and "Data is received:" lines followed by hex data
    sent_pattern = r"Data is sent:\s*([0-9a-fA-F]+)"
    received_pattern = r"Data is received:\s*([0-9a-fA-F]+)"

    # Find all matches with their positions to maintain order
    all_matches = []

    for match in re.finditer(sent_pattern, content):
        hex_data = match.group(1)
        all_matches.append((match.start(), "sent", hex_data))

    for match in re.finditer(received_pattern, content):
        hex_data = match.group(1)
        all_matches.append((match.start(), "received", hex_data))

    # Sort by position to maintain chronological order
    all_matches.sort(key=lambda x: x[0])

    for _, direction, hex_data in all_matches:
        # Convert hex string to bytes
        try:
            data_bytes = bytes.fromhex(hex_data)
            data_segments.append((direction, data_bytes))
            print(f"Found {direction} data segment: {len(data_bytes)} bytes")
        except ValueError as e:
            print(f"Error parsing hex data: {e}")
            continue

    return data_segments


def parse_http2_frames(data):
    """Parse HTTP/2 frames from binary data and return list of individual frames."""
    frames = []
    offset = 0

    # Check for HTTP/2 connection preface
    http2_preface = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
    if data.startswith(http2_preface):
        frames.append(("HTTP/2 Connection Preface", data[: len(http2_preface)], 0))
        offset = len(http2_preface)
        print("Found HTTP/2 connection preface")

    # Parse HTTP/2 frames
    while offset < len(data):
        if offset + 9 > len(data):  # Need at least 9 bytes for frame header
            # Remaining data is incomplete frame or padding
            if len(data) - offset > 0:
                frames.append(("Incomplete/Padding", data[offset:], 0))
            break

        # HTTP/2 frame header: Length(3) + Type(1) + Flags(1) + Stream ID(4)
        frame_length = struct.unpack(">I", b"\x00" + data[offset : offset + 3])[0]
        frame_type = data[offset + 3]
        frame_flags = data[offset + 4]
        stream_id = (
            struct.unpack(">I", data[offset + 5 : offset + 9])[0] & 0x7FFFFFFF
        )  # Clear reserved bit

        frame_header_size = 9
        total_frame_size = frame_header_size + frame_length

        if offset + total_frame_size > len(data):
            # Frame extends beyond available data
            frames.append(("Incomplete Frame", data[offset:], stream_id))
            break

        frame_data = data[offset : offset + total_frame_size]
        frame_payload = data[offset + frame_header_size : offset + total_frame_size]

        # Identify frame type
        frame_types = {
            0x0: "DATA",
            0x1: "HEADERS",
            0x2: "PRIORITY",
            0x3: "RST_STREAM",
            0x4: "SETTINGS",
            0x5: "PUSH_PROMISE",
            0x6: "PING",
            0x7: "GOAWAY",
            0x8: "WINDOW_UPDATE",
            0x9: "CONTINUATION",
        }

        frame_type_name = frame_types.get(frame_type, f"UNKNOWN({frame_type})")
        frame_info = f"HTTP/2 {frame_type_name} Stream:{stream_id} Len:{frame_length} Flags:0x{frame_flags:02x}"

        # Collect stream data for multipart parsing
        collect_stream_data(stream_id, frame_type, frame_payload, frame_flags)

        frames.append((frame_info, frame_data, stream_id))
        print(f"  {frame_info}")

        offset += total_frame_size

    return frames


def collect_stream_data(stream_id, frame_type, payload, flags):
    """Collect HTTP/2 stream data for multipart parsing."""
    global http2_streams, hpack_decoder

    if stream_id == 0:  # Skip control stream
        return

    if stream_id not in http2_streams:
        http2_streams[stream_id] = {
            "headers": {},
            "data": b"",
            "path": "",
            "method": "",
            "complete": False,
        }

    stream = http2_streams[stream_id]

    if frame_type == 1:  # HEADERS frame
        # Try to decode HPACK headers
        try:
            if hpack_decoder is None:
                hpack_decoder = hpack.Decoder()

            # Skip frame header padding/priority if present
            header_payload = payload
            if len(payload) > 0:
                # Check for padding
                if flags & 0x08:  # PADDED flag
                    pad_length = payload[0]
                    header_payload = (
                        payload[1:-pad_length] if pad_length > 0 else payload[1:]
                    )

                # Check for priority (5 bytes)
                if flags & 0x20:  # PRIORITY flag
                    header_payload = header_payload[5:]

            headers = hpack_decoder.decode(header_payload)
            for name, value in headers:
                name_str = name.decode("utf-8") if isinstance(name, bytes) else name
                value_str = value.decode("utf-8") if isinstance(value, bytes) else value
                stream["headers"][name_str] = value_str

                if name_str == ":method":
                    stream["method"] = value_str
                elif name_str == ":path":
                    stream["path"] = value_str

            print(
                f"    Stream {stream_id} headers: {stream['method']} {stream['path']}"
            )

        except Exception as e:
            print(f"    HPACK decode error for stream {stream_id}: {e}")
            # Fallback to looking for text patterns
            try:
                headers_text = payload.decode("utf-8", errors="ignore")
                if "POST" in headers_text:
                    stream["method"] = "POST"
                if "/api/1.0/voice/audio" in headers_text:
                    stream["path"] = "/api/1.0/voice/audio"
                elif "/api/1.0/voice/events" in headers_text:
                    stream["path"] = "/api/1.0/voice/events"
            except UnicodeDecodeError:
                pass

    elif frame_type == 0:  # DATA frame
        # Handle padding in DATA frames
        data_payload = payload
        if flags & 0x08:  # PADDED flag
            if len(payload) > 0:
                pad_length = payload[0]
                data_payload = payload[1:-pad_length] if pad_length > 0 else payload[1:]

        stream["data"] += data_payload

        # Check if stream is complete (END_STREAM flag)
        if flags & 0x01:  # END_STREAM flag
            stream["complete"] = True
            parse_multipart_data(stream_id, stream)


def parse_multipart_data(stream_id, stream):
    """Parse multipart form data from HTTP/2 stream."""
    data = stream["data"]
    path = stream["path"]

    if not data:
        print(f"  No data in stream {stream_id}")
        return

    print(f"\nParsing multipart data from stream {stream_id} ({path})")
    print(f"  Data length: {len(data)} bytes")

    # Look for multipart boundary (multiple patterns)
    boundary_patterns = [
        rb"----[-\w]+",  # Standard boundary format
        rb"--\w{30,}",  # Long alphanumeric boundary
        rb"--[0-9]+",  # Numeric boundary
    ]

    boundary = None
    for pattern in boundary_patterns:
        boundary_match = re.search(pattern, data)
        if boundary_match:
            boundary = boundary_match.group(0)
            break

    if not boundary:
        # Try to find any "--" followed by content-disposition
        content_disp_matches = list(
            re.finditer(rb"Content-Disposition:", data, re.IGNORECASE)
        )
        if content_disp_matches:
            print(f"  Found {len(content_disp_matches)} Content-Disposition headers")
            # Look backwards from first Content-Disposition to find boundary
            first_match = content_disp_matches[0]
            data_before = data[: first_match.start()]
            # Find the last "--" sequence before Content-Disposition
            boundary_candidates = re.findall(rb"--[^\r\n]+", data_before)
            if boundary_candidates:
                boundary = boundary_candidates[-1]
                print(
                    f"  Inferred boundary: {boundary.decode('utf-8', errors='ignore')}"
                )

    if not boundary:
        print(f"  No multipart boundary found in stream {stream_id}")
        # Try to save as single file if it looks like known content
        if b"Content-Disposition:" in data:
            print(
                "  Found Content-Disposition, attempting to parse without boundary..."
            )
            parse_single_multipart_part(stream_id, stream, data)
        return

    print(f"  Found boundary: {boundary.decode('utf-8', errors='ignore')}")

    # Split data by boundary
    parts = data.split(boundary)

    part_count = 0
    for i, part in enumerate(parts):
        if len(part) < 10:  # Skip empty or very small parts
            continue

        part_count += 1
        print(f"  Processing part {part_count} ({len(part)} bytes)")

        # Parse this multipart part
        parse_single_multipart_part(stream_id, stream, part, part_count)

    print(f"  Processed {part_count} multipart parts from stream {stream_id}")


def create_wav_header(data_size, sample_rate=16000, channels=1, bits_per_sample=16):
    """Create a WAV file header for the given audio parameters."""

    # Calculate derived values
    byte_rate = sample_rate * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8

    # WAV file header structure
    header = struct.pack(
        "<4sI4s",  # RIFF header
        b"RIFF",  # ChunkID
        36 + data_size,  # ChunkSize (36 + data size)
        b"WAVE",
    )  # Format

    header += struct.pack(
        "<4sIHHIIHH",  # fmt subchunk
        b"fmt ",  # Subchunk1ID
        16,  # Subchunk1Size (16 for PCM)
        1,  # AudioFormat (1 for PCM)
        channels,  # NumChannels
        sample_rate,  # SampleRate
        byte_rate,  # ByteRate
        block_align,  # BlockAlign
        bits_per_sample,
    )  # BitsPerSample

    header += struct.pack(
        "<4sI", b"data", data_size  # data subchunk  # Subchunk2ID
    )  # Subchunk2Size

    return header


def parse_single_multipart_part(stream_id, stream, part_data, part_num=1):
    """Parse a single multipart part."""
    path = stream["path"]

    # Parse Content-Disposition header
    disposition_match = re.search(
        rb'Content-Disposition:\s*form-data;\s*name="([^"]+)"', part_data, re.IGNORECASE
    )
    if not disposition_match:
        print(f"    No Content-Disposition found in part {part_num}")
        return

    field_name = disposition_match.group(1).decode("utf-8")
    print(f"    Field name: {field_name}")

    # Parse Content-Type header
    content_type_match = re.search(
        rb"Content-Type:\s*([^\r\n]+)", part_data, re.IGNORECASE
    )
    content_type = "application/octet-stream"
    file_ext = "bin"

    if content_type_match:
        content_type = content_type_match.group(1).decode("utf-8").strip()
        print(f"    Content-Type: {content_type}")

    # Determine file extension based on content type and field name
    if "json" in content_type.lower():
        file_ext = "json"
    elif (
        "audio/wav" in content_type.lower()
        or "wav" in content_type.lower()
        or field_name == "audio"
    ):
        file_ext = "wav"
    elif "text" in content_type.lower():
        file_ext = "txt"
    elif "octet-stream" in content_type.lower():
        # Try to guess from field name
        if "audio" in field_name.lower():
            file_ext = "wav"
        elif "config" in field_name.lower() or "json" in field_name.lower():
            file_ext = "json"

    # Find start of actual data (after headers)
    data_start = part_data.find(b"\r\n\r\n")
    if data_start == -1:
        # Try just \n\n
        data_start = part_data.find(b"\n\n")
        if data_start != -1:
            data_start += 2
    else:
        data_start += 4

    if data_start == -1:
        print(f"    Could not find data start in part {part_num}")
        return

    file_data = part_data[data_start:]

    # Clean up trailing boundary markers and whitespace
    file_data = file_data.rstrip(b"\r\n-")

    # Additional cleanup for common trailing patterns
    while (
        file_data.endswith(b"--")
        or file_data.endswith(b"\r\n")
        or file_data.endswith(b"\n")
    ):
        if file_data.endswith(b"--"):
            file_data = file_data[:-2]
        elif file_data.endswith(b"\r\n"):
            file_data = file_data[:-2]
        elif file_data.endswith(b"\n"):
            file_data = file_data[:-1]

    if len(file_data) == 0:
        print(f"    No file data found in part {part_num}")
        return

    # Determine output directory based on stream path
    if "/api/1.0/voice/audio" in path:
        output_dir = "capture/audio"
    elif "/api/1.0/voice/events" in path:
        output_dir = "capture/events"
    else:
        output_dir = f"capture/stream_{stream_id}"
        os.makedirs(output_dir, exist_ok=True)

    # Generate filename
    if len(http2_streams[stream_id]["data"].split(b"Content-Disposition:")) >= 2:
        # Multiple parts, add part number
        filename = f"{part_num}.{field_name}.{file_ext}"
    else:
        filename = f"{field_name}.{file_ext}"

    filepath = os.path.join(output_dir, filename)

    if file_ext == "wav":
        print("    Processing raw audio data to create WAV file...")

        # Default values from the user's specification
        sample_rate = 16000
        channels = 1
        bits_per_sample = 16
        print(
            f"    Using defaults: {sample_rate}Hz, {channels}ch, {bits_per_sample}bit"
        )

        # Create WAV header
        wav_header = create_wav_header(
            len(file_data), sample_rate, channels, bits_per_sample
        )

        # Combine header and data
        file_data = wav_header + file_data
    if file_ext == "json":
        # Pretty-print JSON data if possible
        try:

            json_data = json.loads(file_data.decode("utf-8"))
            file_data = json.dumps(json_data, indent=2).encode("utf-8")
            print("    Parsed JSON data successfully")
        except json.JSONDecodeError as e:
            print(f"    JSON decode error: {e}")

    # Save file
    try:
        with open(filepath, "wb") as f:
            f.write(file_data)
        print(f"    Saved: {filepath} ({len(file_data)} bytes)")

        # If it's JSON, also print it for debugging
        if file_ext == "json":
            try:
                json_text = file_data.decode("utf-8")
                print(f"    JSON content: {json_text[:200]}...")
            except UnicodeDecodeError:
                print(f"    JSON content (binary): {file_data[:100]}...")

    except Exception as e:
        print(f"    Error saving {filepath}: {e}")


def create_http2_pcap(data_segments, output_filename):
    """Create a pcap file from bidirectional HTTP/2 data segments."""

    packets = []

    # Network parameters for HTTP/2 (unencrypted)
    client_ip = "192.168.1.100"  # Client IP
    server_ip = socket.gethostbyname("voice-service.voice.roku.com")  # Server IP
    client_port = 54321  # Client source port
    server_port = 80  # HTTP port (since it's unencrypted HTTP/2)

    print(f"Server IP resolved to: {server_ip}")
    print("Creating bidirectional HTTP/2 traffic:")
    print(f"  Client: {client_ip}:{client_port}")
    print(f"  Server: {server_ip}:{server_port}")

    # Sequence numbers for each direction
    client_seq = 1000
    server_seq = 2000

    # First, create TCP SYN, SYN-ACK, ACK handshake for proper connection establishment
    # SYN packet (client to server)
    syn_packet = IP(src=client_ip, dst=server_ip) / TCP(
        sport=client_port, dport=server_port, flags="S", seq=client_seq, window=65535
    )
    packets.append(syn_packet)

    # SYN-ACK packet (server to client)
    synack_packet = IP(src=server_ip, dst=client_ip) / TCP(
        sport=server_port,
        dport=client_port,
        flags="SA",
        seq=server_seq,
        ack=client_seq + 1,
        window=65535,
    )
    packets.append(synack_packet)

    # ACK packet (client to server)
    ack_packet = IP(src=client_ip, dst=server_ip) / TCP(
        sport=client_port,
        dport=server_port,
        flags="A",
        seq=client_seq + 1,
        ack=server_seq + 1,
        window=65535,
    )
    packets.append(ack_packet)

    client_seq += 1
    server_seq += 1

    print("Added TCP handshake packets")

    # Process each data segment with direction
    for segment_idx, (direction, data) in enumerate(data_segments):
        print(f"\nProcessing {direction} segment {segment_idx + 1}:")

        # Parse HTTP/2 frames in this segment
        frames = parse_http2_frames(data)

        # Determine packet direction
        if direction == "sent":
            src_ip, dst_ip = client_ip, server_ip
            src_port, dst_port = client_port, server_port
            seq_num = client_seq
            ack_num = server_seq
        else:  # received
            src_ip, dst_ip = server_ip, client_ip
            src_port, dst_port = server_port, client_port
            seq_num = server_seq
            ack_num = client_seq

        if not frames:
            # If no frames found, send as single packet
            packet = (
                IP(src=src_ip, dst=dst_ip)
                / TCP(
                    sport=src_port,
                    dport=dst_port,
                    seq=seq_num,
                    ack=ack_num,
                    flags="PA",
                    window=65535,
                )
                / Raw(load=data)
            )
            packets.append(packet)

            # Update sequence numbers
            if direction == "sent":
                client_seq += len(data)
            else:
                server_seq += len(data)
            continue

        # Send each frame as a separate packet for better Wireshark analysis
        for frame_item in frames:
            # Handle both old format (frame_info, frame_data) and new format (frame_info, frame_data, stream_id)
            if len(frame_item) == 3:
                frame_info, frame_data, stream_id = frame_item
            else:
                frame_info, frame_data = frame_item
            if not frame_data:
                continue

            # Create packet with this frame
            packet = (
                IP(src=src_ip, dst=dst_ip)
                / TCP(
                    sport=src_port,
                    dport=dst_port,
                    seq=seq_num,
                    ack=ack_num,
                    flags="PA",  # Push + ACK
                    window=65535,
                )
                / Raw(load=frame_data)
            )

            packets.append(packet)

            # Update sequence number for the sending side
            if direction == "sent":
                client_seq += len(frame_data)
                seq_num = client_seq
            else:
                server_seq += len(frame_data)
                seq_num = server_seq

            direction_arrow = "→" if direction == "sent" else "←"
            print(
                f"    Packet {len(packets)}: {direction_arrow} {frame_info} ({len(frame_data)} bytes)"
            )

    # Write packets to pcap file
    wrpcap(output_filename, packets)
    print(f"\nPCAP file '{output_filename}' created with {len(packets)} packets")
    print(
        "This file contains bidirectional HTTP/2 traffic and should be properly recognized by Wireshark"
    )


def main():
    global http2_streams, hpack_decoder

    # Reset global state
    http2_streams = {}
    hpack_decoder = None

    input_file = "capture.txt"  # Changed from paste.txt
    output_file = "capture/api-voice-service.pcap"

    print("Creating output directories...")
    create_directories()

    print("Parsing traffic file for bidirectional HTTP/2 data...")
    data_segments = parse_traffic_file(input_file)

    if not data_segments:
        print("No data segments found in the file!")
        return

    print(f"Found {len(data_segments)} data segments")

    print("\nAnalyzing HTTP/2 structure and extracting multipart data...")
    create_http2_pcap(data_segments, output_file)

    # Process any remaining incomplete streams
    print(f"\nProcessing {len(http2_streams)} HTTP/2 streams for multipart data...")
    for stream_id, stream in http2_streams.items():
        if not stream["complete"] and stream["data"]:
            print(f"Processing incomplete stream {stream_id}")
            parse_multipart_data(stream_id, stream)

    print("\nGenerated files:")
    print(f"- PCAP: {output_file}")
    print("- Extracted files in capture/ directory:")

    # List extracted files
    for root, dirs, files in os.walk("capture"):
        for file in files:
            filepath = os.path.join(root, file)
            size = os.path.getsize(filepath)
            print(f"  {filepath} ({size} bytes)")

    # Print some statistics
    sent_segments = [seg for direction, seg in data_segments if direction == "sent"]
    received_segments = [
        seg for direction, seg in data_segments if direction == "received"
    ]

    total_sent_bytes = sum(len(data) for data in sent_segments)
    total_received_bytes = sum(len(data) for data in received_segments)
    total_bytes = total_sent_bytes + total_received_bytes

    print("\nStatistics:")
    print(f"- Total data segments: {len(data_segments)}")
    print(f"- Sent segments: {len(sent_segments)} ({total_sent_bytes} bytes)")
    print(
        f"- Received segments: {len(received_segments)} ({total_received_bytes} bytes)"
    )
    print(f"- Total payload bytes: {total_bytes}")
    print(f"- HTTP/2 streams found: {len(http2_streams)}")
    if data_segments:
        print(f"- Average segment size: {total_bytes // len(data_segments)} bytes")

    # Show stream summary
    for stream_id, stream in http2_streams.items():
        print(
            f"- Stream {stream_id}: {stream['method']} {stream['path']} ({len(stream['data'])} bytes data)"
        )


if __name__ == "__main__":
    main()
