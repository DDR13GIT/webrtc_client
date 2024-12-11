import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/webrtc_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

// Add this enum at the top of the file, after the imports
enum CallState {
  disconnected,
  connected,
  incomingCall,
  outgoingCall,
  inCall
}

class CallScreen extends StatefulWidget {
  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  final _webRTCService = WebRTCService();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isInCall = false;
  bool _isMuted = false;
  String _status = 'Disconnected';
  MediaStream? _remoteStream;
  final _ipController = TextEditingController(text: '192.168.0.125');
  late AnimationController _rippleController;
  Duration _callDuration = Duration.zero;
  Timer? _callTimer;
  CallState _callState = CallState.disconnected;
  RTCSessionDescription? _pendingOffer;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat();
    _connectToSignalingServer();
  }

  Future<void> _connectToSignalingServer() async {
    setState(() => _status = 'Connecting...');

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://${_ipController.text}:8080/ws'),
      );

      await _webRTCService.initialize();

      _webRTCService.onIceCandidate = (candidate) {
        _sendMessage({
          'type': 'ice-candidate',
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }
        });
      };

      _webRTCService.onRemoteStream = (stream) {
        setState(() {
          _remoteStream = stream;
          _isInCall = true;
        });
      };

      _channel!.stream.listen(
        (message) => _handleSignalingMessage(jsonDecode(message)),
        onError: (error) {
          setState(() => _status = 'Connection error: $error');
        },
        onDone: () {
          setState(() {
            _status = 'Disconnected';
            _isConnected = false;
          });
        },
      );

      setState(() {
        _isConnected = true;
        _status = 'Connected';
      });
    } catch (e) {
      setState(() => _status = 'Connection failed: $e');
    }
  }

  void _handleSignalingMessage(Map<String, dynamic> message) {
    try {
      developer.log('Received signaling message: ${message['type']}');
      switch (message['type']) {
        case 'offer':
          _handleOffer(message);
          break;
        case 'answer':
          _handleAnswer(message);
          break;
        case 'ice-candidate':
          _handleIceCandidate(message);
          break;
        case 'call-ended':
          _handleRemoteCallEnded();
          break;
      }
    } catch (e, stackTrace) {
      developer.log('Error in _handleSignalingMessage: $e\n$stackTrace');
      setState(() => _status = 'Signaling error: $e');
    }
  }

  // Modify _handleOffer method
  Future<void> _handleOffer(Map<String, dynamic> message) async {
    try {
      // Add this line to reinitialize if needed
      await _webRTCService.reinitialize();
      
      setState(() {
        _status = 'Incoming call...';
        _callState = CallState.incomingCall;
        _pendingOffer = RTCSessionDescription(
          message['sdp']['sdp'],
          message['sdp']['type'],
        );
      });
    } catch (e) {
      developer.log('Error handling offer: $e');
      setState(() => _status = 'Failed to process incoming call');
    }
  }

  // Add new methods for call acceptance/rejection
  Future<void> _acceptCall() async {
    if (_pendingOffer == null) return;

    try {
      setState(() => _status = 'Accepting call...');
      
      final answer = await _webRTCService.handleOffer(_pendingOffer!);
      _sendMessage({
        'type': 'answer',
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        }
      });

      setState(() {
        _isInCall = true;
        _callState = CallState.inCall;
        _status = 'Call connected';
      });
      _startCallTimer();
    } catch (e) {
      setState(() => _status = 'Failed to accept call: $e');
      _endCall();
    }
  }

  void _rejectCall() {
    _pendingOffer = null;
    setState(() {
      _callState = CallState.connected;
      _status = 'Connected';
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> message) async {
    final description = RTCSessionDescription(
      message['sdp']['sdp'],
      message['sdp']['type'],
    );
    await _webRTCService.handleAnswer(description);
    setState(() => _status = 'Call connected');
    _startCallTimer(); // Start timer when call is connected
  }

  void _handleIceCandidate(Map<String, dynamic> message) {
    final candidate = RTCIceCandidate(
      message['candidate']['candidate'],
      message['candidate']['sdpMid'],
      message['candidate']['sdpMLineIndex'],
    );
    _webRTCService.addIceCandidate(candidate);
  }

  // Modify _startCall method
  Future<void> _startCall() async {
    setState(() {
      _status = 'Initiating call...';
      _callState = CallState.outgoingCall;
    });

    try {
      // Add this line to reinitialize if needed
      await _webRTCService.reinitialize();
      
      developer.log('Creating WebRTC offer');
      final offer = await _webRTCService.createOffer();

      developer.log('Sending offer through signaling server');
      _sendMessage({
        'type': 'offer',
        'sdp': {
          'type': offer.type,
          'sdp': offer.sdp,
        }
      });

      setState(() => _status = 'Waiting for answer...');
    } catch (e, stackTrace) {
      developer.log('Error in _startCall: $e\n$stackTrace');
      setState(() => _status = 'Call failed: $e');
      _webRTCService.closeConnection();
    }
  }

  void _toggleMute() {
    _webRTCService.toggleMicrophone();
    setState(() => _isMuted = !_isMuted);
  }

  void _endCall() {
    // Send call-ended signal to remote peer
    _sendMessage({'type': 'call-ended'});
    
    _stopCallTimer();
    _webRTCService.closeConnection();
    setState(() {
      _isInCall = false;
      _callState = CallState.connected;
      _status = 'Connected';
      _remoteStream = null;
    });
  }

  void _handleRemoteCallEnded() {
    if (_isInCall) {
      _stopCallTimer();
      _webRTCService.closeConnection();
      setState(() {
        _isInCall = false;
        _callState = CallState.connected;
        _status = 'Call ended by remote peer';
        _remoteStream = null;
      });
    }
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void _startCallTimer() {
    _callDuration = Duration.zero;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration = Duration(seconds: timer.tick);
      });
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    _callDuration = Duration.zero;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isConnected) _buildConnectionSection(),
              if (_isConnected) Expanded(
                child: _isInCall ? _buildOngoingCallUI() : _buildPreCallUI(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'WebRTC Call',
            style: GoogleFonts.roboto(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _ipController,
              style: GoogleFonts.roboto(),
              decoration: InputDecoration(
                labelText: 'Server IP Address',
                border: InputBorder.none,
                suffixIcon: IconButton(
                  icon: Icon(Icons.connect_without_contact),
                  onPressed: !_isConnected ? _connectToSignalingServer : null,
                ),
              ),
              enabled: !_isConnected,
            ),
          ),
          SizedBox(height: 16),
          Text(
            _status,
            style: GoogleFonts.roboto(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  // Modify _buildPreCallUI to show incoming call UI when needed
  Widget _buildPreCallUI() {
    if (_callState == CallState.incomingCall) {
      return _buildIncomingCallUI();
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Ready to Call',
                style: GoogleFonts.roboto(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _status,
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _startCall,
            icon: Icon(Icons.call),
            label: Text('Start Call'),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  // Add new widget for incoming call UI
  Widget _buildIncomingCallUI() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Incoming Call',
                style: GoogleFonts.roboto(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FilledButton.icon(
                onPressed: _rejectCall,
                icon: Icon(Icons.call_end),
                label: Text('Reject'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
              FilledButton.icon(
                onPressed: _acceptCall,
                icon: Icon(Icons.call),
                label: Text('Accept'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOngoingCallUI() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Icon(
                  Icons.person,
                  size: 64,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Ongoing Call',
                style: GoogleFonts.roboto(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _formatDuration(_callDuration),
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 24),
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  onPressed: _toggleMute,
                ),
                _buildActionButton(
                  icon: Icons.call_end,
                  label: 'End',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: _endCall,
                ),
                _buildActionButton(
                  icon: Icons.volume_up,
                  label: 'Speaker',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final buttonColor = color ?? Theme.of(context).colorScheme.secondary;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: buttonColor.withOpacity(0.1),
          ),
          child: IconButton(
            icon: Icon(icon, color: buttonColor),
            onPressed: onPressed,
            padding: EdgeInsets.all(16),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.roboto(
            color: buttonColor,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _rippleController.dispose();
    _ipController.dispose();
    _webRTCService.dispose();
    _channel?.sink.close();
    super.dispose();
  }
}
