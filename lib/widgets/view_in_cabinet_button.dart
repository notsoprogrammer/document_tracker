import 'package:flutter/material.dart';
import '../models/document.dart';
import '../screens/cabinet_screen.dart';
import '../services/cabinet_service.dart';

/// Opens the Cabinet Library filtered down to this document's entry.
///
/// Renders nothing when the document has no cabinet assigned. Before
/// navigating it makes sure the cabinet entry exists, so documents filed
/// before document↔cabinet linking existed still resolve to an item.
class ViewInCabinetButton extends StatefulWidget {
  final Document document;
  final double iconSize;

  const ViewInCabinetButton({
    super.key,
    required this.document,
    this.iconSize = 18,
  });

  @override
  State<ViewInCabinetButton> createState() => _ViewInCabinetButtonState();
}

class _ViewInCabinetButtonState extends State<ViewInCabinetButton> {
  bool _busy = false;

  Future<void> _open() async {
    final cabinet = widget.document.cabinetLocation?.trim();
    if (cabinet == null || cabinet.isEmpty || _busy) return;

    setState(() => _busy = true);
    final linked = await CabinetService().linkDocument(
      cabinetName: cabinet,
      documentCode: widget.document.code,
      documentTitle: widget.document.title,
      folderTitle: widget.document.folderTitle,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        // If the entry couldn't be created (offline), fall back to the cabinet itself
        builder: (_) => CabinetScreen(initialSearch: linked ? widget.document.code : cabinet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cabinet = widget.document.cabinetLocation?.trim();
    if (cabinet == null || cabinet.isEmpty) return const SizedBox.shrink();

    return IconButton(
      icon: _busy
          ? SizedBox(
              width: widget.iconSize,
              height: widget.iconSize,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.inventory_2_outlined, size: widget.iconSize),
      tooltip: 'View in $cabinet',
      onPressed: _busy ? null : _open,
    );
  }
}
