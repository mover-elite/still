import 'package:livekit_client/livekit_client.dart';

/// Enum for call types
enum CallType { single, group }

/// Connection state change types
enum ConnectionStateType {
  connected,
  disconnected,
  reconnecting,
  reconnected,
}

/// Connection state change event
class ConnectionStateEvent {
  final ConnectionStateType type;
  final DisconnectReason? disconnectReason;

  ConnectionStateEvent(this.type, {this.disconnectReason});
}

/// Participant change types
enum ParticipantChangeType {
  connected,
  disconnected,
}

/// Participant change event
class ParticipantChangeEvent {
  final ParticipantChangeType type;
  final RemoteParticipant participant;

  ParticipantChangeEvent(this.type, this.participant);
}

/// Track state change types
enum TrackStateType {
  muted,
  unmuted,
}

/// Track state change event
class TrackStateEvent {
  final TrackStateType type;
  final TrackPublication publication;

  TrackStateEvent(this.type, this.publication);
}
