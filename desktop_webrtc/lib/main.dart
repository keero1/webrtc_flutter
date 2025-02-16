import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screen_capture/flutter_screen_capture.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image/image.dart' as img;

import 'dart:convert';
import 'package:web_socket_channel/io.dart';

late IOWebSocketChannel _channel;

void main() {
  runApp(MaterialApp(home: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _plugin = ScreenCapture();
  CapturedScreenArea? _fullScreenArea;

  // WebRTC
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  bool _isConnected = false;
  bool _isSharing = false;
  Timer? _captureTimer;

  bool _isDialogVisible = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _connectToWebRTC() async {
    try {
      _channel = IOWebSocketChannel.connect(
          'ws://localhost:3000'); // hardcoded for IP for now.
      _channel.sink.add(jsonEncode({"type": "sender"}));

      _peerConnection = await createPeerConnection({
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"}
        ]
      });

      _dataChannel = await _peerConnection!
          .createDataChannel('screenshot', RTCDataChannelInit());

      _peerConnection!.onIceCandidate = (candidate) {
        if (kDebugMode) {
          print("ICE Candidate Generated: ${candidate.toMap()}");
        } // Debugging
        _channel.sink.add(jsonEncode({
          "type": "ice",
          "target": "receiver",
          "candidate": candidate.toMap()
        }));
      };

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _channel.sink.add(jsonEncode(
          {"type": "offer", "sdp": offer.sdp, "sdpType": offer.type}));

      _channel.stream.listen(
        (message) async {
          final data = jsonDecode(message);

          // since the forward thing of webrtc is sent multiple times, this will get triggered multiple times resulting in many dialog without this condition.
          if (data["type"] == "error" && !_isDialogVisible) {
            _isDialogVisible = true;
            await _showMyDialog(
                "Alert", "Receiver is not available. Please try again.");
            _isDialogVisible = false;
            return;
          }

          //end session if the receiver has disconnected.
          if (data["type"] == "statusUpdate") {
            _showMyDialog(
                "Alert", "The Receiver has Disconnected. Ending the session.");
            await _disconnectFromWebRTC();
          }

          if (data["type"] == "answer") {
            await _peerConnection!.setRemoteDescription(
                RTCSessionDescription(data["sdp"], data["sdpType"]));

            setState(() {
              _isConnected = true;
            });
            if (kDebugMode) {
              print("Remote description set!");
            }
          } else if (data["type"] == "ice") {
            _peerConnection!.addCandidate(RTCIceCandidate(
                data["candidate"]["candidate"],
                data["candidate"]["sdpMid"],
                data["candidate"]["sdpMLineIndex"]));
          }
        },
        onError: (error) {
          _disconnectFromWebRTC();
        },
        onDone: () {
          _disconnectFromWebRTC();
        },
      );
    } catch (e) {
      _showMyDialog("Alert", "Failed to connect to the WebRTC server");
      return;
    }
  }

  Future<void> _disconnectFromWebRTC() async {
    await _peerConnection?.close();
    _channel.sink.close();
    setState(() {
      _isConnected = false;
      _isSharing = false;
    });
  }

  void _startStopScreenCapture() {
    if (_isConnected) {
      if (_isSharing) {
        if (kDebugMode) {
          print("Stopping screen capture...");
        }
        setState(() {
          _isSharing = false;
        });
        _captureTimer?.cancel();
      } else {
        if (kDebugMode) {
          print("Starting screen capture...");
        }
        _captureTimer =
            Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (!_isSharing) {
            timer.cancel();
            if (kDebugMode) {
              print("Capture Timer Stopped");
            }
            return;
          }
          await _captureFullScreen();
        });
        setState(() {
          _isSharing = true;
        });
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
      setState(() {
        _fullScreenArea = area;
      });
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
    setState(() {
      _fullScreenArea = correctedArea;
    });
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

  // popup
  Future<void> _showMyDialog(String title, String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(message),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _peerConnection?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("Sender App")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_isConnected
                  ? "Connected to WebRTC"
                  : "Not Connected to WebRTC"),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_isConnected) {
                    _disconnectFromWebRTC();
                  } else {
                    _connectToWebRTC();
                  }
                },
                child: Text(_isConnected
                    ? "Disconnect from WebRTC"
                    : "Connect to WebRTC"),
              ),
              SizedBox(height: 20),
              if (_isConnected)
                ElevatedButton(
                  onPressed: _startStopScreenCapture,
                  child: Text(_isSharing
                      ? "Stop Sharing Screen"
                      : "Start Sharing Screen"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
