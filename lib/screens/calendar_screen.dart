import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../models/document.dart';
import '../models/activity.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'add_activity_screen.dart';
import '../services/google_drive_service.dart';
import '../config/supabase_config.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final ValueNotifier<List<dynamic>> _selectedEvents;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  RangeSelectionMode _rangeSelectionMode = RangeSelectionMode.toggledOff;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  List<Document> _calendarDocuments = [];
  List<Activity> _calendarActivities = [];

  late final ConnectivityService connectivityService;

  @override
  void initState() {
    super.initState();
    connectivityService = ConnectivityService();
    connectivityService.initialize();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier(_getEventsForDay(_selectedDay!));
    _loadCalendarDocuments();
    _loadCalendarActivities();
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

  Future<void> _loadCalendarActivities() async {
    try {
      final activities = await SupabaseService().fetchActivities();
      setState(() {
        _calendarActivities = activities;
      });
      _selectedEvents.value = _getEventsForDay(_selectedDay!);
    } catch (e) {
      print('Error loading calendar activities: $e');
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    final events = <dynamic>[];

    // Add documents
    events.addAll(_calendarDocuments.where((doc) {
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
    }));

    // Add activities (only on start date)
    events.addAll(_calendarActivities.where((activity) {
      final startDate = activity.startTime;

      // Check start time only
      if (startDate != null &&
          startDate.year == day.year &&
          startDate.month == day.month &&
          startDate.day == day.day) {
        return true;
      }

      return false;
    }));

    return events;
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

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$month/$day/$year $displayHour:$minute $amPm';
  }

  String _cleanRemarks(String remarks) {
    // Remove lines that start with "Attachment:" to exclude attachments from remarks display
    final lines = remarks.split('\n');
    final cleanedLines = lines.where((line) => !line.trim().startsWith('Attachment:')).toList();
    return cleanedLines.join('\n').trim();
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
      floatingActionButton: StreamBuilder<bool>(
        stream: connectivityService.onOnlineStatusChanged,
        builder: (context, snapshot) {
          final isOnline = snapshot.data ?? connectivityService.currentOnlineStatus;
          if (!isOnline) return const SizedBox();
          return FloatingActionButton(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddActivityScreen()),
              );
              if (result == true) {
                // Reload activities if added
                _loadCalendarActivities();
              }
            },
            backgroundColor: const Color(0xFF87CEEB), // pastel blue
            child: const Icon(Icons.add),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final banner = StreamBuilder<bool>(
            stream: connectivityService.onOnlineStatusChanged,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? connectivityService.currentOnlineStatus;
              if (isOnline) return const SizedBox();
              return Container(
                color: Colors.orange.shade100,
                padding: const EdgeInsets.all(8),
                child: const Text(
                  'You are offline. Connect to internet to view and add activities.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black87),
                ),
              );
            },
          );
          final calendar = SizedBox(
            height: 400,
            child: TableCalendar<dynamic>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              rangeStartDay: _rangeStart,
              rangeEndDay: _rangeEnd,
              calendarFormat: _calendarFormat,
              rangeSelectionMode: _rangeSelectionMode,
              eventLoader: _getEventsForDay,
              startingDayOfWeek: StartingDayOfWeek.sunday,
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
                  bool hasLeave = false;
                  bool hasPendingCompliance = false;
                  bool hasCompletedCompliance = false;
                  bool hasActivity = false;

                  for (var event in events) {
                    if (event is Document) {
                      if (event.calendarDeadline != null &&
                          isSameDay(event.calendarDeadline!, date)) {
                        if (event.type == 'Leave') {
                          hasLeave = true;
                        } else {
                          hasCalendar = true;
                        }
                      }
                      if (event.complianceDeadline != null &&
                          isSameDay(event.complianceDeadline!, date)) {
                        if (event.status == 'Completed') {
                          hasCompletedCompliance = true;
                        } else {
                          hasPendingCompliance = true;
                        }
                      }
                    } else if (event is Activity) {
                      // Activities are always calendar events
                      if (event.startTime != null && isSameDay(event.startTime!, date)) {
                        hasActivity = true;
                      }
                    }
                  }

                  if (hasLeave) {
                    markers.add(Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 255, 126, 203),
                        shape: BoxShape.circle,
                      ),
                    ));
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
                  if (hasActivity) {
                    markers.add(Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
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
          );
          final eventList = Expanded(
            child: ValueListenableBuilder<List<dynamic>>(
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
                    final item = value[index];
                    if (item is Document) {
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 4.0,
                        ),
                        child: Card(
                          elevation: 4,
                          child: InkWell(
                            onTap: () => _showDocumentDetails(context, item),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: item.calendarDeadline != null ? Colors.green : (item.status == 'Completed' ? Colors.grey : Colors.red),
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
                                          item.title ?? 'No Title',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(
                                        item.calendarDeadline != null ? Icons.calendar_today : Icons.schedule,
                                        color: item.calendarDeadline != null ? Colors.green : (item.status == 'Completed' ? Colors.grey : Colors.red),
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (item is Document) ...[
                                    Row(
                                      children: [
                                        const Text(
                                          'Code: ',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          item.code,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontFamily: 'monospace',
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: item.calendarDeadline != null ? Colors.green.shade100 : (item.status == 'Completed' ? Colors.grey.shade100 : Colors.red.shade100),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          item.type,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: item.calendarDeadline != null ? Colors.green.shade800 : (item.status == 'Completed' ? Colors.grey.shade800 : Colors.red.shade800),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item.status,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: item.status == 'Completed' ? Colors.grey : Colors.red,
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
                    } else if (item is Activity) {
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 4.0,
                        ),
                        child: Card(
                          elevation: 4,
                          child: InkWell(
                            onTap: () => _showActivityDetails(context, item),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: Colors.blue,
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
                                          item.title ?? 'No Title',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.event,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Activity',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox();
                    }
                  },
                );
              },
            ),
          );
          if (isWide) {
            return Column(
              children: [
                banner,
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 400,
                        child: calendar,
                      ),
                      eventList,
                    ],
                  ),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                banner,
                calendar,
                const SizedBox(height: 8.0),
                eventList,
              ],
            );
          }
        },
      ),
    );
  }

  void _showImageViewer(BuildContext context, List<String> imageUrls) {
    final PageController pageController = PageController();
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              children: [
              PageView.builder(
                controller: pageController,
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  String normalizedFileId = GoogleDriveService.normalizeFileId(imageUrls[index]);
                  String proxyUrl = GoogleDriveService.generateProxyUrl(normalizedFileId);
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: proxyUrl,
                      httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => const Center(child: Text('Failed to load image')),
                    ),
                  );
                },
                ),
                if (imageUrls.length > 1) ...[
                  Positioned(
                    left: 10,
                    top: MediaQuery.of(context).size.height * 0.5 - 25,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 30),
                      onPressed: () {
                        if (pageController.page! > 0) {
                          pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: MediaQuery.of(context).size.height * 0.5 - 25,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, color: Colors.black, size: 30),
                      onPressed: () {
                        if (pageController.page! < imageUrls.length - 1) {
                          pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                    ),
                  ),
                ],
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
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
        return StatefulBuilder(
          builder: (context, setState) {
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
                                    'Code: ${doc.code}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontFamily: 'monospace',
                                      color: Colors.blue,
                                      decoration: TextDecoration.underline,
                                    ),
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
                        const SizedBox(height: 4),

                        // Details Card
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('From/To', doc.fromOrTo),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Remarks:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    IconButton(
                                      color: const Color(0xFF088395),
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _editRemarks(context, doc, setState),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                                    ),
                                    const SizedBox(width: 8),

                                    Expanded(
                                      child: Text(
                                        _cleanRemarks(doc.remarks),
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                                if (doc.calendarDeadline != null)
                                  _buildDetailRow('Date & Time', DateFormat('MM/dd/yy | hh:mm a').format(doc.calendarDeadline!)),
                                if (doc.complianceDeadline != null)
                                  _buildDetailRow('Compliance Deadline', doc.complianceDeadline!.toLocal().toString().split(' ')[0]),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

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
                                      imageUrl: GoogleDriveService.generateProxyUrl(GoogleDriveService.normalizeFileId(doc.imageUrls.first)),
                                      httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
                                      height: 150,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                      errorWidget: (context, url, error) => const Center(child: Text('Failed to load image')),
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
                          const SizedBox(height: 4),
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
                                  ...doc.fileUrls.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final fileUrl = entry.value;
                                    final fileName = index < doc.fileNames.length ? doc.fileNames[index] : 'Document.pdf';
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
      },
    );
  }

  void _showActivityDetails(BuildContext context, Activity activity) {
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
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Colors.blue,
                              width: 4,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activity.title ?? 'No Title',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Activity',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Details Card
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            if (activity.startTime != null)
                              _buildDetailRow('Date and Time', _formatDateTime(activity.startTime!)),
                            if (activity.endTime != null)
                              _buildDetailRow('End Date and Time', _formatDateTime(activity.endTime!)),
                            _buildDetailRow('Added by', activity.person),
                            _buildDetailRow('People Involved', activity.peopleInvolved),
                            if (activity.location != null && activity.location!.isNotEmpty)
                              _buildDetailRow('Location', activity.location!),
                            _buildDetailRow('Remarks', activity.remarks),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Delete Button
                    Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete),
                        label: const Text("Delete Activity"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          final connectivityResult = await Connectivity().checkConnectivity();
                          final isOnline = !connectivityResult.contains(ConnectivityResult.none);
                          if (!isOnline) {
                            Navigator.of(context).pop(); // Close modal
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cannot delete activity offline'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Confirm Deletion'),
                              content: Text('Are you sure you want to delete "${activity.title ?? 'this activity'}"?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[700],
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && activity.id != null) {
                            try {
                              await SupabaseService().deleteActivity(activity.id!);
                              if (mounted) {
                                Navigator.of(context).pop(); // Close modal
                                _loadCalendarActivities(); // Reload activities
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Activity "${activity.title ?? 'Activity'}" deleted successfully'),
                                    backgroundColor: Colors.green[700],
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('No internet, please try again later.'),
                                    backgroundColor: Colors.red[700],
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _editRemarks(BuildContext context, Document doc, StateSetter setState) async {
    final TextEditingController remarksController = TextEditingController(text: doc.remarks);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Remarks'),
        content: TextField(
          controller: remarksController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter meeting location, remarks, status',
              hintStyle: TextStyle(
              fontStyle: FontStyle.italic, // italic hint text
              color: Colors.grey,          // optional: muted color
            ),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, remarksController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result != doc.remarks) {
      try {
        await CachedDocumentService().updateDocument(doc.code, {'remarks': result});
        // Add history entry
        final username = await AuthService.getUsername();
        if (username != null) {
          await CachedDocumentService().addHistoryEntry(
            doc.code,
            HistoryEntry(
              action: 'Remarks updated',
              person: username,
              timestamp: DateTime.now(),
            ),
          );
        }
        // Update local document remarks and refresh UI
        final index = _calendarDocuments.indexWhere((d) => d.code == doc.code);
        if (index != -1) {
          _calendarDocuments[index] = _calendarDocuments[index].copyWith(remarks: result);
          setState(() {});
        }
        // Reload documents
        _loadCalendarDocuments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Remarks updated successfully')),
          );
          // Close the edit dialog
          Navigator.of(context).pop(); // close edit dialog
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update remarks: $e')),
          );
        }
      }
    }
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
