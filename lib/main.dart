import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'apprtc/apprtc_client.dart';
import 'apprtc/peer_connection_client.dart';
import 'apprtc/websocket_rtc_client.dart';

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

  RTCVideoRenderer _localRenderer;
  RTCVideoRenderer _remoteRenderer;

  AppRTCClient _client;
  PeerConnectionClient _conn;
  SignalingParameters _signalingParameters;
  PeerConnectionParameters _peerConnectionParameters;
  DateTime _callStartedTime;

  @override
  void initState() {
    super.initState();
    _logs = <String>[];
    _setCalling(false);
    _localRenderer = RTCVideoRenderer()..initialize();
    _remoteRenderer = RTCVideoRenderer()..initialize();
    _client = WebSocketRTCClient(this);
    _conn = PeerConnectionClient(
        _peerConnectionParameters = PeerConnectionParameters(
          videoCallEnabled: true,
          loopback: false,
          tracing: false,
          videoWidth: 1080,
          videoHeight: 2160,
          videoFps: 0,
          videoMaxBitrate: 0,
          videoCodec: "VP8",
          videoFlexfecEnabled: false,
          videoCodecHwAcceleration: true,
          audioStartBitrate: 0,
          audioCodec: "OPUS",
          noAudioProcessing: false,
          aecDump: false,
          saveInputAudioToFile: false,
          useOpenSLES: false,
          disableBuiltInAEC: false,
          disableBuiltInAGC: false,
          disableBuiltInNS: false,
          disableWebRtcAGCAndHPF: false,
          enableRtcEventLog: false,
          dataChannelParameters: DataChannelParameters(
            ordered: true,
            maxRetransmitTimeMs: -1,
            maxRetransmits: -1,
            protocol: "",
            negotiated: false,
            id: 1,
          ),
        ),
        this);
    _roomIdController = TextEditingController(text: "112233");
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
    _localRenderer.dispose();
    _remoteRenderer.dispose();
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
                    enabled: _calling == false,
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
                  Column(
                    children: <Widget>[
                      Expanded(child: RTCVideoView(_remoteRenderer)),
                      Expanded(child: RTCVideoView(_localRenderer)),
                    ],
                  ),
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
    _callStartedTime = DateTime.now();
    _client.connectToRoom(RoomConnectionParameters.simple(
        "https://appr.tc", _roomIdController.text, false));
    setState(() {
      _calling = null;
    });
  }

  void _hangUp() {
    _conn?.close();
    _client.disconnectFromRoom();
    _stream?.dispose();
    _remoteRenderer.srcObject = null;
  }

  MediaStream _stream;

  @override
  void reassemble() {
    super.reassemble();
  }

  @override
  void onConnectedToRoom(SignalingParameters params) async {
    if (!mounted) return;
    /*try {
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
      navigator.getUserMedia(mediaConstraints).then((stream) {
        _stream = stream;
        _remoteRenderer.srcObject = _stream;
        setState(() {
          _setCalling(true);
        });
      });
    } catch (e) {
      print(e.toString());
      setState(() {
        _setCalling(false);
      });
    }

    if (1 == 1) return;*/
    _signalingParameters = params;

    await _conn.createPeerConn(_remoteRenderer, _localRenderer, params);
    _logAndToast("Initiator is ${params.initiator}");
    if (params.initiator) {
      _logAndToast("Creating OFFER...");
      // Create offer. Offer SDP will be sent to answering client in
      // PeerConnectionEvents.onLocalDescription event.
      await _conn.createOffer();
    } else {
      if (params.offerSdp != null) {
        await _conn.setRemoteDescription(params.offerSdp);
        _logAndToast("Creating ANSWER 1 ...");
        // Create answer. Answer SDP will be sent to offering client in
        // PeerConnectionEvents.onLocalDescription event.
        await _conn.createAnswer();
      }

      if (params.iceCandidates != null) {
        // Add remote ICE candidates from room.
        for (RTCIceCandidate iceCandidate in params.iceCandidates) {
          await _conn.addRemoteIceCandidate(iceCandidate);
        }
      }
    }
    setState(() {
      _setCalling(true);
      _logs.add("onConnectedToRoom: ");
    });
  }

  @override
  void onRemoteDescription(RTCSessionDescription sdp) async {
    if (_conn == null) {
      print("E Received remote SDP for non-initilized peer connection.");
      return;
    }
    final delta = DateTime.now().difference(_callStartedTime);
    _logAndToast(
        "Received remote " + sdp.type + ", delay=${delta.inMilliseconds}ms");
    await _conn.setRemoteDescription(sdp);
    if (!_signalingParameters.initiator) {
      _logAndToast("Creating ANSWER 2 ...");
      // Create answer. Answer SDP will be sent to offering client in
      // PeerConnectionEvents.onLocalDescription event.
      await _conn.createAnswer();
    }
    setState(() {
//      _logs.add("onRemoteDescription");
    });
  }

  @override
  void onRemoteIceCandidate(RTCIceCandidate candidate) {
    if (_conn == null) {
      _logAndToast(
          "E Received ICE candidate for a non-initialized peer connection.");
      return;
    }
    _conn.addRemoteIceCandidate(candidate);
    setState(() {
//      _logs.add("onRemoteIceCandidate");
    });
  }

  @override
  void onRemoteIceCandidatesRemoved(List<RTCIceCandidate> candidates) {
    if (_conn == null) {
      _logAndToast(
          "E Received ICE candidate removals for a non-initialized peer connection.");
      return;
    }
    _conn.removeRemoteIceCandidates(candidates);
    setState(() {
//      _logs.add("onRemoteIceCandidatesRemoved");
    });
  }

  @override
  void onChannelClose() {
    _disconnect();
    _logAndToast("Remote end hung up; dropping PeerConnection");
    setState(() {
      _setCalling(false);
//      _logs.add("onChannelClose");
    });
  }

  @override
  void onChannelError(String description) {
    setState(() {
      _setCalling(false);
      _logs.add("onChannelError: $description");
    });
  }

  // Disconnect from remote resources, dispose of local resources, and exit.
  void _disconnect() {
    _conn?.close();
    _client.disconnectFromRoom();
  }

  // -----Implementation of PeerConnectionClient.PeerConnectionEvents.---------
  // Send local peer connection SDP and ICE candidates to remote party.
  // All callbacks are invoked from peer connection client looper thread and
  // are routed to UI thread.

  @override
  void onLocalDescription(RTCSessionDescription sdp) {
    if (_client != null) {
      final delta = DateTime.now().difference(_callStartedTime);
      _logAndToast("Sending " + sdp.type + ", delay=${delta.inMilliseconds}ms");
      if (_signalingParameters.initiator) {
        _client.sendOfferSdp(sdp);
      } else {
        _client.sendAnswerSdp(sdp);
      }
    }
    if (_peerConnectionParameters.videoMaxBitrate > 0) {
//      print("D Set video maximum bitrate: ${_peerConnectionParameters.videoMaxBitrate}");
//      _conn.setVideoMaxBitrate(_peerConnectionParameters.videoMaxBitrate);
    }
  }

  @override
  void onIceCandidate(RTCIceCandidate candidate) {
    _client?.sendLocalIceCandidate(candidate);
  }

  @override
  void onIceCandidatesRemoved(List<RTCIceCandidate> candidates) {
    _client?.sendLocalIceCandidateRemovals(candidates);
  }

  @override
  void onIceConnected() {
    final delta = DateTime.now().difference(_callStartedTime);
    _logAndToast("ICE connected, delay=${delta.inMilliseconds}ms");
  }

  @override
  void onIceDisconnected() {
    _logAndToast("ICE disconnected");
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

  void _logAndToast(String msg) {
    print(msg);
    setState(() {
      _logs.add(msg);
    });
  }
}
