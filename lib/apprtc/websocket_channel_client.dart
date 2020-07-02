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

  WebSocketConnectionState _state;

  // Do not remove this member variable. If this is removed, the observer gets garbage collected and
  // this causes test breakages.
  Completer _closeEventCompleter;
  bool _closeEvent;
  List<String> _wsSendQueue;

  String _errorMessage;

  WebSocketChannelClient({
    OnMessageObserver onData,
    OnStateChangedObserver onStateChagned,
  }) {
    _wsSendQueue = [];
    _stateEvents = StreamController();
    _messageEvents = StreamController();
    _updateState(WebSocketConnectionState.NEW);

    _messageEvents.stream.listen(onData);
    _stateEvents.stream.listen(onStateChagned);
  }

  String get errorMessage => _errorMessage;

  WebSocketConnectionState get state => _state;

  void _updateState(WebSocketConnectionState field) {
    if (_state != field) {
      _state = field;
      _stateEvents.sink.add(_state);
    }
  }

  Future<void> connect(final String wsUrl, final String postUrl) async {
    if (state != WebSocketConnectionState.NEW) {
      print("e $_ WebSocket is already connected.");
      return;
    }
    _wsServerUrl = wsUrl;
    _postServerUrl = postUrl;
    _closeEvent = false;
    _errorMessage = null;

    print("d $_ Connecting WebSocket to: " + wsUrl + ". Post URL: " + postUrl);

    try {
      return WebSocket.connect(_wsServerUrl, headers: {
        "Origin": "https://apprtc-ws.webrtc.org"
      }).then((ws) {
        _ws = ws;
        _ws.listen((data) {
          print("I $_ onData: $data");
          _onTextMessage(data);
        }, onError: (err) {
          print("I $_ onError: $err");
          _reportError(err.message);
        }, onDone: () {
          print("I $_ onDone: ");
          _onClose(_ws.closeCode, _ws.closeReason);
        });
        _onOpen();
      });
    } catch (e, s) {
      print("E $_ $e\n$s");
      _reportError(e.message);
      return Future.error(e, s);
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
      print("w $_ WebSocket register() in state $_state");
      return;
    }

    print("d $_ Registering WebSocket for room " +
        roomID +
        ". ClientID: " +
        clientID);
    final json = <String, dynamic>{};
    json["cmd"] = "register";
    json["roomid"] = roomID;
    json["clientid"] = clientID;
    print("d $_ C->WSS: $json");

    _ws.add(jsonEncode(json));

    _updateState(WebSocketConnectionState.REGISTERED);
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
        print("d $_ WS ACC: $message");
        _wsSendQueue.add(message);
        return;
      case WebSocketConnectionState.ERROR:
      case WebSocketConnectionState.CLOSED:
        print("e $_ WebSocket send() in error or closed state : " + message);
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

  Future<void> disconnect(bool waitForComplete) {
    _checkIfCalledOnValidThread();
    print("d $_ Disconnect WebSocket. State: $_state");
    if (_state == WebSocketConnectionState.REGISTERED) {
      // Send "bye" to WebSocket server.
      send("{\"type\": \"bye\"}");
      _updateState(WebSocketConnectionState.CONNECTED);
      // Send http DELETE to http WebSocket server.
      _sendWSSMessage("DELETE", "");
    }
    // Close WebSocket in CONNECTED or ERROR states only.
    if (_state == WebSocketConnectionState.CONNECTED ||
        _state == WebSocketConnectionState.ERROR) {
      _updateState(WebSocketConnectionState.CLOSED);
      final close = _ws.close();
      if (waitForComplete) {
        return close;
      }

      // Wait for websocket close event to prevent websocket library from
      // sending any pending messages to deleted looper thread.
//      if (waitForComplete) {
//          while (!_closeEvent) {
//            try {
//              closeEventLock.wait(CLOSE_TIMEOUT);
//              break;
//            } catch (e) {
//          print("e $_ Wait error: " + e.toString());
//          }
//        }
//      }
    }
    print("d $_ Disconnecting WebSocket done.");
    return Future.value(null);
  }

  void _reportError(final String errorMessage) {
    print("e $_ " + errorMessage);
    if (_state != WebSocketConnectionState.ERROR) {
      _errorMessage = errorMessage;
      _updateState(WebSocketConnectionState.ERROR);
      // events.onWebSocketError(errorMessage);
    }
  }

  // Asynchronously send POST/DELETE to WebSocket server.
  void _sendWSSMessage(final String method, final String message) async {
    String postUrl = _postServerUrl + "/" + _roomID + "/" + _clientID;
    print("d $_ WS " + method + " : " + postUrl + " : " + message);

    try {
      final client = HttpClient();
      final req = await client.openUrl(method, Uri.parse(postUrl));

      req.add(utf8.encode(message));

      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception("Non-200 response to " +
            method +
            " to URL: " +
            postUrl +
            " : " +
            resp.headers?.toString());
      }
    } catch (e) {
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
    print("d $_ WebSocket connection opened to: " + _wsServerUrl);
    _updateState(WebSocketConnectionState.CONNECTED);
    // Check if we have pending register request.
    if (_roomID != null && _clientID != null) {
      register(_roomID, _clientID);
    }
  }

  void _onClose(int code, String reason) {
    print(
        "d $_ WebSocket connection closed. Code: $code. Reason: $reason. State: $_state");
//    synchronized (closeEventLock) {
//      closeEvent = true;
//      closeEventLock.notify();
//    }
    if (state != WebSocketConnectionState.CLOSED) {
      _updateState(WebSocketConnectionState.CLOSED);
//      events.onWebSocketClose();
    }
  }

  void _onTextMessage(dynamic payload) {
    print("d $_ WSS->C: " + payload);

    if (_state == WebSocketConnectionState.CONNECTED ||
        _state == WebSocketConnectionState.REGISTERED) {
      _messageEvents.sink.add(payload);
    }
  }
}
