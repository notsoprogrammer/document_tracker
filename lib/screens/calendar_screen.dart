import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/document.dart';
import '../services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  Future<void> _selectMonthYear(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _focusedDay,
      firstDate: DateTime.utc(2020, 1, 1),
      lastDate: DateTime.utc(2030, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && picked != _focusedDay) {
      setState(() {
        _focusedDay = picked;
        _selectedDay = picked;
        _selectedEvents.value = _getEventsForDay(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    appBar: AppBar(
      title: const Text('Calendar'),
      foregroundColor: const Color.fromARGB(255, 3, 3, 3), // text/icon color
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectMonthYear(context),
            tooltip: 'Select Month/Year',
          ),
        ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFB2DFDB), // pastel teal-green
              Color(0xFFC8E6C9), // pastel green
              Color(0xFFA5D6A7), // slightly stronger pastel
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
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
              markerDecoration: BoxDecoration(
                color: Colors.green.shade200, // pastel marker
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: const Color(0xFFC8E6C9),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.green.shade400, // slightly stronger pastel for selected
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                color: Colors.green.shade700, // darker pastel for header text
                fontWeight: FontWeight.bold,
              ),
              leftChevronIcon: Icon(Icons.chevron_left, color: Colors.green.shade400),
              rightChevronIcon: Icon(Icons.chevron_right, color: Colors.green.shade400),
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
                if (value.isEmpty) {
                  return const Center(
                    child: Text(
                      'No events for this date',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final doc = value[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 4.0,
                      ),
                      child: Card(
                        elevation: 2,
                        child: InkWell(
                          onTap: () => _showDocumentDetails(context, doc),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: doc.calendarDeadline != null ? Colors.green : (doc.status == 'Completed' ? Colors.grey : Colors.red),
                                  width: 4,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        doc.title ?? 'No Title',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      doc.calendarDeadline != null ? Icons.calendar_today : Icons.schedule,
                                      color: doc.calendarDeadline != null ? Colors.green : (doc.status == 'Completed' ? Colors.grey : Colors.red),
                                      size: 20,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text(
                                      'Code: ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        await Clipboard.setData(ClipboardData(text: doc.code));
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Code copied to clipboard')),
                                          );
                                        }
                                      },
                                      child: Text(
                                        doc.code,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontFamily: 'monospace',
                                          color: Colors.blue,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: doc.calendarDeadline != null ? Colors.green.shade100 : (doc.status == 'Completed' ? Colors.grey.shade100 : Colors.red.shade100),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        doc.type,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: doc.calendarDeadline != null ? Colors.green.shade800 : (doc.status == 'Completed' ? Colors.grey.shade800 : Colors.red.shade800),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      doc.status,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: doc.status == 'Completed' ? Colors.grey : Colors.red,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
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

  void _showImageViewer(BuildContext context, List<String> imageUrls) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.8,
            child: PageView.builder(
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return CachedNetworkImage(
                  imageUrl: imageUrls[index],
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showDocumentDetails(BuildContext context, Document doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.3,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Card
                    Card(
                      elevation: 2,
                      margin: EdgeInsets.zero,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: doc.calendarDeadline != null ? Colors.green : (doc.status == 'Completed' ? Colors.grey : Colors.red),
                              width: 4,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title ?? 'No Title',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Code: ${doc.code}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontFamily: 'monospace',
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: doc.calendarDeadline != null ? Colors.green.shade100 : (doc.status == 'Completed' ? Colors.grey.shade100 : Colors.red.shade100),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    doc.type,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: doc.calendarDeadline != null ? Colors.green.shade800 : (doc.status == 'Completed' ? Colors.grey.shade800 : Colors.red.shade800),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Details Card
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow('From/To', doc.fromOrTo),
                            _buildDetailRow('Status', doc.status),
                            if (doc.complianceDeadline != null)
                              _buildDetailRow('Compliance Deadline', doc.complianceDeadline!.toLocal().toString().split(' ')[0]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Images Section
                    if (doc.imageUrls.isNotEmpty) ...[
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Images',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => _showImageViewer(context, doc.imageUrls),
                                child: CachedNetworkImage(
                                  imageUrl: doc.imageUrls.first,
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) => const Icon(Icons.error),
                                ),
                              ),
                              if (doc.imageUrls.length > 1)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Tap to view all images',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Files Section
                    if (doc.fileUrls.isNotEmpty) ...[
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Files',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...doc.fileUrls.map((fileUrl) {
                                final fileName = fileUrl.split('/').last;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    onTap: () async {
                                      if (await canLaunchUrl(Uri.parse(fileUrl))) {
                                        await launchUrl(Uri.parse(fileUrl));
                                      }
                                    },
                                    child: Row(
                                      children: [
                                        const Icon(Icons.attach_file, color: Colors.blue),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            fileName,
                                            style: const TextStyle(
                                              color: Colors.blue,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
