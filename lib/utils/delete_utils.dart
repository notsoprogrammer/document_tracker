import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';

Future<bool> confirmAndDeleteRecord(BuildContext context, Document document, CachedDocumentService service) async {
  final TextEditingController controller = TextEditingController();
  bool? result;

  // Check if device is online
  final isOnline = await service.isOnline;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final input = controller.text.trim().toLowerCase();
          final canConfirm = input == 'y';
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.delete_forever,
                  color: Colors.red[700],
                ),
                const SizedBox(width: 8),
                const Text('Confirm Deletion'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to delete the document "${document.title ?? document.code}"?',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                // Online/Offline status indicator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green[50] : Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isOnline ? Colors.green[200]! : Colors.orange[200]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnline ? Icons.cloud_done : Icons.cloud_off,
                        size: 20,
                        color: isOnline ? Colors.green[700] : Colors.orange[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOnline
                              ? 'Online: Document will be deleted immediately'
                              : 'Offline: Document will be marked for deletion and synced when online',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOnline ? Colors.green[900] : Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Type "y" to confirm, "n" to cancel',
                    border: OutlineInputBorder(),
                    helperText: 'This action cannot be undone',
                  ),
                  maxLength: 1,
                  onChanged: (value) => setState(() {}),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canConfirm ? () {
                  result = true;
                  Navigator.of(context).pop();
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm Delete'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true) {
    try {
      await service.deleteDocument(document.code);
      
      // Show success message with appropriate context
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOnline
                  ? 'Document "${document.title ?? document.code}" deleted successfully'
                  : 'Document "${document.title ?? document.code}" marked for deletion. Will sync when online.',
            ),
            backgroundColor: isOnline ? Colors.green[700] : Colors.orange[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      return true;
    } catch (e) {
      // Handle error - show snackbar
      print('Error deleting document: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete document: ${e.toString()}'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      return false;
    }
  }

  return false;
}
