import 'dart:async';
import 'package:desktop_webrtc/service/webrtc_service.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(home: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final WebrtcService _webRTCService = WebrtcService();
  late String serverUrl = 'ws://localhost:3000';

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
        appBar: AppBar(title: Text("Sender App")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_webRTCService.isConnected
                  ? "Connected to WebRTC"
                  : "Not Connected to WebRTC"),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _toggleConnect,
                child: Text(_webRTCService.isConnected
                    ? "Disconnect from WebRTC"
                    : "Connect to WebRTC"),
              ),
              SizedBox(height: 20),
              if (_webRTCService.isConnected)
                ElevatedButton(
                  onPressed: _webRTCService.startStopScreenCapture,
                  child: Text(_webRTCService.isSharing
                      ? "Stop Sharing Screen"
                      : "Start Sharing Screen"),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleConnect() {
    if (_webRTCService.isConnected) {
      _webRTCService.disconnectFromWebRTC();
    } else {
      _webRTCService.connectToWebRTC(serverUrl, (status) {
        _showMyDialog(status);
      });
    }
  }

  // popup
  Future<void> _showMyDialog(String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Alert"),
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
}
