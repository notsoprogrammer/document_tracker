import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../services/cached_activity_service.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/snackbar_utils.dart';

class AddActivityScreen extends StatefulWidget {
  final Activity? initialActivity;
  const AddActivityScreen({super.key, this.initialActivity});

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  final titleController = TextEditingController();
  DateTime? selectedStartDate;
  TimeOfDay? selectedStartTime;
  DateTime? selectedEndDate;
  TimeOfDay? selectedEndTime;
  final peopleInvolvedController = TextEditingController();
  final remarksController = TextEditingController();
  final personController = TextEditingController();
  final linkedDocumentCodeController = TextEditingController();
  List<DateTime> extraDates = [];

  bool _isSaving = false;
  bool _showValidationErrors = false;
  bool isAllDay = false;

  bool get _isEditing => widget.initialActivity != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _prefillFromActivity(widget.initialActivity!);
    } else {
      _loadUsername();
    }
  }

  void _prefillFromActivity(Activity a) {
    titleController.text = a.title ?? '';
    selectedStartDate = DateTime(a.startTime.year, a.startTime.month, a.startTime.day);
    selectedStartTime = TimeOfDay(hour: a.startTime.hour, minute: a.startTime.minute);
    isAllDay = a.startTime.hour == 0 && a.startTime.minute == 0;
    if (a.endTime != null) {
      selectedEndDate = DateTime(a.endTime!.year, a.endTime!.month, a.endTime!.day);
      selectedEndTime = TimeOfDay(hour: a.endTime!.hour, minute: a.endTime!.minute);
    }
    peopleInvolvedController.text = a.peopleInvolved;
    remarksController.text = a.remarks;
    personController.text = a.person;
    linkedDocumentCodeController.text = a.linkedDocumentCode ?? '';
    extraDates = List<DateTime>.from(a.extraDates);
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty && mounted) {
      setState(() => personController.text = username);
    }
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Exit'),
        content: const Text('Do you want to exit?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _pickExtraDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final normalized = DateTime(date.year, date.month, date.day);
    final alreadyExists = extraDates.any(
      (d) => d.year == normalized.year && d.month == normalized.month && d.day == normalized.day,
    );
    if (!alreadyExists) setState(() => extraDates.add(normalized));
  }

  Future<void> _saveActivity() async {
    setState(() => _showValidationErrors = true);

    if (titleController.text.trim().isEmpty ||
        selectedStartDate == null ||
        (!isAllDay && selectedStartTime == null) ||
        peopleInvolvedController.text.trim().isEmpty ||
        personController.text.trim().isEmpty) {
      return;
    }

    final startTime = DateTime(
      selectedStartDate!.year,
      selectedStartDate!.month,
      selectedStartDate!.day,
      isAllDay ? 0 : selectedStartTime!.hour,
      isAllDay ? 0 : selectedStartTime!.minute,
    );

    DateTime? endTime;
    if (selectedEndDate != null && selectedEndTime != null) {
      endTime = DateTime(
        selectedEndDate!.year,
        selectedEndDate!.month,
        selectedEndDate!.day,
        selectedEndTime!.hour,
        selectedEndTime!.minute,
      );
    }

    setState(() => _isSaving = true);
    try {
      final docCode = linkedDocumentCodeController.text.trim();
      if (_isEditing) {
        final updates = {
          'title': titleController.text.trim(),
          'start_time': startTime.toIso8601String(),
          'end_time': endTime?.toIso8601String(),
          'people_involved': peopleInvolvedController.text.trim(),
          'remarks': remarksController.text.trim(),
          'extra_dates': extraDates.map((d) => d.toIso8601String()).toList(),
          'linked_document_code': docCode.isEmpty ? null : docCode,
        };
        await SupabaseService().updateActivity(widget.initialActivity!.id!, updates);

        final updated = widget.initialActivity!.copyWith(
          title: titleController.text.trim(),
          startTime: startTime,
          endTime: endTime,
          peopleInvolved: peopleInvolvedController.text.trim(),
          remarks: remarksController.text.trim(),
          extraDates: extraDates,
          linkedDocumentCode: docCode.isEmpty ? null : docCode,
        );
        NotificationService().scheduleActivityReminder(updated);
        _scheduleExtraDateReminders(updated);
      } else {
        final activity = Activity(
          title: titleController.text.trim(),
          startTime: startTime,
          endTime: endTime,
          peopleInvolved: peopleInvolvedController.text.trim(),
          remarks: remarksController.text.trim(),
          person: personController.text.trim(),
          extraDates: extraDates,
          linkedDocumentCode: docCode.isEmpty ? null : docCode,
        );
        await CachedActivityService().createActivity(activity);
        NotificationService().scheduleActivityReminder(activity);
        _scheduleExtraDateReminders(activity);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      SnackbarUtils.showErrorSnackBar(context, 'Failed to save activity: $e');
      setState(() => _isSaving = false);
    }
  }

  void _scheduleExtraDateReminders(Activity activity) {
    for (final extraDate in activity.extraDates) {
      final extraDt = DateTime(
        extraDate.year, extraDate.month, extraDate.day,
        activity.startTime.hour, activity.startTime.minute,
      );
      NotificationService().scheduleActivityReminder(activity.copyWith(startTime: extraDt));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _confirmExit();
        if (!shouldPop || !mounted) return;
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Event' : 'Add Event'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFB3E5FC), Color(0xFF81D4FA), Color.fromARGB(255, 98, 195, 240)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: const Color.fromARGB(255, 28, 28, 28),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Activity details card
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Activity/Event Details",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: titleController,
                          enabled: !_isSaving,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: "Event",
                            hintText: "e.g. Leave, Meetings, Training",
                            hintStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                            ),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && titleController.text.trim().isEmpty
                                ? "Activity title is required"
                                : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: peopleInvolvedController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "People Involved",
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && peopleInvolvedController.text.trim().isEmpty
                                ? "People involved is required"
                                : null,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: remarksController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Remarks",
                            hintText: "Details about the event (e.g., location, purpose)",
                            hintStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                            ),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: linkedDocumentCodeController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Document Reference (Optional)",
                            hintText: "e.g. IDL-MEMO-20260101-163407",
                            hintStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic,
                            ),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Date and time card
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Start Date and Time",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: isAllDay,
                              onChanged: _isSaving
                                  ? null
                                  : (value) => setState(() {
                                        isAllDay = value ?? false;
                                        if (isAllDay) selectedStartTime = null;
                                      }),
                            ),
                            const Text('All Day'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _isSaving
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: selectedStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                                  );
                                  if (date == null) return;
                                  if (!context.mounted) return;
                                  if (!isAllDay) {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: selectedStartTime ?? const TimeOfDay(hour: 9, minute: 0),
                                    );
                                    if (time == null) return;
                                    if (!context.mounted) return;
                                    setState(() {
                                      selectedStartDate = date;
                                      selectedStartTime = time;
                                    });
                                  } else {
                                    setState(() {
                                      selectedStartDate = date;
                                      selectedStartTime = const TimeOfDay(hour: 0, minute: 0);
                                    });
                                  }
                                },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: isAllDay ? "Start Date" : "Start Date and Time",
                              hintText: isAllDay ? "Select date" : "Select date and time",
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              suffixIcon: const Icon(Icons.calendar_today),
                              errorText: _showValidationErrors && selectedStartDate == null
                                  ? (isAllDay ? "Start date is required" : "Start date and time is required")
                                  : null,
                            ),
                            child: Text(
                              selectedStartDate != null
                                  ? isAllDay
                                      ? "${selectedStartDate!.month}/${selectedStartDate!.day}/${selectedStartDate!.year}"
                                      : (selectedStartTime != null
                                          ? "${selectedStartDate!.month}/${selectedStartDate!.day}/${selectedStartDate!.year} ${selectedStartTime!.hour.toString().padLeft(2, '0')}:${selectedStartTime!.minute.toString().padLeft(2, '0')}"
                                          : '')
                                  : '',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "End Date and Time (Optional)",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _isSaving
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: selectedEndDate ?? selectedStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                                  );
                                  if (date == null) return;
                                  if (!context.mounted) return;
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: selectedEndTime ?? const TimeOfDay(hour: 17, minute: 0),
                                  );
                                  if (time == null) return;
                                  if (!context.mounted) return;
                                  setState(() {
                                    selectedEndDate = date;
                                    selectedEndTime = time;
                                  });
                                },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: "End Date and Time (Optional)",
                              hintText: "Select date and time",
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              suffixIcon: selectedEndDate != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () => setState(() {
                                        selectedEndDate = null;
                                        selectedEndTime = null;
                                      }),
                                    )
                                  : null,
                            ),
                            child: Text(
                              selectedEndDate != null && selectedEndTime != null
                                  ? "${selectedEndDate!.month}/${selectedEndDate!.day}/${selectedEndDate!.year} ${selectedEndTime!.hour.toString().padLeft(2, '0')}:${selectedEndTime!.minute.toString().padLeft(2, '0')}"
                                  : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Extra dates card
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Additional Dates (Optional)",
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _isSaving ? null : _pickExtraDate,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Date'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "For recurring events on non-consecutive dates (e.g., cleanup drive on multiple days)",
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (extraDates.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: extraDates.map((date) {
                              final label = "${date.month}/${date.day}/${date.year}";
                              return Chip(
                                label: Text(label, style: const TextStyle(fontSize: 13)),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: _isSaving ? null : () => setState(() => extraDates.remove(date)),
                                backgroundColor: const Color(0xFFB3E5FC),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveActivity,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    backgroundColor: const Color(0xFF81D4FA),
                    foregroundColor: Colors.black87,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEditing ? "Save Changes" : "Save Activity",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
