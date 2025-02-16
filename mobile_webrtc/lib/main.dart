import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';

//toast
import 'package:fluttertoast/fluttertoast.dart';

//time
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  Uint8List? _imageData;
  bool _isConnected = false;
  late IOWebSocketChannel _channel;

  String? _timestamp;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _connectToWebRTC() async {
    try {
      _channel = IOWebSocketChannel.connect(
          'ws://10.0.2.2:3000'); // hardcoded IP for now.
      _channel.sink.add(jsonEncode({"type": "receiver"}));

      setState(() {
        _isConnected = true;
      });

      _peerConnection = await createPeerConnection({
        "iceServers": [
          {"urls": "stun:stun.l.google.com:19302"}
        ]
      });

      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        if (kDebugMode) {
          print("DataChannel received: ${channel.label}");
        }
        _dataChannel = channel;

        Map<int, Uint8List> receivedChunks = {};
        int? expectedChunks;

        _dataChannel!.onMessage = (RTCDataChannelMessage message) {
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
              setState(() {
                _imageData = finalImage;
                _timestamp =
                    "Updated at ${DateFormat('yyyy-MM-dd hh:mm:ss a').format(DateTime.now())}";
              });

              receivedChunks.clear();
              expectedChunks = null;
            }
          }
        };

        _dataChannel!.onDataChannelState = (state) {
          if (kDebugMode) {
            print("DataChannel State: $state");
          }
        };
      };

      _peerConnection!.onIceCandidate = (candidate) {
        _channel.sink.add(jsonEncode({
          "type": "ice",
          "target": "sender",
          "candidate": candidate.toMap()
        }));
      };

      _channel.stream.listen((message) async {
        final data = jsonDecode(message);

        if (data["type"] == "statusUpdate") {
          Fluttertoast.showToast(
            msg: data["message"],
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
          );
        }

        if (data["type"] == "senderActive") {
          Fluttertoast.showToast(
            msg: data["message"],
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
          );
        }

        if (data["type"] == "offer") {
          RTCSessionDescription offer =
              RTCSessionDescription(data["sdp"], data["sdpType"]);
          await _peerConnection!.setRemoteDescription(offer);

          RTCSessionDescription answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);

          _channel.sink.add(jsonEncode(
              {"type": "answer", "sdp": answer.sdp, "sdpType": answer.type}));
        } else if (data["type"] == "ice") {
          _peerConnection!.addCandidate(RTCIceCandidate(
              data["candidate"]["candidate"],
              data["candidate"]["sdpMid"],
              data["candidate"]["sdpMLineIndex"]));
        }
      }, onError: (error) {
        _disconnectFromWebRTC();
      }, onDone: () {
        _disconnectFromWebRTC();
      });
    } catch (error) {
      return;
    }
  }

  Future<void> _disconnectFromWebRTC() async {
    await _peerConnection?.close();
    _channel.sink.close();
    setState(() {
      _isConnected = false;
      _imageData = null;
    });
  }

  @override
  void dispose() {
    _peerConnection?.close();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("Receiver App")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              const SizedBox(height: 20),
              _imageData != null
                  ? Column(
                      children: [
                        Image.memory(_imageData!),
                        const SizedBox(height: 10),
                        Text(
                          _timestamp ?? "",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : Text(
                      _isConnected ? "Waiting for image..." : "Not Connected"),
            ],
          ),
        ),
      ),
    );
  }
}
