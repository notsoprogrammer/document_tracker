import 'dart:async';
import 'package:flutter/material.dart';

class DocumentSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onFilterTap;
  final bool hasActiveFilter;
  final int resultCount;
  final int totalCount;
  final String hintText;

  const DocumentSearchBar({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onFilterTap,
    required this.resultCount,
    required this.totalCount,
    this.hasActiveFilter = false,
    this.hintText = 'Search by code, title, type...',
  });

  @override
  State<DocumentSearchBar> createState() => _DocumentSearchBarState();
}

class _DocumentSearchBarState extends State<DocumentSearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onSearch(value);
    });
  }

  void _onClear() {
    _debounce?.cancel();
    widget.controller.clear();
    setState(() {});
    widget.onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final isFiltering = widget.controller.text.isNotEmpty || widget.hasActiveFilter;
    final countText = isFiltering
        ? '${widget.resultCount} of ${widget.totalCount} found'
        : '${widget.totalCount} document${widget.totalCount != 1 ? 's' : ''}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  onChanged: _onChanged,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: widget.controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _onClear,
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.filter_list,
                      color: widget.hasActiveFilter ? Colors.orange[300] : null,
                    ),
                    onPressed: widget.onFilterTap,
                    tooltip: 'Filter by Date',
                  ),
                  if (widget.hasActiveFilter)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.orange[400],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              countText,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
