import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/webrtc.dart';

import 'apprtc_client.dart';

///
/// AsyncTask that converts an AppRTC room URL into the set of signaling
/// parameters to use with that room.
///
class RoomParametersFetcher {
  static const String _ = "RoomRTCClient";
  static const int _TURN_HTTP_TIMEOUT_MS = 5000;

  final String _roomUrl;
  final String _roomMessage;
  final HttpClient _httpClient;

  RoomParametersFetcher(this._roomUrl, this._roomMessage)
      : _httpClient = HttpClient();

  Future<SignalingParameters> makeRequest() async {
    print("d $_ Connecting to room: $_roomUrl");

    try {
      final req = await _httpClient.openUrl("POST", Uri.parse(_roomUrl));
      if (_roomMessage != null) {
        req.add(utf8.encode(_roomMessage));
      }
      final resp = await req.close();

      if (resp.statusCode != HttpStatus.ok) {
        throw Exception("Non-200 response to POST to URL: $_roomUrl : " +
            resp.headers?.toString());
      }

      final body = await resp.transform(utf8.decoder).join();
      return _roomHttpResponseParse(body);
    } catch (e, s) {
      print("e $_ Room connection error: $e\n$s");
      return Future.error(e);
    }
  }

  Future<SignalingParameters> _roomHttpResponseParse(String response) async {
    print("d $_ Room response: " + response);
    try {
      List<RTCIceCandidate> iceCandidates;
      RTCSessionDescription offerSdp;
      var roomJson = jsonDecode(response);

      String result = roomJson["result"];
      if (result != "SUCCESS") {
        throw Exception("Room response error: " + result);
      }

      roomJson = roomJson["params"];
      String roomId = roomJson["room_id"];
      String clientId = roomJson["client_id"];
      String wssUrl = roomJson["wss_url"];
      String wssPostUrl = roomJson["wss_post_url"];
      bool initiator = _parseBool(roomJson["is_initiator"]);
      if (!initiator) {
        iceCandidates = [];
        var messages = roomJson["messages"];
        for (int i = 0; i < messages.length; ++i) {
          String messageString = messages[i];
          if (messageString?.isNotEmpty != true) continue;
          var message = jsonDecode(messageString);
          String messageType = message["type"];
          print("d $_ GAE->C #$i : " + messageString);
          if (messageType == "offer") {
            offerSdp = new RTCSessionDescription(message["sdp"], messageType);
          } else if (messageType == "candidate") {
            RTCIceCandidate candidate = new RTCIceCandidate(
                message["candidate"], message["id"], message["label"]);
            iceCandidates.add(candidate);
          } else {
            print("e $_ Unknown message: " + messageString);
          }
        }
      }
      print("d $_ RoomId: $roomId. ClientId: $clientId");
      print("d $_ Initiator: $initiator");
      print("d $_ WSS url: " + wssUrl);
      print("d $_ WSS POST url: " + wssPostUrl);

      List<Map<String, dynamic>> iceServers =
          _iceServersFromPCConfigJSON(roomJson["pc_config"]);
      bool isTurnPresent = false;
      for (Map<String, dynamic> server in iceServers) {
        print("d $_ IceServer: $server");
        for (String uri in server["urls"]) {
          if (uri.startsWith("turn:")) {
            isTurnPresent = true;
            break;
          }
        }
      }
      // Request TURN servers.
      if (!isTurnPresent && !roomJson["ice_server_url"].isEmpty) {
        List<Map<String, dynamic>> turnServers =
            await _requestTurnServers(roomJson["ice_server_url"]);
        for (Map<String, dynamic> turnServer in turnServers) {
          print("d $_ TurnServer: $turnServer");
          iceServers.add(turnServer);
        }
      }

      SignalingParameters params = new SignalingParameters(iceServers,
          initiator, clientId, wssUrl, wssPostUrl, offerSdp, iceCandidates);
      return params;
    } catch (e, s) {
      return Future.error(e, s);
//    events.onSignalingParametersError("Room JSON parsing error: " + e.toString());
    }
  }

  // Requests & returns a TURN ICE Server based on a request URL.  Must be run
  // off the main thread!
  Future<List<Map<String, dynamic>>> _requestTurnServers(String url)
//  throws IOException, JSONException
  async {
    return [
      {
        "url": "turn:49.234.159.207:3478",
        "username": "xiaofa",
        "credential": "123456",
      },
      {"url": "stun:stun.ekiga.net"},
      {"url": "stun:stun.ekiga.net"},
      {"url": "stun:stun.ideasip.com"},
    ];
    List<Map<String, dynamic>> turnServers = [];
    print("d $_ Request TURN from: " + url);
    final req = await _httpClient.openUrl("GET", Uri.parse(url));
    req.headers.add("REFERER", "https://appr.tc");
    final resp = await req.close();

    if (resp.statusCode != HttpStatus.ok) {
      throw Exception("Non-200 response when requesting TURN server from " +
          url +
          " : " +
          resp.headers?.toString());
    }
    String response = await resp.transform(utf8.decoder).join("\\A");

    print("d $_ TURN response: " + response);

    var responseJSON = jsonDecode(response);
    var iceServers = responseJSON["iceServers"];
    for (int i = 0; i < iceServers.length; ++i) {
      var server = iceServers[i];
      var turnUrls = server["urls"];
      String username =
          server.containsKey("username") ? server["username"] : "";
      String credential =
          server.containsKey("credential") ? server["credential"] : "";
      for (int j = 0; j < turnUrls.length(); j++) {
        String turnUrl = turnUrls[j];
        Map<String, dynamic> turnServer = {
          "url": turnUrl,
          "username": username,
          "credential": credential,
        };
        turnServers.add(turnServer);
      }
    }
    return turnServers;
  }

// Return the list of ICE servers described by a WebRTCPeerConnection
// configuration string.
  List<Map<String, dynamic>> _iceServersFromPCConfigJSON(String pcConfig) {
    final json = jsonDecode(pcConfig);
    var servers = json["iceServers"];
    List<Map<String, dynamic>> ret = [];
    for (int i = 0; i < servers.length; ++i) {
      final server = servers[i];
      String url = server["urls"];
      String credential =
          server.containsKey("credential") ? server["credential"] : "";
      Map<String, dynamic> turnServer = {
        "url": url,
        "credential": credential,
      };
      ret.add(turnServer);
    }
    return ret;
  }

  bool _parseBool(var value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value == "true") {
      return true;
    } else if (value == "false") {
      return false;
    }
    throw FormatException("$value is not bool");
  }
}
