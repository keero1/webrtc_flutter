import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';

//time
import 'package:intl/intl.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  IOWebSocketChannel? _channel;
  Map<int, Uint8List> receivedChunks = {};
  String? _timestamp;

  bool _isConnected = false;

  Function(bool)? onConnectionStatusChanged;

  Future<bool> connectToWebRTC(
      String serverUrl,
      Function(String) onStatusUpdate,
      Function(Uint8List, String?) onImageUpdate) async {
    try {
      _channel = IOWebSocketChannel.connect(serverUrl);
      _channel?.sink.add(jsonEncode({"type": "receiver"}));

      _isConnected = true;
      onConnectionStatusChanged?.call(_isConnected);

      _peerConnection = await createPeerConnection({
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"}
        ]
      });

      _peerConnection?.onDataChannel = (RTCDataChannel channel) {
        debugPrint("DataChannel received: ${channel.label}");
        _dataChannel = channel;
        _setupDataChannel(onImageUpdate);
      };

      _peerConnection?.onIceCandidate = (candidate) {
        _channel?.sink.add(jsonEncode({
          "type": "ice",
          "target": "sender",
          "candidate": candidate.toMap()
        }));
      };

      _channel?.stream.listen((message) async {
        await _handleMessage(message, onStatusUpdate, onImageUpdate);
      },
          onError: (error) => disconnectFromWebRTC(),
          onDone: () => disconnectFromWebRTC());

      return true;
    } catch (error) {
      debugPrint("WebRTC connection error: $error");
      onStatusUpdate("WebRTC connection failed");
      return false;
    }
  }

  void _setupDataChannel(Function(Uint8List, String?) onImageUpdate) {
    int? expectedChunks;

    _dataChannel?.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        Uint8List data = message.binary;

        // reconstruct the chunks.
        String header =
            String.fromCharCodes(data.takeWhile((c) => c != 58).toList());
        List<String> parts = header.split('/');
        if (parts.length != 2) return;

        int chunkIndex = int.parse(parts[0]);
        expectedChunks = int.parse(parts[1]);
        Uint8List chunkData = data.sublist(header.length + 1);

        receivedChunks[chunkIndex] = chunkData;

        if (receivedChunks.length == expectedChunks) {
          List<int> fullImageBytes = [];
          for (int i = 0; i < expectedChunks!; i++) {
            fullImageBytes.addAll(receivedChunks[i]!);
          }

          Uint8List finalImage = Uint8List.fromList(fullImageBytes);
          _timestamp =
              "Updated at ${DateFormat('yyyy-MM-dd hh:mm:ss a').format(DateTime.now())}";

          onImageUpdate(finalImage, _timestamp);
          receivedChunks.clear();
          expectedChunks = null;
        }
      }
    };

    _dataChannel?.onDataChannelState = (state) {
      debugPrint("DataChannel State: $state");
    };
  }

  Future<void> _handleMessage(String message, Function(String) onStatusUpdate,
      Function(Uint8List, String?) onImageUpdate) async {
    final data = jsonDecode(message);

    switch (data["type"]) {
      case "statusUpdate":
      case "senderActive":
        onStatusUpdate(data["message"]);
        break;

      case "offer":
        RTCSessionDescription offer =
            RTCSessionDescription(data["sdp"], data["sdpType"]);
        await _peerConnection?.setRemoteDescription(offer);

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection?.setLocalDescription(answer);

        _channel?.sink.add(jsonEncode(
            {"type": "answer", "sdp": answer.sdp, "sdpType": answer.type}));
        break;

      case "ice":
        _peerConnection?.addCandidate(RTCIceCandidate(
            data["candidate"]["candidate"],
            data["candidate"]["sdpMid"],
            data["candidate"]["sdpMLineIndex"]));
        break;
    }
  }

  Future<void> disconnectFromWebRTC() async {
    await _peerConnection?.close();
    _channel?.sink.close();
    _isConnected = false;
    onConnectionStatusChanged?.call(_isConnected);
    receivedChunks.clear();
  }

  bool get isConnected => _isConnected;
}
