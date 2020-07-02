import 'package:flutter_webrtc/webrtc.dart';

/// Struct holding the connection parameters of an AppRTC room.
class RoomConnectionParameters {
  final String roomUrl;
  final String roomId;
  final bool loopback;
  final String urlParameters;

  RoomConnectionParameters(
    this.roomUrl,
    this.roomId,
    this.loopback,
    this.urlParameters,
  );

  RoomConnectionParameters.simple(String roomUrl, String roomId, bool loopback)
      : this(roomUrl, roomId, loopback, null /* urlParameters */);
}

/// Struct holding the signaling parameters of an AppRTC room.
class SignalingParameters {
  final List<Map<String, dynamic>> iceServers;
  final bool initiator;
  final String clientId;
  final String wssUrl;
  final String wssPostUrl;
  final RTCSessionDescription offerSdp;
  final List<RTCIceCandidate> iceCandidates;

  SignalingParameters(
    this.iceServers,
    this.initiator,
    this.clientId,
    this.wssUrl,
    this.wssPostUrl,
    this.offerSdp,
    this.iceCandidates,
  );
}

///
/// Callback interface for messages delivered on signaling channel.
///
/// <p>Methods are guaranteed to be invoked on the UI thread of |activity|.
///
abstract class SignalingEvents {
  ///
  /// Callback fired once the room's signaling parameters
  /// SignalingParameters are extracted.
  ///
  void onConnectedToRoom(final SignalingParameters params);

  ///
  /// Callback fired once remote SDP is received.
  ///
  void onRemoteDescription(final RTCSessionDescription sdp);

  ///
  /// Callback fired once remote Ice candidate is received.
  ///
  void onRemoteIceCandidate(final RTCIceCandidate candidate);

  ///
  /// Callback fired once remote Ice candidate removals are received.
  ///
  void onRemoteIceCandidatesRemoved(final List<RTCIceCandidate> candidates);

  ///
  /// Callback fired once channel is closed.
  ///
  void onChannelClose();

  ///
  /// Callback fired once channel error happened.
  ///
  void onChannelError(final String description);
}

/// AppRTCClient is the interface representing an AppRTC client.
abstract class AppRTCClient {
  ///
  /// Asynchronously connect to an AppRTC room URL using supplied connection
  /// parameters. Once connection is established onConnectedToRoom()
  /// callback with room parameters is invoked.
  ///
  void connectToRoom(RoomConnectionParameters connectionParameters);

  ///
  /// Send offer SDP to the other participant.
  ///
  void sendOfferSdp(final RTCSessionDescription sdp);

  ///
  /// Send answer SDP to the other participant.
  ///
  void sendAnswerSdp(final RTCSessionDescription sdp);

  ///
  /// Send Ice candidate to the other participant.
  ///
  void sendLocalIceCandidate(final RTCIceCandidate candidate);

  ///
  /// Send removed ICE candidates to the other participant.
  ///
  void sendLocalIceCandidateRemovals(final List<RTCIceCandidate> candidates);

  ///
  /// Disconnect from room.
  ///
  void disconnectFromRoom();
}
