import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import 'package:flutter/foundation.dart';
import 'package:flutter_screen_capture/flutter_screen_capture.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';

class WebrtcService {
  // screenshot
  final _plugin = ScreenCapture();
  CapturedScreenArea? _fullScreenArea;
  // WebRTC
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  IOWebSocketChannel? _channel;

  bool _isConnected = false;
  bool _isSharing = false;
  Timer? _captureTimer;

  bool _hasErrorOccurred = false;

  Function(bool)? onConnectionStatusChanged;

  Future<bool> connectToWebRTC(
      String serverUrl, Function(String) onStatusUpdate) async {
    try {
      _channel = IOWebSocketChannel.connect(serverUrl);
      _channel?.sink.add(jsonEncode({"type": "sender"}));

      _peerConnection = await createPeerConnection({
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"}
        ]
      });

      _dataChannel = await _peerConnection!
          .createDataChannel('screenshot', RTCDataChannelInit());

      _peerConnection!.onIceCandidate = (candidate) {
        debugPrint("ICE Candidate Generated: ${candidate.toMap()}");
        _channel?.sink.add(jsonEncode({
          "type": "ice",
          "target": "receiver",
          "candidate": candidate.toMap()
        }));
      };

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _channel?.sink.add(jsonEncode(
          {"type": "offer", "sdp": offer.sdp, "sdpType": offer.type}));

      _channel?.stream.listen((message) async {
        await _handleMessage(message, onStatusUpdate);
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

  Future<void> _handleMessage(
      String message, Function(String) onStatusUpdate) async {
    final data = jsonDecode(message);

    switch (data["type"]) {
      case "statusUpdate":
        onStatusUpdate(data["message"]);
        disconnectFromWebRTC();
        break;
      case "error":
        if (!_hasErrorOccurred) {
          _hasErrorOccurred = true;
          onStatusUpdate(data["message"]);
        }
        disconnectFromWebRTC();
        break;

      case 'answer':
        await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data["sdp"], data["sdpType"]));
        _isConnected = true;
        onConnectionStatusChanged?.call(_isConnected);

        debugPrint("Remote description set!");
        break;
      case 'ice':
        _peerConnection!.addCandidate(RTCIceCandidate(
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
    _isSharing = false;

    onConnectionStatusChanged?.call(_isConnected);
  }

  //screenshot
  Future<void> startStopScreenCapture() async {
    if (_isConnected) {
      if (_isSharing) {
        debugPrint("Stopping screen capture...");
        _isSharing = false;
        _captureTimer?.cancel();
      } else {
        debugPrint("Starting screen capture...");
        _captureTimer =
            Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (!_isSharing) {
            timer.cancel();
            debugPrint("Capture Timer Stopped");
            return;
          }
          await _captureFullScreen();
        });
        _isSharing = true;
      }
    }
  }

  Future<void> _captureFullScreen() async {
    final area = await _plugin.captureEntireScreen();

    // Convert and fix colors
    await _swapRedBlueChannels(area!);
    await _sendScreenshot(_fullScreenArea!);
  }

  static const int chunkSize = 16000;

  // The package flutter_capture_screen uses BGRA so since I'm runnng windows, I need to convert it to RGBA.
  Future<void> _swapRedBlueChannels(CapturedScreenArea area) async {
    if (Platform.isMacOS) {
      _fullScreenArea = area;
    }

    final correctedBuffer = Uint8List(area.buffer.length);

    for (int i = 0; i < area.buffer.length; i += area.bytesPerPixel) {
      final b = area.buffer[i];
      final g = area.buffer[i + 1];
      final r = area.buffer[i + 2];
      final a = area.buffer[i + 3];

      correctedBuffer[i] = r;
      correctedBuffer[i + 1] = g;
      correctedBuffer[i + 2] = b;
      correctedBuffer[i + 3] = a;
    }

    final correctedArea = area.copyWith(buffer: correctedBuffer);
    _fullScreenArea = correctedArea;
  }

  Future<void> _sendScreenshot(CapturedScreenArea area) async {
    if (_dataChannel == null || !_isConnected) return;

    img.Image? image = area.toImage();
    final Uint8List pngBytes = Uint8List.fromList(img.encodePng(image));

    int totalChunks = (pngBytes.length / chunkSize).ceil();
    int chunkIndex = 0;

    // Need to deconstruct the binary into chunks because WebRTC Data Channel cannot handle sending 1 big binary data.
    for (int i = 0; i < pngBytes.length; i += chunkSize) {
      final Uint8List chunk = pngBytes.sublist(
          i, i + chunkSize > pngBytes.length ? pngBytes.length : i + chunkSize);

      final Uint8List header =
          Uint8List.fromList("$chunkIndex/$totalChunks:".codeUnits);
      final Uint8List fullChunk = Uint8List.fromList([...header, ...chunk]);

      _dataChannel!.send(RTCDataChannelMessage.fromBinary(fullChunk));
      chunkIndex++;
    }
  }

  bool get isSharing => _isSharing;
  bool get isConnected => _isConnected;
}
