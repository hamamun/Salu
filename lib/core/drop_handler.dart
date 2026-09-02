import 'drag_drop_handler.dart';

/// Legacy Phase 2 entry point for drag-and-drop.
///
/// Phase 5 moved the real intelligence into [DragDropHandler]; this thin
/// shim keeps the original call site working and simply forwards to it.
class DropHandler {
  DropHandler._();

  /// Handles a list of dropped file-system paths. Returns a short
  /// human-readable summary, or `null` if nothing usable was dropped.
  static Future<String?> handleDroppedPaths(List<String> paths) async {
    final DropResult result = await DragDropHandler.handle(paths);
    if (!result.handled || result.message.isEmpty) return null;
    return result.message;
  }
}
