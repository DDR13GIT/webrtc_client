import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:developer' as developer;

class WebRTCService {
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  Function(MediaStream)? onRemoteStream;
  Function(RTCIceCandidate)? onIceCandidate;
  RTCSessionDescription? _remoteDescription;

  Future<void> initialize() async {
    try {
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true
        },
        'video': false
      });

      final config = {
        'iceServers': [
          {
            'urls': [
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302'
            ]
          }
        ],
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceTransportPolicy': 'all',
        'enableDtlsSrtp': true,
        'enableRtpDataChannel': true,
      };

      final constraints = {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false
        },
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ]
      };

      peerConnection = await createPeerConnection(config, constraints);

      // Setup ICE handling
      peerConnection?.onIceCandidate = (candidate) {
        developer.log('ICE candidate generated: ${candidate.candidate}');
        if (onIceCandidate != null) {
          onIceCandidate!(candidate);
        }
      };

      // Handle ICE connection state changes
      peerConnection?.onIceConnectionState = (state) {
        developer.log('ICE Connection state changed to: $state');
      };

      // Handle connection state changes
      peerConnection?.onConnectionState = (state) {
        developer.log('Connection state changed to: $state');
      };

      // Add local stream to peer connection
      localStream?.getTracks().forEach((track) {
        developer.log('Adding track: ${track.kind} to peer connection');
        peerConnection?.addTrack(track, localStream!);
      });

      // Handle remote stream
      peerConnection?.onTrack = (event) {
        if (onRemoteStream != null) {
          onRemoteStream!(event.streams[0]);
        }
      };
    } catch (e, stackTrace) {
      developer.log('Error in initialize: $e\n$stackTrace');
      throw Exception('Failed to initialize WebRTC: $e');
    }
  }

  Future<void> reinitialize() async {
    if (peerConnection == null) {
      await initialize();
    }
  }

  Future<RTCSessionDescription> createOffer() async {
    if (peerConnection == null) {
      throw Exception('PeerConnection not initialized');
    }

    try {
      final constraints = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'voiceActivityDetection': true
      };

      final offer = await peerConnection!.createOffer(constraints);
      developer.log('Offer created: ${offer.sdp}');
      
      await peerConnection!.setLocalDescription(offer);
      developer.log('Local description set');
      
      return offer;
    } catch (e, stackTrace) {
      developer.log('Error in createOffer: $e\n$stackTrace');
      throw Exception('Failed to create offer: $e');
    }
  }

  Future<RTCSessionDescription> handleOffer(RTCSessionDescription offer) async {
    if (peerConnection == null) {
      throw Exception('PeerConnection is not initialized');
    }

    try {
      developer.log('Setting remote description from offer');
      await peerConnection!.setRemoteDescription(offer);

      developer.log('Creating answer');
      final answer = await peerConnection!.createAnswer();
      
      developer.log('Setting local description from answer');
      await peerConnection!.setLocalDescription(answer);
      
      return answer;
    } catch (e, stackTrace) {
      developer.log('Error in handleOffer: $e\n$stackTrace');
      throw Exception('Failed to handle offer: $e');
    }
  }

  Future<void> handleAnswer(RTCSessionDescription answer) async {
    _remoteDescription = answer;
    await peerConnection?.setRemoteDescription(answer);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await peerConnection?.addCandidate(candidate);
  }

  void toggleMicrophone() {
    if (localStream != null) {
      final audioTrack = localStream!.getAudioTracks().first;
      audioTrack.enabled = !audioTrack.enabled;
    }
  }

  void closeConnection() {
    localStream?.getTracks().forEach((track) {
      track.stop();
    });
    localStream?.dispose();
    localStream = null;
    
    peerConnection?.close();
    peerConnection = null;
    _remoteDescription = null;
  }

  void dispose() {
    closeConnection();
  }
}