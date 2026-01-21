import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';

Future<bool> confirmAndDeleteRecord(BuildContext context, Document document, CachedDocumentService service) async {
  final TextEditingController controller = TextEditingController();
  bool? result;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Are you sure you want to delete the document "${document.title ?? document.code}"?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Type "y" to confirm or "n" to cancel',
                border: OutlineInputBorder(),
              ),
              maxLength: 1,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final input = controller.text.trim().toLowerCase();
              if (input == 'y') {
                result = true;
                Navigator.of(context).pop();
              } else if (input == 'n') {
                result = false;
                Navigator.of(context).pop();
              }
            },
            child: const Text('Submit'),
          ),
        ],
      );
    },
  );

  if (result == true) {
    try {
      await service.deleteDocument(document.code);
      return true;
    } catch (e) {
      // Handle error - could show snackbar
      print('Error deleting document: $e');
      return false;
    }
  }

  return false;
}
