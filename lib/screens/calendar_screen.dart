import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/document.dart';
import '../services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final ValueNotifier<List<Document>> _selectedEvents;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  RangeSelectionMode _rangeSelectionMode = RangeSelectionMode.toggledOff;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  List<Document> _calendarDocuments = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier(_getEventsForDay(_selectedDay!));
    _loadCalendarDocuments();
  }

  @override
  void dispose() {
    _selectedEvents.dispose();
    super.dispose();
  }

  Future<void> _loadCalendarDocuments() async {
    try {
      final documents = await SupabaseService().fetchCalendarDocuments();
      setState(() {
        _calendarDocuments = documents;
      });
      _selectedEvents.value = _getEventsForDay(_selectedDay!);
    } catch (e) {
      print('Error loading calendar documents: $e');
    }
  }

  List<Document> _getEventsForDay(DateTime day) {
    return _calendarDocuments.where((doc) {
      final calendarDate = doc.calendarDeadline;
      final complianceDate = doc.complianceDeadline;

      // Check calendar deadline
      if (calendarDate != null &&
          calendarDate.year == day.year &&
          calendarDate.month == day.month &&
          calendarDate.day == day.day) {
        return true;
      }

      // Check compliance deadline
      if (complianceDate != null &&
          complianceDate.year == day.year &&
          complianceDate.month == day.month &&
          complianceDate.day == day.day) {
        return true;
      }

      return false;
    }).toList();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _rangeStart = null;
        _rangeEnd = null;
        _rangeSelectionMode = RangeSelectionMode.toggledOff;
      });

      _selectedEvents.value = _getEventsForDay(selectedDay);
    }
  }

  void _onFormatChanged(CalendarFormat format) {
    if (_calendarFormat != format) {
      setState(() {
        _calendarFormat = format;
      });
    }
  }

  void _onPageChanged(DateTime focusedDay) {
    _focusedDay = focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          TableCalendar<Document>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            rangeStartDay: _rangeStart,
            rangeEndDay: _rangeEnd,
            calendarFormat: _calendarFormat,
            rangeSelectionMode: _rangeSelectionMode,
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              markersMaxCount: 3,
              markerDecoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            onDaySelected: _onDaySelected,
            onFormatChanged: _onFormatChanged,
            onPageChanged: _onPageChanged,
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return const SizedBox();

                List<Widget> markers = [];
                bool hasCalendar = false;
                bool hasPendingCompliance = false;
                bool hasCompletedCompliance = false;

                for (var doc in events) {
                  if (doc.calendarDeadline != null &&
                      isSameDay(doc.calendarDeadline!, date)) {
                    hasCalendar = true;
                  }
                  if (doc.complianceDeadline != null &&
                      isSameDay(doc.complianceDeadline!, date)) {
                    if (doc.status == 'Completed') {
                      hasCompletedCompliance = true;
                    } else {
                      hasPendingCompliance = true;
                    }
                  }
                }

                if (hasCalendar) {
                  markers.add(Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ));
                }
                if (hasPendingCompliance) {
                  markers.add(Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ));
                }
                // No indicator for completed compliance, but metadata remains in modal

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: markers,
                );
              },
            ),
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: ValueListenableBuilder<List<Document>>(
              valueListenable: _selectedEvents,
              builder: (context, value, _) {
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final doc = value[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: ListTile(
                        onTap: () => _showDocumentDetails(context, doc),
                        title: Text(doc.title ?? 'No Title'),
                        subtitle: Text('Code: ${doc.code}\nType: ${doc.type}'),
                        trailing: Icon(
                          doc.calendarDeadline != null ? Icons.calendar_today : Icons.schedule,
                          color: doc.calendarDeadline != null ? Colors.green : (doc.status == 'Completed' ? Colors.grey : Colors.red),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDocumentDetails(BuildContext context, Document doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  Text(
                    doc.title ?? 'No Title',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Code: ${doc.code}'),
                  Text('Type: ${doc.type}'),
                  Text('From/To: ${doc.fromOrTo}'),
                  Text('Status: ${doc.status}'),
                  if (doc.calendarDeadline != null) ...[
                    Text('Calendar Date: ${doc.calendarDeadline!.toLocal().toString().split(' ')[0]}'),
                  ],
                  if (doc.complianceDeadline != null) ...[
                    Text('Compliance Deadline: ${doc.complianceDeadline!.toLocal().toString().split(' ')[0]}'),
                  ],
                  const SizedBox(height: 16),
                  const Text('Attachments:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...doc.attachments.map((attachment) {
                    return ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: Text(attachment.split('/').last),
                      onTap: () async {
                        if (await canLaunchUrl(Uri.file(attachment))) {
                          await launchUrl(Uri.file(attachment));
                        }
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
