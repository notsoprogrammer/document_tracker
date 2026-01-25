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
  final peopleInvolvedController = TextEditingController();
  final remarksController = TextEditingController();
  final personController = TextEditingController();
  final locationController = TextEditingController();

  DateTime? selectedStartDate;
  TimeOfDay? selectedStartTime;
  DateTime? selectedEndDate;
  TimeOfDay? selectedEndTime;

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
          title: const Text("Add Activity"),
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
                            "Activity Information",
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
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && titleController.text.trim().isEmpty ? "Activity title is required" : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: peopleInvolvedController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "People Involved",
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && peopleInvolvedController.text.trim().isEmpty ? "People involved is required" : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: locationController,
                            enabled: !_isSaving,
                            decoration: const InputDecoration(
                              labelText: "Location (Optional)",
                              border: OutlineInputBorder(),
                              filled: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: remarksController,
                            enabled: !_isSaving,
                            decoration: const InputDecoration(
                              labelText: "Remarks",
                              border: OutlineInputBorder(),
                              filled: true,
                            ),
                            maxLines: 3,
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
                            "Time Information",
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
                                      setState(() {
                                        selectedStartDate = date;
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: "Start Date",
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Theme.of(context).colorScheme.surface,
                                      suffixIcon: const Icon(Icons.calendar_today),
                                      errorText: _showValidationErrors && selectedStartDate == null ? "Start date is required" : null,
                                    ),
                                    child: Text(
                                      selectedStartDate != null
                                          ? "${selectedStartDate!.month}/${selectedStartDate!.day}/${selectedStartDate!.year}"
                                          : '',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: _isSaving ? null : () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: selectedStartTime ?? const TimeOfDay(hour: 9, minute: 0),
                                    );
                                    if (time != null) {
                                      setState(() {
                                        selectedStartTime = time;
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: "Start Time",
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Theme.of(context).colorScheme.surface,
                                      suffixIcon: const Icon(Icons.access_time),
                                      errorText: _showValidationErrors && selectedStartTime == null ? "Start time is required" : null,
                                    ),
                                    child: Text(
                                      selectedStartTime != null
                                          ? "${selectedStartTime!.hour.toString().padLeft(2, '0')}:${selectedStartTime!.minute.toString().padLeft(2, '0')}"
                                          : '',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
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
                                      setState(() {
                                        selectedEndDate = date;
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: "End Date (Optional)",
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      suffixIcon: Icon(Icons.calendar_today),
                                    ),
                                    child: Text(
                                      selectedEndDate != null
                                          ? "${selectedEndDate!.month}/${selectedEndDate!.day}/${selectedEndDate!.year}"
                                          : '',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: _isSaving ? null : () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: selectedEndTime ?? const TimeOfDay(hour: 17, minute: 0),
                                    );
                                    if (time != null) {
                                      setState(() {
                                        selectedEndTime = time;
                                      });
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: "End Time (Optional)",
                                      border: OutlineInputBorder(),
                                      filled: true,
                                      suffixIcon: Icon(Icons.access_time),
                                    ),
                                    child: Text(
                                      selectedEndTime != null
                                          ? "${selectedEndTime!.hour.toString().padLeft(2, '0')}:${selectedEndTime!.minute.toString().padLeft(2, '0')}"
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
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSaving ? null : () async {
                      setState(() {
                        _showValidationErrors = true;
                      });

                      if (titleController.text.trim().isNotEmpty &&
                          peopleInvolvedController.text.trim().isNotEmpty &&
                          selectedStartDate != null &&
                          selectedStartTime != null &&
                          personController.text.trim().isNotEmpty) {

                        final startDateTime = DateTime(
                          selectedStartDate!.year,
                          selectedStartDate!.month,
                          selectedStartDate!.day,
                          selectedStartTime!.hour,
                          selectedStartTime!.minute,
                        );

                        DateTime? endDateTime;
                        if (selectedEndDate != null && selectedEndTime != null) {
                          endDateTime = DateTime(
                            selectedEndDate!.year,
                            selectedEndDate!.month,
                            selectedEndDate!.day,
                            selectedEndTime!.hour,
                            selectedEndTime!.minute,
                          );
                        }

                        final activity = Activity(
                          title: titleController.text.trim(),
                          startTime: startDateTime,
                          endTime: endDateTime,
                          peopleInvolved: peopleInvolvedController.text.trim(),
                          remarks: remarksController.text.trim(),
                          person: personController.text.trim(),
                          location: locationController.text.trim().isNotEmpty ? locationController.text.trim() : null,
                        );

                        setState(() => _isSaving = true);
                        try {
                          await CachedActivityService().createActivity(activity);
                          if (mounted) {
                            Navigator.pop(context, true);
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
