import 'package:flutter/material.dart';

class DocumentFilterDialog extends StatefulWidget {
  final DateTime? specificDate;
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(DateTime? specificDate, DateTime? startDate, DateTime? endDate) onApply;

  const DocumentFilterDialog({
    super.key,
    this.specificDate,
    this.startDate,
    this.endDate,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    DateTime? specificDate,
    DateTime? startDate,
    DateTime? endDate,
    required void Function(DateTime? specificDate, DateTime? startDate, DateTime? endDate) onApply,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => DocumentFilterDialog(
        specificDate: specificDate,
        startDate: startDate,
        endDate: endDate,
        onApply: onApply,
      ),
    );
  }

  @override
  State<DocumentFilterDialog> createState() => _DocumentFilterDialogState();
}

class _DocumentFilterDialogState extends State<DocumentFilterDialog> {
  late bool _isRangeMode;
  DateTime? _specificDate;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _specificDate = widget.specificDate;
    _startDate = widget.startDate;
    _endDate = widget.endDate;
    _isRangeMode = widget.startDate != null || widget.endDate != null;
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _applyQuickFilter(String label) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? specific, start, end;
    switch (label) {
      case 'Today':
        specific = today;
      case 'This Week':
        final weekday = today.weekday % 7;
        start = today.subtract(Duration(days: weekday));
        end = today;
      case 'This Month':
        start = DateTime(today.year, today.month, 1);
        end = today;
      case 'Last Month':
        final firstOfThis = DateTime(today.year, today.month, 1);
        end = firstOfThis.subtract(const Duration(days: 1));
        start = DateTime(end.year, end.month, 1);
    }
    widget.onApply(specific, start, end);
    Navigator.pop(context);
  }

  Future<void> _pickSpecificDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _specificDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _specificDate = picked);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  void _apply() {
    if (_isRangeMode) {
      widget.onApply(null, _startDate, _endDate);
    } else {
      widget.onApply(_specificDate, null, null);
    }
    Navigator.pop(context);
  }

  bool get _hasAnyDate =>
      _specificDate != null || _startDate != null || _endDate != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      title: Row(
        children: [
          Icon(Icons.filter_list_rounded, color: colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          const Text(
            'Filter by Date',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (_hasAnyDate)
            TextButton(
              onPressed: () => setState(() {
                _specificDate = null;
                _startDate = null;
                _endDate = null;
              }),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Clear all',
                style: TextStyle(fontSize: 12, color: Colors.orange[400]),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              'QUICK SELECT',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ['Today', 'This Week', 'This Month', 'Last Month'].map((label) {
                return ActionChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _applyQuickFilter(label),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: 'Specific Date',
                    icon: Icons.today_outlined,
                    selected: !_isRangeMode,
                    onTap: () => setState(() => _isRangeMode = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeTab(
                    label: 'Date Range',
                    icon: Icons.date_range_outlined,
                    selected: _isRangeMode,
                    onTap: () => setState(() => _isRangeMode = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_isRangeMode)
              _DateField(
                label: 'Tap to select a date',
                date: _specificDate,
                formatter: _fmt,
                onTap: _pickSpecificDate,
                onClear: _specificDate != null ? () => setState(() => _specificDate = null) : null,
              )
            else ...[
              _DateField(
                label: 'Start date',
                date: _startDate,
                formatter: _fmt,
                onTap: _pickStartDate,
                onClear: _startDate != null ? () => setState(() => _startDate = null) : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.arrow_downward, size: 14, color: Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  Text('to', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 8),
              _DateField(
                label: 'End date',
                date: _endDate,
                formatter: _fmt,
                onTap: _pickEndDate,
                onClear: _endDate != null ? () => setState(() => _endDate = null) : null,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: selected ? color : Colors.grey.withValues(alpha: 0.35),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? color : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String Function(DateTime) formatter;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateField({
    required this.label,
    this.date,
    required this.formatter,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDate = date != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasDate
                ? theme.colorScheme.primary
                : Colors.grey.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(10),
          color: hasDate
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: hasDate ? theme.colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasDate ? formatter(date!) : label,
                style: TextStyle(
                  fontSize: 14,
                  color: hasDate ? theme.colorScheme.onSurface : Colors.grey,
                  fontWeight: hasDate ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
