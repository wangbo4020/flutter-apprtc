import 'dart:async';
import 'dart:convert';

import 'dart:io';

///
/// Possible WebSocket connection states.
///
enum WebSocketConnectionState { NEW, CONNECTED, REGISTERED, CLOSED, ERROR }

typedef OnMessageObserver = Function(dynamic data);
typedef OnStateChangedObserver = Function(WebSocketConnectionState state);

class WebSocketChannelClient {
  static const _ = "WebSocketChannelClient";

  StreamController<WebSocketConnectionState> _stateEvents;
  StreamController<dynamic> _messageEvents;

  WebSocket _ws;
  String _wsServerUrl;
  String _postServerUrl;

  String _roomID;
  String _clientID;
  bool _closeEvent;

  WebSocketConnectionState _state;
  List<String> _wsSendQueue;

  String _errorMessage;

  WebSocketChannelClient({
    OnMessageObserver onData,
    OnStateChangedObserver onStateChagned,
  }) {
    _stateEvents = StreamController();
    _messageEvents = StreamController();
    _state = WebSocketConnectionState.NEW;

    _messageEvents.stream.listen(onData);
    _stateEvents.stream.listen(onStateChagned);
  }

  WebSocketConnectionState get state => _state;

  void connect(final String wsUrl, final String postUrl) async {
    if (state != WebSocketConnectionState.NEW) {
      print("$_ e WebSocket is already connected.");
      return;
    }
    _wsServerUrl = wsUrl;
    _postServerUrl = postUrl;
    _closeEvent = false;
    _errorMessage = null;

    print("$_ d Connecting WebSocket to: " + wsUrl + ". Post URL: " + postUrl);

    try {
      _ws = await WebSocket.connect(_wsServerUrl);
      _ws.listen(
          (data) {
            _onTextMessage(data);
          },
          onError: (err) {},
          onDone: () {
            _onClose(_ws.closeCode, _ws.closeReason);
          });
      _onOpen();
    } catch (e) {
      _reportError(e.message);
    }
//    ws = new WebSocketConnection();
//    wsObserver = new WebSocketObserver();
//    try {
//      ws.connect(new URI(wsServerUrl), wsObserver);
//    } catch (URISyntaxException e) {
//    reportError("URI error: " + e.getMessage());
//    } catch (WebSocketException e) {
//    reportError("WebSocket connection error: " + e.getMessage());
//    }
  }

  void register(final String roomID, final String clientID) {
    _checkIfCalledOnValidThread();
    this._roomID = roomID;
    this._clientID = clientID;

    if (state != WebSocketConnectionState.CONNECTED) {
      print("$_ w WebSocket register() in state $_state");
      return;
    }

    print("$_ d Registering WebSocket for room " +
        roomID +
        ". ClientID: " +
        clientID);
    final json = <String, dynamic>{};
    json["cmd"] = "register";
    json["roomid"] = roomID;
    json["clientid"] = clientID;
    print("$_ d C->WSS: $json");

    _ws.add(jsonEncode(json));

    _state = WebSocketConnectionState.REGISTERED;
    // Send any previously accumulated messages.
    for (String sendMessage in _wsSendQueue) {
      send(sendMessage);
    }
    _wsSendQueue.clear();
  }

  void send(String message) {
    _checkIfCalledOnValidThread();
    switch (_state) {
      case WebSocketConnectionState.NEW:
      case WebSocketConnectionState.CONNECTED:
        // Store outgoing messages and send them after websocket client
        // is registered.
        print("$_ d WS ACC: $message");
        _wsSendQueue.add(message);
        return;
      case WebSocketConnectionState.ERROR:
      case WebSocketConnectionState.CLOSED:
        print("$_ e WebSocket send() in error or closed state : " + message);
        return;
      case WebSocketConnectionState.REGISTERED:
        final json = <String, dynamic>{
          "cmd": "send",
          "msg": message,
        };
        _ws.add(jsonEncode(json));
        break;
    }
  }

  // This call can be used to send WebSocket messages before WebSocket
  // connection is opened.
  void post(String message) {
    _checkIfCalledOnValidThread();
    _sendWSSMessage("POST", message);
  }

  void _reportError(final String errorMessage) {
    print("$_ e " + errorMessage);
    if (_state != WebSocketConnectionState.ERROR) {
      _errorMessage = errorMessage;
      _state = WebSocketConnectionState.ERROR;
      _stateEvents.sink.add(_state); // events.onWebSocketError(errorMessage);
    }
  }

  // Asynchronously send POST/DELETE to WebSocket server.
  void _sendWSSMessage(final String method, final String message) async {
    String postUrl = _postServerUrl + "/" + _roomID + "/" + _clientID;
    print("$_ d WS " + method + " : " + postUrl + " : " + message);

    try {
      final client = HttpClient();
      final req = await client.openUrl(method, Uri.parse(postUrl));

      req.add(utf8.encode(message));

      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception("Non-200 response to " + method + " to URL: " + postUrl + " : "
            + resp.headers?.toString());
      }
    } catch(e) {
      _reportError(e.message);
    }

    /*AsyncHttpURLConnection httpConnection =
    new AsyncHttpURLConnection(method, postUrl, message, new AsyncHttpEvents() {
    @Override
    public void onHttpError(String errorMessage) {
    reportError("WS " + method + " error: " + errorMessage);
    }

    @Override
    public void onHttpComplete(String response) {}
    });
    httpConnection.send();*/

  }

  // Helper method for debugging purposes. Ensures that WebSocket method is
  // called on a looper thread.
  void _checkIfCalledOnValidThread() {
//    if (Thread.currentThread() != handler.getLooper().getThread()) {
//      throw new IllegalStateException("WebSocket method is not called on valid thread");
//    }
  }

  void _onOpen() {
    print("$_ d WebSocket connection opened to: " + _wsServerUrl);
    _state = WebSocketConnectionState.CONNECTED;
    // Check if we have pending register request.
    if (_roomID != null && _clientID != null) {
      register(_roomID, _clientID);
    }
  }

  void _onClose(int code, String reason) {}

  void _onTextMessage(dynamic payload) {
    print("$_ d WSS->C: " + payload);

    if (_state == WebSocketConnectionState.CONNECTED ||
        _state == WebSocketConnectionState.REGISTERED) {
      _messageEvents.sink.add(payload);
    }
  }
}
