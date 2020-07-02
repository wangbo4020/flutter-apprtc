import 'dart:convert';
import 'dart:io';

import 'package:flutter_apprtc/apprtc/room_parameters_fetcher.dart';
import 'package:flutter_webrtc/rtc_ice_candidate.dart';

import 'package:flutter_webrtc/rtc_session_description.dart';

import 'apprtc_client.dart';
import 'websocket_channel_client.dart';

enum ConnectionState { NEW, CONNECTED, CLOSED, ERROR }

enum MessageType { MESSAGE, LEAVE }

///
/// Negotiates signaling for chatting with https://appr.tc "rooms".
/// Uses the client<->server specifics of the apprtc AppEngine webapp.
///
/// <p>To use: create an instance of this object (registering a message handler) and
/// call connectToRoom().  Once room connection is established
/// onConnectedToRoom() callback with room parameters is invoked.
/// Messages to other party (with local Ice candidates and answer SDP) can
/// be sent after WebSocket connection is established.
///
class WebSocketRTCClient implements AppRTCClient {
  static const String _ = "WSRTCClient";
  static const String _ROOM_JOIN = "join";
  static const String _ROOM_MESSAGE = "message";
  static const String _ROOM_LEAVE = "leave";

  bool _initiator;
  SignalingEvents _events;
  WebSocketChannelClient _wsClient;
  ConnectionState _roomState;
  RoomConnectionParameters _connectionParameters;
  String _messageUrl;
  String _leaveUrl;

  WebSocketRTCClient(this._events) {
    _roomState = ConnectionState.NEW;
  }

  void _updateRoomState(ConnectionState state) {
    if (_roomState != state) {
      _roomState = state;
    }
  }

  // --------------------------------------------------------------------
  // AppRTCClient interface implementation.
  // Asynchronously connect to an AppRTC room URL using supplied connection
  // parameters, retrieves room parameters and connect to WebSocket server.
  @override
  void connectToRoom(RoomConnectionParameters connectionParameters) {
    this._connectionParameters = connectionParameters;
    _connectToRoomInternal();
  }

  @override
  void disconnectFromRoom() {
    _disconnectFromRoomInternal();
  }

  // Connects to room - function runs on a local looper thread.
  void _connectToRoomInternal() {
    String connectionUrl = _getConnectionUrl(_connectionParameters);
    print("d $_ Connect to room: " + connectionUrl);
    _roomState = ConnectionState.NEW;
    _wsClient = new WebSocketChannelClient(
      onData: (data) {
        onWebSocketMessage(data);
      },
      onStateChagned: (state) {
        print("i $_ onStateChanged: $state");
        if (state == WebSocketConnectionState.CLOSED) {
          onWebSocketClose();
        } else if (state == WebSocketConnectionState.ERROR) {
          onWebSocketError(_wsClient.errorMessage);
        }
      },
    );

    RoomParametersFetcher(connectionUrl, null).makeRequest().then((params) {
      _signalingParametersReady(params);
    }).catchError((e, s) {
      print("w $_ $e\n$s");
      _reportError(e?.toString());
    });
  }

  // Disconnect from room and send bye messages - runs on a local looper thread.
  void _disconnectFromRoomInternal() {
    print("d $_ Disconnect. Room state: $_roomState");
    if (_roomState == ConnectionState.CONNECTED) {
      print("d $_ Closing room.");
      _sendPostMessage(MessageType.LEAVE, _leaveUrl, null);
    }
    _roomState = ConnectionState.CLOSED;
    if (_wsClient != null) {
      _wsClient.disconnect(true);
    }
  }

  // Helper functions to get connection, post message and leave message URLs
  String _getConnectionUrl(RoomConnectionParameters connectionParameters) {
    return connectionParameters.roomUrl +
        "/" +
        _ROOM_JOIN +
        "/" +
        connectionParameters.roomId +
        _getQueryString(connectionParameters);
  }

  String _getMessageUrl(RoomConnectionParameters connectionParameters,
      SignalingParameters signalingParameters) {
    return connectionParameters.roomUrl +
        "/" +
        _ROOM_MESSAGE +
        "/" +
        connectionParameters.roomId +
        "/" +
        signalingParameters.clientId +
        _getQueryString(connectionParameters);
  }

  String _getLeaveUrl(RoomConnectionParameters connectionParameters,
      SignalingParameters signalingParameters) {
    return connectionParameters.roomUrl +
        "/" +
        _ROOM_LEAVE +
        "/" +
        connectionParameters.roomId +
        "/" +
        signalingParameters.clientId +
        _getQueryString(connectionParameters);
  }

  String _getQueryString(RoomConnectionParameters connectionParameters) {
    if (connectionParameters.urlParameters != null) {
      return "?" + connectionParameters.urlParameters;
    } else {
      return "";
    }
  }

  // Callback issued when room parameters are extracted. Runs on local
  // looper thread.
  void _signalingParametersReady(
      final SignalingParameters signalingParameters) {
    print("d $_ Room connection completed.");
    if (_connectionParameters.loopback &&
        (!signalingParameters.initiator ||
            signalingParameters.offerSdp != null)) {
      _reportError("Loopback room is busy.");
      return;
    }
    if (!_connectionParameters.loopback &&
        !signalingParameters.initiator &&
        signalingParameters.offerSdp == null) {
      print("w $_ No offer SDP in room response.");
    }
    _initiator = signalingParameters.initiator;
    _messageUrl = _getMessageUrl(_connectionParameters, signalingParameters);
    _leaveUrl = _getLeaveUrl(_connectionParameters, signalingParameters);
    print("d $_ Message URL: " + _messageUrl);
    print("d $_ Leave URL: " + _leaveUrl);
    _roomState = ConnectionState.CONNECTED;

    // Fire connection and signaling parameters events.
    _events.onConnectedToRoom(signalingParameters);

    // Connect and register WebSocket client.
    _wsClient
        .connect(
      signalingParameters.wssUrl,
      signalingParameters.wssPostUrl,
    )
        .then((_) {
      _wsClient.register(
          _connectionParameters.roomId, signalingParameters.clientId);
    });
  }

  // Send local offer SDP to the other participant.
  @override
  void sendOfferSdp(RTCSessionDescription sdp) {
    if (_roomState != ConnectionState.CONNECTED) {
      _reportError("Sending offer SDP in non connected state.");
      return;
    }
    final json = <String, String>{};
    json["sdp"] = sdp.sdp;
    json["type"] = "offer";
    _sendPostMessage(MessageType.MESSAGE, _messageUrl, jsonEncode(json));
    if (_connectionParameters.loopback) {
      // In loopback mode rename this offer to answer and route it back.
      RTCSessionDescription sdpAnswer =
          new RTCSessionDescription("answer", sdp.sdp);
      _events.onRemoteDescription(sdpAnswer);
    }
  }

  // Send local answer SDP to the other participant.
  @override
  void sendAnswerSdp(RTCSessionDescription sdp) {
    if (_connectionParameters.loopback) {
      print("e $_ Sending answer in loopback mode.");
      return;
    }
    final json = <String, String>{
      "sdp": sdp.sdp,
      "type": "answer",
    };
    _wsClient.send(jsonEncode(json));
  }

  // Send Ice candidate to the other participant.
  @override
  void sendLocalIceCandidate(RTCIceCandidate candidate) {
    final json = {
      "type": "candidate",
      "label": candidate.sdpMlineIndex,
      "id": candidate.sdpMid,
      "candidate": candidate.candidate,
    };
    if (_initiator) {
      // Call initiator sends ice candidates to GAE server.
      if (_roomState != ConnectionState.CONNECTED) {
        _reportError("Sending ICE candidate in non connected state.");
        return;
      }
      _sendPostMessage(MessageType.MESSAGE, _messageUrl, jsonEncode(json));
      if (_connectionParameters.loopback) {
        _events.onRemoteIceCandidate(candidate);
      }
    } else {
      // Call receiver sends ice candidates to websocket server.
      _wsClient.send(jsonEncode(json));
    }
  }

  // Send removed Ice candidates to the other participant.
  @override
  void sendLocalIceCandidateRemovals(List<RTCIceCandidate> candidates) {
    final json = <String, dynamic>{
      "type": "remove-candidates",
      "candidates": candidates.map(_toJsonCandidate).toList(growable: false),
    };

    if (_initiator) {
      // Call initiator sends ice candidates to GAE server.
      if (_roomState != ConnectionState.CONNECTED) {
        _reportError("Sending ICE candidate removals in non connected state.");
        return;
      }
      _sendPostMessage(MessageType.MESSAGE, _messageUrl, jsonEncode(json));
      if (_connectionParameters.loopback) {
        _events.onRemoteIceCandidatesRemoved(candidates);
      }
    } else {
      // Call receiver sends ice candidates to websocket server.
      _wsClient.send(jsonEncode(json));
    }
  }

  // --------------------------------------------------------------------
  // WebSocketChannelEvents interface implementation.
  // All events are called by WebSocketChannelClient on a local looper thread
  // (passed to WebSocket client constructor).
  void onWebSocketMessage(final String msg) {
    if (_wsClient.state != WebSocketConnectionState.REGISTERED) {
      print("e $_ Got WebSocket message in non registered state.");
      return;
    }
    var json = jsonDecode(msg);
    String msgText = json["msg"];
    String errorText = json["error"];
    if (msgText.length > 0) {
      json = jsonDecode(msgText);
      String type = json.optString("type");
      if (type == "candidate") {
        _events.onRemoteIceCandidate(_toDartCandidate(json));
      } else if (type == "remove-candidates") {
        var candidateArray = json["candidates"];
        List<RTCIceCandidate> candidates = [];
        for (int i = 0; i < candidateArray.length(); ++i) {
          candidates[i] = _toDartCandidate(candidateArray.getJSONObject(i));
        }
        _events.onRemoteIceCandidatesRemoved(candidates);
      } else if (type == "answer") {
        if (_initiator) {
          RTCSessionDescription sdp =
              new RTCSessionDescription(type, json["sdp"]);
          _events.onRemoteDescription(sdp);
        } else {
          _reportError("Received answer for call initiator: " + msg);
        }
      } else if (type == "offer") {
        if (!_initiator) {
          RTCSessionDescription sdp =
              new RTCSessionDescription(type, json["sdp"]);
          _events.onRemoteDescription(sdp);
        } else {
          _reportError("Received offer for call receiver: " + msg);
        }
      } else if (type == "bye") {
        _events.onChannelClose();
      } else {
        _reportError("Unexpected WebSocket message: " + msg);
      }
    } else {
      if (errorText != null && errorText.length > 0) {
        _reportError("WebSocket error message: " + errorText);
      } else {
        _reportError("Unexpected WebSocket message: " + msg);
      }
    }
  }

  void onWebSocketClose() {
    _events.onChannelClose();
  }

  void onWebSocketError(String description) {
    _reportError("WebSocket error: " + description);
  }

  // --------------------------------------------------------------------
  // Helper functions.
  void _reportError(final String errorMessage) {
    print("e $_ $errorMessage");

    if (_roomState != ConnectionState.ERROR) {
      _roomState = ConnectionState.ERROR;
      _events.onChannelError(errorMessage);
    }
  }

  // Send SDP or ICE candidate to a room server.
  void _sendPostMessage(final MessageType messageType, final String url,
      final String message) async {
    String logInfo = url;
    if (message != null) {
      logInfo += ". Message: " + message;
    }
    print("d $_ C->GAE: " + logInfo);
    try {
      final req = await HttpClient().openUrl("POST", Uri.parse(url));

      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) {
        throw Exception("Non-200 response to POST to URL: " +
            url +
            " : " +
            req.headers?.toString());
      }
      if (messageType == MessageType.MESSAGE) {
        final roomJson =
            jsonDecode(await resp.transform(utf8.decoder).join("\\A"));
        String result = roomJson["result"];
        if (result != "SUCCESS") {
          _reportError("GAE POST error: $result");
        }
      }
    } catch (e) {
      _reportError("GAE POST error: " + e.message);
    }
  }

  // Converts a Java candidate to a JSONObject.
  Map<String, dynamic> _toJsonCandidate(final RTCIceCandidate candidate) {
    return {
      "label": candidate.sdpMlineIndex,
      "id": candidate.sdpMid,
      "candidate": candidate.candidate,
    };
  }

  // Converts a JSON candidate to a Java object.
  RTCIceCandidate _toDartCandidate(Map json) {
    return RTCIceCandidate(json["id"], json["label"], json["candidate"]);
  }
}
