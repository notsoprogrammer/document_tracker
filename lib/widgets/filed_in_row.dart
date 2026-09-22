import 'package:flutter/material.dart';
import '../models/document.dart';
import 'view_in_cabinet_button.dart';

/// Where a document physically sits, as one line.
///
/// This used to be two rows — "Location" and "Held by" — each padded out with
/// an apologetic placeholder ("Not assigned", "Not specified") whenever its
/// half was empty, which is most of the time. They are one fact, so they read
/// as one line: whichever parts are recorded, in order, separated by a pipe.
class FiledInRow extends StatelessWidget {
  final Document document;
  final VoidCallback onEditLocation;
  final VoidCallback onEditHolder;

  const FiledInRow({
    super.key,
    required this.document,
    required this.onEditLocation,
    required this.onEditHolder,
  });

  /// The recorded parts, narrowest to broadest: who has it, the folder they
  /// keep it in, the cabinet it belongs to, and that cabinet's folder. Empty
  /// parts are dropped rather than announced.
  static String summarise(Document d) {
    final parts = <String?>[
      d.heldBy,
      d.heldByFolder,
      d.cabinetLocation,
      d.folderTitle,
    ].map((p) => p?.trim() ?? '').where((p) => p.isNotEmpty).toList();

    return parts.isEmpty ? '-' : parts.join('  |  ');
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.inventory_2_outlined, size: 20, color: primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Filed in',
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: primary,
                        fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message:
                        'Held by  |  their folder  |  cabinet  |  cabinet folder',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(Icons.help_outline,
                        size: 13, color: primary.withValues(alpha: 0.6)),
                  ),
                ],
              ),
              Text(summarise(document), style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        ViewInCabinetButton(document: document),
        IconButton(
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          onPressed: onEditLocation,
          tooltip: 'Update Location',
        ),
        IconButton(
          icon: const Icon(Icons.person_pin_outlined, size: 18),
          onPressed: onEditHolder,
          tooltip: 'Update Holder',
        ),
      ],
    );
  }
}
