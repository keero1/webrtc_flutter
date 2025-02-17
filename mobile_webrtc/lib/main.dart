import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_webrtc/service/webrtc_service.dart';

//toast
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final WebRTCService _webRTCService = WebRTCService();
  Uint8List? _imageData;
  String? _timestamp;

  late String serverUrl = 'ws://10.0.2.2:3000';

  @override
  void initState() {
    super.initState();

    _webRTCService.onConnectionStatusChanged = (isConnected) {
      setState(() {});
    };
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
                onPressed: _toggleConnection,
                child: Text(_webRTCService.isConnected
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
                  : Text(_webRTCService.isConnected
                      ? "Waiting for image..."
                      : "Not Connected"),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleConnection() {
    if (_webRTCService.isConnected) {
      _webRTCService.disconnectFromWebRTC();
      _imageData = null;
      _timestamp = null;
    } else {
      _webRTCService.connectToWebRTC(
        serverUrl,
        (status) {
          _showToast(status);
        },
        (imageData, timestamp) {
          setState(() {
            _imageData = imageData;
            _timestamp = timestamp;
          });
        },
      );
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 1,
    );
  }
}
