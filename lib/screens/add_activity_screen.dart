import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../services/cached_activity_service.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class AddActivityScreen extends StatefulWidget {
  const AddActivityScreen({super.key});

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

  bool _isSaving = false;
  bool _showValidationErrors = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty) {
      setState(() {
        personController.text = username;
      });
    }
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Exit'),
        content: const Text('Do you want to continue adding or cancel?'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(false), // Continue Adding
            child: const Text('Continue Adding'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true), // Cancel
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Activity'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Activity Details",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: titleController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "Activity Title",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && titleController.text.trim().isEmpty ? "Activity title is required" : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: personController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "Added by",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                            readOnly: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Time",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _isSaving ? null : () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: selectedStartDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (date != null) {
                                      final time = await showTimePicker(
                                        context: context,
                                        initialTime: selectedStartTime ?? const TimeOfDay(hour: 9, minute: 0),
                                      );
                                      if (time != null) {
                                        setState(() {
                                          selectedStartDate = date;
                                          selectedStartTime = time;
                                        });
                                      }
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: "Start Time",
                                      hintText: "Select date and time",
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Theme.of(context).colorScheme.surface,
                                      suffixIcon: const Icon(Icons.calendar_today),
                                      errorText: _showValidationErrors && selectedStartDate == null ? "Start time is required" : null,
                                    ),
                                    child: Text(
                                      selectedStartDate != null && selectedStartTime != null
                                          ? "${selectedStartDate!.month}/${selectedStartDate!.day}/${selectedStartDate!.year} ${selectedStartTime!.hour.toString().padLeft(2, '0')}:${selectedStartTime!.minute.toString().padLeft(2, '0')}"
                                          : '',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: _isSaving ? null : () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: selectedEndDate ?? selectedStartDate ?? DateTime.now(),
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    );
                                    if (date != null) {
                                      final time = await showTimePicker(
                                        context: context,
                                        initialTime: selectedEndTime ?? const TimeOfDay(hour: 17, minute: 0),
                                      );
                                      if (time != null) {
                                        setState(() {
                                          selectedEndDate = date;
                                          selectedEndTime = time;
                                        });
                                      }
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: "End Time",
                                      hintText: "Select date and time",
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Theme.of(context).colorScheme.surface,
                                    ),
                                    child: Text(
                                      selectedEndDate != null && selectedEndTime != null
                                          ? "${selectedEndDate!.month}/${selectedEndDate!.day}/${selectedEndDate!.year} ${selectedEndTime!.hour.toString().padLeft(2, '0')}:${selectedEndTime!.minute.toString().padLeft(2, '0')}"
                                          : '',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Additional Information",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: peopleInvolvedController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "People Involved",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && peopleInvolvedController.text.trim().isEmpty ? "People involved is required" : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: remarksController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "Remarks",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSaving ? null : () async {
                      setState(() {
                        _showValidationErrors = true;
                      });

                      if (titleController.text.trim().isNotEmpty &&
                          selectedStartDate != null &&
                          selectedStartTime != null &&
                          peopleInvolvedController.text.trim().isNotEmpty &&
                          personController.text.trim().isNotEmpty) {

                        final startTime = DateTime(
                          selectedStartDate!.year,
                          selectedStartDate!.month,
                          selectedStartDate!.day,
                          selectedStartTime!.hour,
                          selectedStartTime!.minute,
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

                        final activity = Activity(
                          title: titleController.text.trim(),
                          startTime: startTime,
                          endTime: endTime,
                          peopleInvolved: peopleInvolvedController.text.trim(),
                          remarks: remarksController.text.trim(),
                          person: personController.text.trim(),
                        );

                        setState(() => _isSaving = true);
                        try {
                          await CachedActivityService().createActivity(activity);
                          if (mounted) {
                            Navigator.pop(context, true); // Success
                          }
                        } catch (e) {
                          SnackbarUtils.showErrorSnackBar(context, 'Failed to save activity: $e');
                          if (mounted) setState(() => _isSaving = false);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Save Activity", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
