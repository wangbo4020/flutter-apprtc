import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_apprtc/apprtc/apprtc_client.dart';
import 'package:flutter_apprtc/apprtc/peer_connection_client.dart';
import 'package:flutter_apprtc/apprtc/websocket_rtc_client.dart';
import 'package:flutter_webrtc/webrtc.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    implements SignalingEvents, PeerConnectionEvents {
  TextEditingController _roomIdController;
  List<String> _logs;
  bool _calling;
  String _button;
  IconData _icon;

  RTCVideoRenderer _renderer;

  AppRTCClient _client;
  PeerConnectionClient _conn;

  @override
  void initState() {
    super.initState();
    _logs = <String>[];
    _setCalling(false);
    _renderer = RTCVideoRenderer()..initialize();
    _client = WebSocketRTCClient(this);
    _conn = PeerConnectionClient(
        _renderer,
        PeerConnectionParameters(
          videoCallEnabled: true,
          loopback: false,
          tracing: false,
          videoWidth: 720,
          videoHeight: 1280,
        ),
        this);
    _roomIdController = TextEditingController();
  }

  void _setCalling(bool calling) {
    if (calling != _calling) {
      _calling = calling;

      if (calling != null) {
        if (calling) {
          _button = "Hang Up";
          _icon = Icons.call_end;
        } else {
          _button = "Call";
          _icon = Icons.call;
        }
      }
    }
  }

  @override
  void dispose() {
    _stream?.dispose();
    _renderer.dispose();
    _conn.close();
    _client.disconnectFromRoom();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _roomIdController,
                  ),
                ),
                OutlineButton.icon(
                  onPressed: _calling == null
                      ? null
                      : () {
                          if (_calling) {
                            _hangUp();
                            return;
                          }
                          final text = _roomIdController.text;
                          if (text.isEmpty) {
                            return;
                          }
                          _makeCall();
                        },
                  icon: Icon(_icon),
                  label: Text(_button),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: Stack(
                children: <Widget>[
                  RTCVideoView(_renderer),
                  ListView.builder(
                    itemBuilder: (context, i) => Text(_logs[i]),
                    itemCount: _logs.length,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _makeCall() {
    _client.connectToRoom(RoomConnectionParameters.simple(
        "https://appr.tc", _roomIdController.text, false));
    setState(() {
      _calling = null;
    });
  }

  void _hangUp() {
    _client.disconnectFromRoom();
    _stream?.dispose();
    _renderer.srcObject = null;
  }

  @override
  void onChannelClose() {
    setState(() {
      _setCalling(false);
      _logs.add("onChannelClose");
    });
  }

  @override
  void onChannelError(String description) {
    setState(() {
      _setCalling(false);
      _logs.add("onChannelError: $description");
    });
  }

  MediaStream _stream;

  @override
  void onConnectedToRoom(SignalingParameters params) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> mediaConstraints = {
        "audio": false,
        "video": {
          "mandatory": {
            "minWidth": '640',
            // Provide your own width, height and frame rate here
            "minHeight": '480',
            "minFrameRate": '30',
          },
          "facingMode": "user",
          "optional": [],
        }
      };
      navigator.getDisplayMedia(mediaConstraints).then((stream) {
        _stream = stream;
        _renderer.srcObject = _stream;
      });
    } catch (e) {
      print(e.toString());
    }
    setState(() {
      _setCalling(true);
      _logs.add("onConnectedToRoom: ");
    });
  }

  @override
  void onRemoteDescription(RTCSessionDescription sdp) {
    setState(() {
      _logs.add("onRemoteDescription");
    });
  }

  @override
  void onRemoteIceCandidate(RTCIceCandidate candidate) {
    setState(() {
      _logs.add("onRemoteIceCandidate");
    });
  }

  @override
  void onRemoteIceCandidatesRemoved(List<RTCIceCandidate> candidates) {
    setState(() {
      _logs.add("onRemoteIceCandidatesRemoved");
    });
  }

  @override
  void onConnected() {
    // TODO: implement onConnected
  }

  @override
  void onDisconnected() {
    // TODO: implement onDisconnected
  }

  @override
  void onIceCandidate(RTCIceCandidate candidate) {
    // TODO: implement onIceCandidate
  }

  @override
  void onIceCandidatesRemoved(List<RTCIceCandidate> candidates) {
    // TODO: implement onIceCandidatesRemoved
  }

  @override
  void onIceConnected() {
    // TODO: implement onIceConnected
  }

  @override
  void onIceDisconnected() {
    // TODO: implement onIceDisconnected
  }

  @override
  void onLocalDescription(RTCSessionDescription sdp) {
    // TODO: implement onLocalDescription
  }

  @override
  void onPeerConnectionClosed() {
    // TODO: implement onPeerConnectionClosed
  }

  @override
  void onPeerConnectionError(String description) {
    // TODO: implement onPeerConnectionError
  }

  @override
  void onPeerConnectionStatsReady(List<StatsReport> reports) {
    // TODO: implement onPeerConnectionStatsReady
  }
}
