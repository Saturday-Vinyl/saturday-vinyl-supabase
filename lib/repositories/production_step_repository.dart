import 'dart:io';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

/// Repository for managing production steps
class ProductionStepRepository {
  final _supabase = SupabaseService.instance.client;
  final _storage = StorageService();
  final _uuid = const Uuid();

  /// Get all production steps for a product, ordered by stepOrder
  Future<List<ProductionStep>> getStepsForProduct(String productId) async {
    try {
      AppLogger.info('Fetching production steps for product: $productId');

      final response = await _supabase
          .from('production_steps')
          .select()
          .eq('product_id', productId)
          .order('step_order', ascending: true);

      final steps = (response as List)
          .map((json) => ProductionStep.fromJson(json))
          .toList();

      AppLogger.info('Fetched ${steps.length} production steps');
      return steps;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch production steps', error, stackTrace);
      rethrow;
    }
  }

  /// Get all production steps for a product with their associated gCode files
  Future<List<ProductionStep>> getStepsForProductWithGCode(String productId) async {
    try {
      AppLogger.info('Fetching production steps with gCode files for product: $productId');

      final response = await _supabase
          .from('production_steps')
          .select('''
            *,
            step_gcode_files (
              *,
              gcode_files (*)
            )
          ''')
          .eq('product_id', productId)
          .order('step_order', ascending: true);

      final steps = (response as List)
          .map((json) => ProductionStep.fromJson(json))
          .toList();

      AppLogger.info('Fetched ${steps.length} production steps with gCode files');
      return steps;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch production steps with gCode files', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new production step
  /// If file is provided, uploads it first then creates step with file URL
  Future<ProductionStep> createStep(ProductionStep step, {File? file}) async {
    String? uploadedFileUrl;

    try {
      AppLogger.info('Creating production step: ${step.name}');

      final stepId = _uuid.v4();
      String? fileUrl = step.fileUrl;
      String? fileName = step.fileName;
      String? fileType = step.fileType;

      // Upload file if provided
      if (file != null) {
        AppLogger.info('Uploading file for production step');
        uploadedFileUrl = await _storage.uploadProductionFile(
          file,
          step.productId,
          stepId,
        );
        fileUrl = uploadedFileUrl;
        fileName = path.basename(file.path);
        fileType = path.extension(file.path);
      }

      final now = DateTime.now();

      // Insert step record into database
      await _supabase.from('production_steps').insert({
        'id': stepId,
        'product_id': step.productId,
        'name': step.name,
        'description': step.description,
        'step_order': step.stepOrder,
        'file_url': fileUrl,
        'file_name': fileName,
        'file_type': fileType,
        'step_type': step.stepType.value,
        'engrave_qr': step.engraveQr,
        'qr_x_offset': step.qrXOffset,
        'qr_y_offset': step.qrYOffset,
        'qr_size': step.qrSize,
        'qr_power_percent': step.qrPowerPercent,
        'qr_speed_mm_min': step.qrSpeedMmMin,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final createdStep = ProductionStep(
        id: stepId,
        productId: step.productId,
        name: step.name,
        description: step.description,
        stepOrder: step.stepOrder,
        fileUrl: fileUrl,
        fileName: fileName,
        fileType: fileType,
        stepType: step.stepType,
        engraveQr: step.engraveQr,
        qrXOffset: step.qrXOffset,
        qrYOffset: step.qrYOffset,
        qrSize: step.qrSize,
        qrPowerPercent: step.qrPowerPercent,
        qrSpeedMmMin: step.qrSpeedMmMin,
        createdAt: now,
        updatedAt: now,
      );

      AppLogger.info('Production step created successfully');
      return createdStep;
    } catch (error, stackTrace) {
      // Rollback: delete uploaded file if step creation failed
      if (uploadedFileUrl != null) {
        try {
          AppLogger.warning('Rolling back file upload due to step creation failure');
          await _storage.deleteProductionFile(uploadedFileUrl);
        } catch (deleteError) {
          AppLogger.error('Failed to rollback file upload', deleteError, StackTrace.current);
        }
      }

      AppLogger.error('Failed to create production step', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing production step
  /// If file is provided, uploads new file and deletes old one
  Future<void> updateStep(
    ProductionStep step, {
    File? file,
    ProductionStep? oldStep,
  }) async {
    String? uploadedFileUrl;

    try {
      AppLogger.info('Updating production step: ${step.id}');

      String? fileUrl = step.fileUrl;
      String? fileName = step.fileName;
      String? fileType = step.fileType;
      String? oldFileUrl = oldStep?.fileUrl;

      // Upload new file if provided
      if (file != null) {
        AppLogger.info('Uploading new file for production step');
        uploadedFileUrl = await _storage.uploadProductionFile(
          file,
          step.productId,
          step.id,
        );
        fileUrl = uploadedFileUrl;
        fileName = path.basename(file.path);
        fileType = path.extension(file.path);
      }

      final now = DateTime.now();

      // Update step record in database
      await _supabase.from('production_steps').update({
        'name': step.name,
        'description': step.description,
        'step_order': step.stepOrder,
        'file_url': fileUrl,
        'file_name': fileName,
        'file_type': fileType,
        'step_type': step.stepType.value,
        'engrave_qr': step.engraveQr,
        'qr_x_offset': step.qrXOffset,
        'qr_y_offset': step.qrYOffset,
        'qr_size': step.qrSize,
        'qr_power_percent': step.qrPowerPercent,
        'qr_speed_mm_min': step.qrSpeedMmMin,
        'updated_at': now.toIso8601String(),
      }).eq('id', step.id);

      // Delete old file if it was replaced
      if (oldFileUrl != null && uploadedFileUrl != null && oldFileUrl != uploadedFileUrl) {
        try {
          AppLogger.info('Deleting old file');
          await _storage.deleteProductionFile(oldFileUrl);
        } catch (deleteError) {
          AppLogger.warning('Failed to delete old file', deleteError);
          // Don't fail the update if old file deletion fails
        }
      }

      AppLogger.info('Production step updated successfully');
    } catch (error, stackTrace) {
      // Rollback: delete uploaded file if step update failed
      if (uploadedFileUrl != null) {
        try {
          AppLogger.warning('Rolling back file upload due to step update failure');
          await _storage.deleteProductionFile(uploadedFileUrl);
        } catch (deleteError) {
          AppLogger.error('Failed to rollback file upload', deleteError, StackTrace.current);
        }
      }

      AppLogger.error('Failed to update production step', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a production step
  /// Also deletes associated file from storage
  Future<void> deleteStep(String stepId) async {
    try {
      AppLogger.info('Deleting production step: $stepId');

      // Get step to find file URL
      final response = await _supabase
          .from('production_steps')
          .select()
          .eq('id', stepId)
          .single();

      final step = ProductionStep.fromJson(response);

      // Delete from database first
      await _supabase.from('production_steps').delete().eq('id', stepId);

      // Delete associated file if exists
      if (step.fileUrl != null) {
        try {
          AppLogger.info('Deleting associated file');
          await _storage.deleteProductionFile(step.fileUrl!);
        } catch (deleteError) {
          AppLogger.warning('Failed to delete associated file', deleteError);
          // Don't fail the delete if file deletion fails
        }
      }

      AppLogger.info('Production step deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete production step', error, stackTrace);
      rethrow;
    }
  }

  /// Reorder production steps
  /// Updates the stepOrder for multiple steps in a single transaction
  Future<void> reorderSteps(String productId, List<String> stepIds) async {
    try {
      AppLogger.info('Reordering ${stepIds.length} production steps for product: $productId');

      // Update each step's order
      for (int i = 0; i < stepIds.length; i++) {
        final stepId = stepIds[i];
        final newOrder = i + 1; // Orders start at 1

        await _supabase.from('production_steps').update({
          'step_order': newOrder,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', stepId);
      }

      AppLogger.info('Production steps reordered successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to reorder production steps', error, stackTrace);
      rethrow;
    }
  }

  /// Get the next available step order for a product
  /// Used when creating new steps
  Future<int> getNextStepOrder(String productId) async {
    try {
      final steps = await getStepsForProduct(productId);
      if (steps.isEmpty) {
        return 1;
      }

      // Find the highest step order and add 1
      final maxOrder = steps.map((s) => s.stepOrder).reduce((a, b) => a > b ? a : b);
      return maxOrder + 1;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get next step order', error, stackTrace);
      rethrow;
    }
  }
}
