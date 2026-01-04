import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing RFID tag rolls in Supabase
class RfidTagRollRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all rolls, optionally filtered by status
  ///
  /// [status] - Optional status filter
  /// [limit] - Maximum number of rolls to return (default 50)
  /// [offset] - Number of rolls to skip for pagination (default 0)
  Future<List<RfidTagRoll>> getRolls({
    RfidTagRollStatus? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      AppLogger.info(
        'Fetching rolls${status != null ? ' with status: ${status.value}' : ''}, limit: $limit, offset: $offset',
      );

      late final List<dynamic> response;

      if (status != null) {
        response = await _supabase
            .from('rfid_tag_rolls')
            .select()
            .eq('status', status.value)
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      } else {
        response = await _supabase
            .from('rfid_tag_rolls')
            .select()
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
      }

      final rolls =
          response.map((json) => RfidTagRoll.fromJson(json)).toList();

      AppLogger.info('Found ${rolls.length} rolls');
      return rolls;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch rolls', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single roll by ID
  Future<RfidTagRoll?> getRollById(String id) async {
    try {
      AppLogger.info('Fetching roll by ID: $id');

      final response = await _supabase
          .from('rfid_tag_rolls')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('Roll not found for ID: $id');
        return null;
      }

      final roll = RfidTagRoll.fromJson(response);
      AppLogger.info('Found roll: ${roll.shortId}');
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch roll by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new roll
  ///
  /// [labelWidthMm] - Label width in millimeters
  /// [labelHeightMm] - Label height in millimeters
  /// [labelCount] - Total labels on the physical roll
  /// [manufacturerUrl] - Optional link to manufacturer listing
  /// [createdBy] - User ID of the creator
  Future<RfidTagRoll> createRoll({
    required double labelWidthMm,
    required double labelHeightMm,
    required int labelCount,
    String? manufacturerUrl,
    String? createdBy,
  }) async {
    try {
      AppLogger.info(
        'Creating roll: ${labelWidthMm}x${labelHeightMm}mm, $labelCount labels',
      );

      final data = {
        'label_width_mm': labelWidthMm,
        'label_height_mm': labelHeightMm,
        'label_count': labelCount,
        'status': RfidTagRollStatus.writing.value,
        'last_printed_position': 0,
        'manufacturer_url': manufacturerUrl,
        'created_by': createdBy,
      };

      final response = await _supabase
          .from('rfid_tag_rolls')
          .insert(data)
          .select()
          .single();

      final roll = RfidTagRoll.fromJson(response);
      AppLogger.info('Roll created successfully: ${roll.id}');
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create roll', error, stackTrace);
      rethrow;
    }
  }

  /// Update roll status
  Future<RfidTagRoll> updateRollStatus(
    String id,
    RfidTagRollStatus status,
  ) async {
    try {
      AppLogger.info('Updating roll $id status to ${status.value}');

      final response = await _supabase
          .from('rfid_tag_rolls')
          .update({'status': status.value})
          .eq('id', id)
          .select()
          .single();

      final roll = RfidTagRoll.fromJson(response);
      AppLogger.info('Roll status updated: ${roll.shortId} -> ${status.value}');
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update roll status', error, stackTrace);
      rethrow;
    }
  }

  /// Update last printed position
  ///
  /// Used during batch printing to track progress
  Future<RfidTagRoll> updateLastPrintedPosition(
    String id,
    int position,
  ) async {
    try {
      AppLogger.info('Updating roll $id last printed position to $position');

      final response = await _supabase
          .from('rfid_tag_rolls')
          .update({'last_printed_position': position})
          .eq('id', id)
          .select()
          .single();

      final roll = RfidTagRoll.fromJson(response);
      AppLogger.info(
        'Roll print position updated: ${roll.shortId} -> $position',
      );
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update roll print position', error, stackTrace);
      rethrow;
    }
  }

  /// Mark roll as ready to print
  ///
  /// Sets status to ready_to_print
  Future<RfidTagRoll> markReadyToPrint(String id) async {
    return updateRollStatus(id, RfidTagRollStatus.readyToPrint);
  }

  /// Start printing a roll
  ///
  /// Sets status to printing
  Future<RfidTagRoll> startPrinting(String id) async {
    return updateRollStatus(id, RfidTagRollStatus.printing);
  }

  /// Complete a roll
  ///
  /// Sets status to completed
  Future<RfidTagRoll> completeRoll(String id) async {
    return updateRollStatus(id, RfidTagRollStatus.completed);
  }

  /// Get tags for a specific roll, ordered by position
  Future<List<RfidTag>> getTagsForRoll(String rollId) async {
    try {
      AppLogger.info('Fetching tags for roll: $rollId');

      final response = await _supabase
          .from('rfid_tags')
          .select()
          .eq('roll_id', rollId)
          .order('roll_position', ascending: true);

      final tags =
          (response as List).map((json) => RfidTag.fromJson(json)).toList();

      AppLogger.info('Found ${tags.length} tags for roll');
      return tags;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch tags for roll', error, stackTrace);
      rethrow;
    }
  }

  /// Get count of tags written to a roll
  Future<int> getTagCountForRoll(String rollId) async {
    try {
      AppLogger.info('Getting tag count for roll: $rollId');

      final response = await _supabase
          .from('rfid_tags')
          .select('id')
          .eq('roll_id', rollId);

      final count = (response as List).length;
      AppLogger.info('Roll has $count tags');
      return count;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get tag count for roll', error, stackTrace);
      rethrow;
    }
  }

  /// Get the next position number for a roll
  ///
  /// Returns 1 if no tags exist, otherwise max(roll_position) + 1
  Future<int> getNextPositionForRoll(String rollId) async {
    try {
      AppLogger.info('Getting next position for roll: $rollId');

      final response = await _supabase
          .from('rfid_tags')
          .select('roll_position')
          .eq('roll_id', rollId)
          .order('roll_position', ascending: false)
          .limit(1);

      if ((response as List).isEmpty) {
        AppLogger.info('No existing tags, next position is 1');
        return 1;
      }

      final maxPosition = response[0]['roll_position'] as int;
      final nextPosition = maxPosition + 1;
      AppLogger.info('Next position for roll: $nextPosition');
      return nextPosition;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get next position for roll', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a roll and disassociate its tags
  ///
  /// Tags are NOT deleted, just their roll_id and roll_position are cleared
  Future<void> deleteRoll(String id) async {
    try {
      AppLogger.info('Deleting roll: $id');

      // First, clear roll association from tags
      await _supabase
          .from('rfid_tags')
          .update({'roll_id': null, 'roll_position': null})
          .eq('roll_id', id);

      // Then delete the roll
      await _supabase.from('rfid_tag_rolls').delete().eq('id', id);

      AppLogger.info('Roll deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete roll', error, stackTrace);
      rethrow;
    }
  }

  /// Get count of rolls, optionally filtered by status
  Future<int> getRollCount({RfidTagRollStatus? status}) async {
    try {
      AppLogger.info(
        'Getting roll count${status != null ? ' for status: ${status.value}' : ''}',
      );

      late final List<dynamic> response;

      if (status != null) {
        response = await _supabase
            .from('rfid_tag_rolls')
            .select('id')
            .eq('status', status.value);
      } else {
        response = await _supabase.from('rfid_tag_rolls').select('id');
      }

      final count = response.length;
      AppLogger.info('Roll count: $count');
      return count;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get roll count', error, stackTrace);
      rethrow;
    }
  }
}
