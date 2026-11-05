import 'package:flutter/material.dart';
import '../services/cabinet_service.dart';

class CabinetLocationPicker extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const CabinetLocationPicker({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<CabinetLocationPicker> createState() => _CabinetLocationPickerState();
}

class _CabinetLocationPickerState extends State<CabinetLocationPicker> {
  List<String> _cabinetNames = [];
  bool _loading = true;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
    _loadCabinets();
  }

  Future<void> _loadCabinets() async {
    final names = await CabinetService().fetchCabinetNames();
    if (mounted) {
      setState(() {
        _cabinetNames = names;
        _loading = false;
        // If initial value isn't in the list, keep it as freeform text
        if (_selected != null && !names.contains(_selected)) {
          _cabinetNames = [_selected!, ...names];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(_selected),
          initialValue: _selected,
          decoration: InputDecoration(
            labelText: 'Cabinet Location (optional)',
            hintText: 'Where is this document filed?',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: theme.colorScheme.surface,
            prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _selected != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear',
                        onPressed: widget.enabled
                            ? () {
                                setState(() => _selected = null);
                                widget.onChanged(null);
                              }
                            : null,
                      )
                    : null,
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Not assigned', style: TextStyle(color: Colors.grey)),
            ),
            ..._cabinetNames.map((name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                )),
          ],
          onChanged: widget.enabled
              ? (value) {
                  setState(() => _selected = value);
                  widget.onChanged(value);
                }
              : null,
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              'Document will be linked to $_selected',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
            ),
          ),
      ],
    );
  }
}
