import 'package:flutter_webrtc/webrtc.dart';
import 'package:flutter_webrtc/rtc_peerconnection_factory.dart'
    if (dart.library.js) 'package:flutter_webrtc/web/rtc_peerconnection_factory.dart'
    as f;

import 'apprtc_client.dart';

///
/// Peer connection client implementation.
///
/// <p>All public methods are routed to local looper thread.
/// All PeerConnectionEvents callbacks are invoked from the same looper thread.
/// This class is a singleton.
///
class PeerConnectionClient {
  static const String VIDEO_TRACK_ID = "ARDAMSv0";
  static const String AUDIO_TRACK_ID = "ARDAMSa0";
  static const String VIDEO_TRACK_TYPE = "video";

  static const String _ = "PCRTCClient";

  /*private*/
  static const String VIDEO_CODEC_VP8 = "VP8";

  /*private*/
  static const String VIDEO_CODEC_VP9 = "VP9";

  /*private*/
  static const String VIDEO_CODEC_H264 = "H264";

  /*private*/
  static const String VIDEO_CODEC_H264_BASELINE = "H264 Baseline";

  /*private*/
  static const String VIDEO_CODEC_H264_HIGH = "H264 High";

  /*private*/
  static const String AUDIO_CODEC_OPUS = "opus";

  /*private*/
  static const String AUDIO_CODEC_ISAC = "ISAC";

  /*private*/
  static const String VIDEO_CODEC_PARAM_START_BITRATE =
      "x-google-start-bitrate";

  /*private*/
  static const String VIDEO_FLEXFEC_FIELDTRIAL =
      "WebRTC-FlexFEC-03-Advertised/Enabled/WebRTC-FlexFEC-03/Enabled/";

  /*private*/
  static const String VIDEO_VP8_INTEL_HW_ENCODER_FIELDTRIAL =
      "WebRTC-IntelVP8/Enabled/";

  /*private*/
  static const String DISABLE_WEBRTC_AGC_FIELDTRIAL =
      "WebRTC-Audio-MinimizeResamplingOnMobile/Enabled/";

  /*private*/
  static const String AUDIO_CODEC_PARAM_BITRATE = "maxaveragebitrate";

  /*private*/
  static const String AUDIO_ECHO_CANCELLATION_CONSTRAINT =
      "googEchoCancellation";

  /*private*/
  static const String AUDIO_AUTO_GAIN_CONTROL_CONSTRAINT =
      "googAutoGainControl";

  /*private*/
  static const String AUDIO_HIGH_PASS_FILTER_CONSTRAINT = "googHighpassFilter";

  /*private*/
  static const String AUDIO_NOISE_SUPPRESSION_CONSTRAINT =
      "googNoiseSuppression";

  /*private*/
  static const String DTLS_SRTP_KEY_AGREEMENT_CONSTRAINT =
      "DtlsSrtpKeyAgreement";

  /*private*/
  static const int HD_VIDEO_WIDTH = 1280;

  /*private*/
  static const int HD_VIDEO_HEIGHT = 720;

  /*private*/
  static const int BPS_IN_KBPS = 1000;

  /*private*/
  static const String RTCEVENTLOG_OUTPUT_DIR_NAME = "rtc_event_log";

  /*private*/
  final PeerConnectionParameters peerConnectionParameters;

  /*private*/
  final PeerConnectionEvents events;

  /*private*/
  RTCPeerConnection peerConnection;

  /*private*/
  MediaStream videoSource;

  /*private*/
  MediaStream audioSource;

  /*private*/
  bool preferIsac;

  /*private*/
  bool isError;

  RTCVideoRenderer _remoteRenderer;
  RTCVideoRenderer _localRenderer;

  /*private*/
  SignalingParameters signalingParameters;

  /*private*/
  int videoWidth;

  /*private*/
  int videoHeight;

  /*private*/
  int videoFps;

  /*private*/
  Map<String, dynamic> audioConstraints;

  /*private*/
  Map<String, dynamic> sdpMediaConstraints;

  // Queued remote ICE candidates are consumed only after both local and
  // remote descriptions are set. Similarly local ICE candidates are sent to
  // remote peer after both local and remote description are set.
  /*private*/
  List<RTCIceCandidate> queuedRemoteCandidates;
  bool isInitiator;

  /*private*/
  RTCSessionDescription localSdp; // either offer or answer SDP

  /*private*/
  RTCDataChannel dataChannel;

  /*private*/
  final bool dataChannelEnabled;

  PeerConnectionClient(this.peerConnectionParameters, this.events)
      : dataChannelEnabled =
            peerConnectionParameters._dataChannelParameters != null {
    print("D $_ Preferred video codec: " +
        getSdpVideoCodecName(peerConnectionParameters));
    isInitiator = false;
    // Check if ISAC is used by default.
    preferIsac = peerConnectionParameters.audioCodec != null &&
        peerConnectionParameters.audioCodec == AUDIO_CODEC_ISAC;
  }

  Future<void> createPeerConnection(
      final RTCVideoRenderer remoteRenderer,
      final RTCVideoRenderer localRenderer,
      final SignalingParameters signalingParameters) {
    if (peerConnectionParameters == null) {
      print("E $_ Creating peer connection without initializing factory.");
      return Future.value();
    }
    this.localSdp = null;
    this.isError = false;
    this._remoteRenderer = remoteRenderer;
    this._localRenderer = localRenderer;
    this.signalingParameters = signalingParameters;

    _createMediaConstraintsInternal();
    return _createPeerConnectionInternal();
  }

  void close() {
    closeInternal();
  }

  bool _isVideoCallEnabled() {
    return peerConnectionParameters
        .videoCallEnabled /* && videoCapturer != null*/;
  }

  Future<void> createOffer() {
    if (peerConnection != null && !isError) {
      print("D $_ PC Create OFFER");
      return peerConnection
          .createOffer(sdpMediaConstraints)
          .then(_onCreateSuccess)
          .catchError(_onCreateFailure);
    }
    return Future.error("Already on error");
  }

  Future<void> createAnswer() {
    if (peerConnection != null && !isError) {
      print("D $_ PC create ANSWER");
      isInitiator = false;
      return peerConnection
          .createAnswer(sdpMediaConstraints)
          .then(_onCreateSuccess)
          .catchError(_onCreateFailure);
    }
    return Future.error("Already on error");
  }

  Future<void> addRemoteIceCandidate(final RTCIceCandidate candidate) {
    if (peerConnection != null && !isError) {
      if (queuedRemoteCandidates != null) {
        queuedRemoteCandidates.add(candidate);
      } else {
        return peerConnection.addCandidate(candidate);
      }
    }
    return Future.value();
  }

  Future<void> removeRemoteIceCandidates(
      final List<RTCIceCandidate> candidates) {
    if (peerConnection == null || isError) {
      return Future.error("Already on error");
    }
    // Drain the queued remote candidates if there is any so that
    // they are processed in the proper order.
    drainCandidates();
//    peerConnection.removeCandidates(candidates);
    return Future.value();
  }

  Future<void> setRemoteDescription(final RTCSessionDescription sdp) {
    if (peerConnection == null || isError) {
      return Future.error("Already on error");
    }
    String sdpDescription = sdp.sdp;
    if (preferIsac) {
      sdpDescription = preferCodec(sdpDescription, AUDIO_CODEC_ISAC, true);
    }
    if (_isVideoCallEnabled()) {
      sdpDescription = preferCodec(sdpDescription,
          getSdpVideoCodecName(peerConnectionParameters), false);
    }
    if (peerConnectionParameters.audioStartBitrate > 0) {
      sdpDescription = setStartBitrate(AUDIO_CODEC_OPUS, false, sdpDescription,
          peerConnectionParameters.audioStartBitrate);
    }
    print("D $_ Set remote SDP.");
    RTCSessionDescription sdpRemote =
        new RTCSessionDescription(sdpDescription, sdp.type);
    return peerConnection
        .setRemoteDescription(sdpRemote)
        .then((_) => _onSetSuccess())
        .catchError(_onSetFailure);
  }

  void _reportError(final String errorMessage) {
    print("E $_ PeerConnection error: " + errorMessage);
    if (!isError) {
      events.onPeerConnectionError(errorMessage);
      isError = true;
    }
  }

  void _createMediaConstraintsInternal() {
    // Create video constraints if video call is enabled.
    if (_isVideoCallEnabled()) {
      videoWidth = peerConnectionParameters.videoWidth;
      videoHeight = peerConnectionParameters.videoHeight;
      videoFps = peerConnectionParameters.videoFps;

      // If video resolution is not specified, default to HD.
      if (videoWidth == 0 || videoHeight == 0) {
        videoWidth = HD_VIDEO_WIDTH;
        videoHeight = HD_VIDEO_HEIGHT;
      }

      // If fps is not specified, default to 30.
      if (videoFps == 0) {
        videoFps = 30;
      }
      print("D $_ Capturing format: ${videoWidth}x$videoHeight@$videoFps");
    }

    // Create audio constraints.
    audioConstraints = <String, dynamic>{
      // added for audio performance measurements
      if (peerConnectionParameters.noAudioProcessing)
        "mandatory": {
          AUDIO_ECHO_CANCELLATION_CONSTRAINT: "false",
          AUDIO_AUTO_GAIN_CONTROL_CONSTRAINT: "false",
          AUDIO_HIGH_PASS_FILTER_CONSTRAINT: "false",
          AUDIO_NOISE_SUPPRESSION_CONSTRAINT: "false",
        }
      else
        "mandatory": {},
      "optional": [],
    };

    // Create SDP constraints.
    sdpMediaConstraints = <String, dynamic>{
      "mandatory": {
        "OfferToReceiveAudio": "true",
        "OfferToReceiveVideo": _isVideoCallEnabled().toString(),
      },
      "optional": [],
    };
  }

  Future<void> _createPeerConnectionInternal() async {
    if (isError) {
      print("E $_ PeerConnection factory is not created");
      return;
    }
    print("D $_ Create peer connection.");
    queuedRemoteCandidates = [];

    Map<String, dynamic> configuration = {
      "iceServers": signalingParameters.iceServers,
    };
    peerConnection = await f.createPeerConnection(configuration, {});
    peerConnection.onIceCandidate = events.onIceCandidate;
    peerConnection.onSignalingState = (state) {
      print("D $_ SignalingState: $state");
    };
    peerConnection.onIceConnectionState = (newState) {
      print("D $_ IceConnectionState: $newState");
      if (newState == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        events.onIceConnected();
      } else if (newState ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        events.onIceDisconnected();
      } else if (newState ==
          RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _reportError("ICE connection failed.");
      }
    };
    peerConnection.onIceGatheringState = (newState) {
      print("D $_ IceGatheringState: $newState");
    };
//    peerConnection.onIceGatheringState = (newState) {
//      print("D $_ IceGatheringState: $newState");
//    };
    peerConnection.onAddStream = (stream) {
      print("D $_ onAddStream: $stream");
      _remoteRenderer.srcObject = stream;
    };
    peerConnection.onRemoveStream = (stream) {
      print("D $_ onRemoveStream: $stream");
      stream?.dispose();
      _remoteRenderer.srcObject = null;
    };
    peerConnection.onDataChannel = (dc) {
      print("D $_ New Data channel " /* + dc.label*/);

      if (!dataChannelEnabled) return;

      dc.onDataChannelState = (newState) {
        print(
            "D $_ Data channel state changed: $newState" /* + dc.label() + ": " + dc.state()*/);
      };
      dc.onMessage = (buffer) {
        if (buffer.isBinary) {
          print("D $_ Received binary msg over ");
          return;
        }

//        ByteBuffer data = buffer.data;
//        final byte[] bytes = new byte[data.capacity()];
//        data.get(bytes);
        String strData = buffer.text;
        print("D $_ Got msg: " + strData + " over ");
      };
    };

    if (dataChannelEnabled) {
      print("D $_ Creating data channel....");
      final init = RTCDataChannelInit();
      init.ordered = peerConnectionParameters._dataChannelParameters.ordered;
      init.maxRetransmitTime =
          peerConnectionParameters._dataChannelParameters.maxRetransmitTimeMs;
      init.maxRetransmits =
          peerConnectionParameters._dataChannelParameters.maxRetransmits;
      init.protocol = peerConnectionParameters._dataChannelParameters.protocol;
      init.negotiated =
          peerConnectionParameters._dataChannelParameters.negotiated;
      init.id = peerConnectionParameters._dataChannelParameters.id;
      dataChannel =
          await peerConnection.createDataChannel("ApprtcDemo data", init);
      print("D $_ Data channel created.");
    }

    isInitiator = false;

    if (_isVideoCallEnabled()) {
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
      return navigator.getUserMedia(mediaConstraints).then((media) {
        return peerConnection
            .addStream(_localRenderer.srcObject = videoSource = media);
      });
    }
    print("D $_ Peer connection created.");
  }

  void closeInternal() {
    peerConnection?.dispose();
    peerConnection = null;
    videoSource?.dispose();
    videoSource = null;
    audioSource?.dispose();
    audioSource = null;
    _localRenderer = null;
    _remoteRenderer = null;
    print("D $_ Closing peer connection done.");
    events.onPeerConnectionClosed();
  }

  static String getSdpVideoCodecName(PeerConnectionParameters parameters) {
    switch (parameters.videoCodec) {
      case VIDEO_CODEC_VP8:
        return VIDEO_CODEC_VP8;
      case VIDEO_CODEC_VP9:
        return VIDEO_CODEC_VP9;
      case VIDEO_CODEC_H264_HIGH:
      case VIDEO_CODEC_H264_BASELINE:
        return VIDEO_CODEC_H264;
      default:
        return VIDEO_CODEC_VP8;
    }
  }

  static String getFieldTrials(
      PeerConnectionParameters peerConnectionParameters) {
    String fieldTrials = "";
    if (peerConnectionParameters.videoFlexfecEnabled) {
      fieldTrials += VIDEO_FLEXFEC_FIELDTRIAL;
      print("D $_ Enable FlexFEC field trial.");
    }
    fieldTrials += VIDEO_VP8_INTEL_HW_ENCODER_FIELDTRIAL;
    if (peerConnectionParameters.disableWebRtcAGCAndHPF) {
      fieldTrials += DISABLE_WEBRTC_AGC_FIELDTRIAL;
      print("D $_ Disable WebRTC AGC field trial.");
    }
    return fieldTrials;
  }

  /*private*/
  static String setStartBitrate(
      String codec, bool isVideoCodec, String sdpDescription, int bitrateKbps) {
    List<String> lines = sdpDescription.split("\r\n");
    int rtpmapLineIndex = -1;
    bool sdpFormatUpdated = false;
    String codecRtpMap = null;
    // Search for codec rtpmap in format
    // a=rtpmap:<payload type> <encoding name>/<clock rate> [/<encoding parameters>]
    String regex = "^a=rtpmap:(\d+) " + codec + "(/\d+)+[\r]?\$";

    RegExp codecPattern = RegExp(regex);
    for (int i = 0; i < lines.length; i++) {
      if (codecPattern.hasMatch(lines[i])) {
        Match codecMatcher = codecPattern.firstMatch(lines[i]);
        codecRtpMap = codecMatcher.group(1);
        rtpmapLineIndex = i;
        break;
      }
    }
    if (codecRtpMap == null) {
      print("W $_ No rtpmap for " + codec + " codec");
      return sdpDescription;
    }
    print("D $_ Found " +
        codec +
        " rtpmap " +
        codecRtpMap +
        " at " +
        lines[rtpmapLineIndex]);

    // Check if a=fmtp string already exist in remote SDP for this codec and
    // update it with new bitrate parameter.
    regex = "^a=fmtp:" + codecRtpMap + " \w+=\d+.*[\r]?\$";
    codecPattern = RegExp(regex);
    for (int i = 0; i < lines.length; i++) {
      if (codecPattern.hasMatch(lines[i])) {
        Match codecMatcher = codecPattern.firstMatch(lines[i]);
        print("D $_ Found " + codec + " " + lines[i]);
        if (isVideoCodec) {
          lines[i] += "; " + VIDEO_CODEC_PARAM_START_BITRATE + "=$bitrateKbps";
        } else {
          lines[i] +=
              "; " + AUDIO_CODEC_PARAM_BITRATE + "=${bitrateKbps * 1000}";
        }
        print("D $_ Update remote SDP line: " + lines[i]);
        sdpFormatUpdated = true;
        break;
      }
    }

    String newSdpDescription = "";
    for (int i = 0; i < lines.length; i++) {
      newSdpDescription += (lines[i]) + ("\r\n");
      // Append new a=fmtp line if no such line exist for a codec.
      if (!sdpFormatUpdated && i == rtpmapLineIndex) {
        String bitrateSet;
        if (isVideoCodec) {
          bitrateSet = "a=fmtp:" +
              codecRtpMap +
              " " +
              VIDEO_CODEC_PARAM_START_BITRATE +
              "=$bitrateKbps";
        } else {
          bitrateSet = "a=fmtp:" +
              codecRtpMap +
              " " +
              AUDIO_CODEC_PARAM_BITRATE +
              "=${bitrateKbps * 1000}";
        }
        print("D $_ Add remote SDP line: " + bitrateSet);
        newSdpDescription += (bitrateSet) + ("\r\n");
      }
    }
    return newSdpDescription;
  }

  /// Returns the line number containing "m=audio|video", or -1 if no such line exists.
  /*private*/
  static int findMediaDescriptionLine(bool isAudio, List<String> sdpLines) {
    final String mediaDescription = isAudio ? "m=audio " : "m=video ";
    for (int i = 0; i < sdpLines.length; ++i) {
      if (sdpLines[i].startsWith(mediaDescription)) {
        return i;
      }
    }
    return -1;
  }

  /*private*/
  static String joinString(
      Iterable<String> s, String delimiter, bool delimiterAtEnd) {
    String buf = s.join(delimiter);
    if (delimiterAtEnd) {
      buf += delimiter;
    }
    return buf;
  }

  static String movePayloadTypesToFront(
      List<String> preferredPayloadTypes, String mLine) {
    // The format of the media description line should be: m=<media> <port> <proto> <fmt> ...
    final List<String> origLineParts = mLine.split(" ");
    if (origLineParts.length <= 3) {
      print("E $_ Wrong SDP media description format: " + mLine);
      return null;
    }
    final List<String> header = origLineParts.sublist(0, 3);
    final List<String> unpreferredPayloadTypes =
        origLineParts.sublist(3, origLineParts.length);
    unpreferredPayloadTypes
        .removeWhere((e) => preferredPayloadTypes.contains(e));
    // Reconstruct the line with |preferredPayloadTypes| moved to the beginning of the payload
    // types.
    final List<String> newLineParts = [];
    newLineParts.addAll(header);
    newLineParts.addAll(preferredPayloadTypes);
    newLineParts.addAll(unpreferredPayloadTypes);
    return joinString(newLineParts, " ", false /* delimiterAtEnd */);
  }

  static String preferCodec(String sdpDescription, String codec, bool isAudio) {
    final List<String> lines = sdpDescription.split("\r\n");
    final int mLineIndex = findMediaDescriptionLine(isAudio, lines);
    if (mLineIndex == -1) {
      print("W $_ No mediaDescription line, so can't prefer " + codec);
      return sdpDescription;
    }
    // A list with all the payload types with name |codec|. The payload types are integers in the
    // range 96-127, but they are stored as strings here.
    final List<String> codecPayloadTypes = [];
    // a=rtpmap:<payload type> <encoding name>/<clock rate> [/<encoding parameters>]
    final RegExp codecPattern =
        RegExp("^a=rtpmap:(\d+) " + codec + "(/\d+)+[\r]?\$");
    for (String line in lines) {
      if (codecPattern.hasMatch(line)) {
        Match codecMatcher = codecPattern.firstMatch(line);
        codecPayloadTypes.add(codecMatcher.group(1));
      }
    }
    if (codecPayloadTypes.isEmpty) {
      print("W $_ No payload types with name " + codec);
      return sdpDescription;
    }

    final String newMLine =
        movePayloadTypesToFront(codecPayloadTypes, lines[mLineIndex]);
    if (newMLine == null) {
      return sdpDescription;
    }
    print("D $_ Change media description from: " +
        lines[mLineIndex] +
        " to " +
        newMLine);
    lines[mLineIndex] = newMLine;
    return joinString(lines, "\r\n", true /* delimiterAtEnd */);
  }

  void drainCandidates() {
    if (queuedRemoteCandidates != null) {
      print("D $_ Add ${queuedRemoteCandidates.length} remote candidates");
      for (RTCIceCandidate candidate in queuedRemoteCandidates) {
        peerConnection.addCandidate(candidate);
      }
      queuedRemoteCandidates = null;
    }
  }

  void _onCreateSuccess(final RTCSessionDescription origSdp) async {
    if (localSdp != null) {
      _reportError("Multiple SDP create.");
      return;
    }
    String sdpDescription = origSdp.sdp;
    if (preferIsac) {
      sdpDescription = preferCodec(sdpDescription, AUDIO_CODEC_ISAC, true);
    }
    if (_isVideoCallEnabled()) {
      sdpDescription = preferCodec(sdpDescription,
          getSdpVideoCodecName(peerConnectionParameters), false);
    }
    final RTCSessionDescription sdp =
        new RTCSessionDescription(sdpDescription, origSdp.type);
    localSdp = sdp;
    if (!isError) {
      print("D $_ Set local SDP from " + sdp.type);
      await peerConnection
          .setLocalDescription(sdp)
          .then((_) => _onSetSuccess())
          .catchError(_onSetFailure);
    }
  }

  void _onCreateFailure(e, s) {
    _reportError("createSDP error: $e" + (s != null ? "\n$s" : ""));
  }

  void _onSetSuccess() async {
    if (peerConnection == null || isError) {
      return;
    }
    if (isInitiator) {
      // For offering peer connection we first create offer and set
      // local SDP, then after receiving answer set remote SDP.
      await peerConnection.getRemoteDescription().then((sdp) {
        if (sdp == null) {
          // We've just set our local SDP so time to send it.
          print("D $_ Local SDP set successfully");
          events.onLocalDescription(localSdp);
        } else {
          // We've just set remote description, so drain remote
          // and send local ICE candidates.
          print("D $_ Remote SDP set successfully");
          drainCandidates();
        }
      });
    } else {
      // For answering peer connection we set remote SDP and then
      // create answer and set local SDP.
      await peerConnection.getLocalDescription().then((sdp) {
        if (sdp != null) {
          // We've just set our local SDP so time to send it, drain
          // remote and send local ICE candidates.
          print("D $_ Local SDP set successfully");
          events.onLocalDescription(localSdp);
          drainCandidates();
        } else {
          // We've just set remote SDP - do nothing for now -
          // answer will be created soon.
          print("D $_ Remote SDP set successfully");
        }
      }).catchError((e) {});
    }
  }

  void _onSetFailure(final e, s) {
    _reportError("setSDP error: $e" + (s != null ? "\n$s" : ""));
  }
}

///
/// Peer connection parameters.
///
class DataChannelParameters {
  final bool ordered;
  final int maxRetransmitTimeMs;
  final int maxRetransmits;
  final String protocol;
  final bool negotiated;
  final int id;

  DataChannelParameters({
    this.ordered,
    this.maxRetransmitTimeMs,
    this.maxRetransmits,
    this.protocol,
    this.negotiated,
    this.id,
  });
}

///
/// Peer connection parameters.
///
class PeerConnectionParameters {
  final bool videoCallEnabled;
  final bool loopback;
  final bool tracing;
  final int videoWidth;
  final int videoHeight;
  final int videoFps;
  final int videoMaxBitrate;
  final String videoCodec;
  final bool videoCodecHwAcceleration;
  final bool videoFlexfecEnabled;
  final int audioStartBitrate;
  final String audioCodec;
  final bool noAudioProcessing;
  final bool aecDump;
  final bool saveInputAudioToFile;
  final bool useOpenSLES;
  final bool disableBuiltInAEC;
  final bool disableBuiltInAGC;
  final bool disableBuiltInNS;
  final bool disableWebRtcAGCAndHPF;
  final bool enableRtcEventLog;
  final DataChannelParameters _dataChannelParameters;

  PeerConnectionParameters({
    this.videoCallEnabled,
    this.loopback,
    this.tracing,
    this.videoWidth,
    this.videoHeight,
    this.videoFps,
    this.videoMaxBitrate,
    this.videoCodec,
    this.videoCodecHwAcceleration,
    this.videoFlexfecEnabled,
    this.audioStartBitrate,
    this.audioCodec,
    this.noAudioProcessing,
    this.aecDump,
    this.saveInputAudioToFile,
    this.useOpenSLES,
    this.disableBuiltInAEC,
    this.disableBuiltInAGC,
    this.disableBuiltInNS,
    this.disableWebRtcAGCAndHPF,
    this.enableRtcEventLog,
    DataChannelParameters dataChannelParameters,
  }) : this._dataChannelParameters = dataChannelParameters;
}

///
/// Peer connection events.
///
abstract class PeerConnectionEvents {
  ///
  /// Callback fired once local SDP is created and set.
  ///
  void onLocalDescription(final RTCSessionDescription sdp);

  ///
  /// Callback fired once local Ice candidate is generated.
  ///
  void onIceCandidate(final RTCIceCandidate candidate);

  ///
  /// Callback fired once local ICE candidates are removed.
  ///
  void onIceCandidatesRemoved(final List<RTCIceCandidate> candidates);

  ///
  /// Callback fired once connection is established (IceConnectionState is
  /// CONNECTED).

  void onIceConnected();

  ///
  /// Callback fired once connection is disconnected (IceConnectionState is
  /// DISCONNECTED).
  ///
  void onIceDisconnected();

  ///
  /// Callback fired once DTLS connection is established (PeerConnectionState
  /// is CONNECTED).
  ///
  void onConnected();

  ///
  /// Callback fired once DTLS connection is disconnected (PeerConnectionState
  /// is DISCONNECTED).
  ///
  void onDisconnected();

  ///
  /// Callback fired once peer connection is closed.
  ///
  void onPeerConnectionClosed();

  ///
  /// Callback fired once peer connection statistics is ready.
  ///
  void onPeerConnectionStatsReady(final List<StatsReport> reports);

  ///
  /// Callback fired once peer connection error happened.
  ///
  void onPeerConnectionError(final String description);
}
