import 'package:saturday_consumer_app/models/room_observation.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Wraps the `mobile_room_observation()` RPC. The RPC returns zero or one
/// row; absence is a valid outcome (the room shows nothing).
class RoomObservationRepository extends BaseRepository {
  Future<RoomObservation?> fetchOne() async {
    final response = await client.rpc('mobile_room_observation');
    final rows = (response as List?) ?? const [];
    if (rows.isEmpty) return null;
    return RoomObservation.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }
}
