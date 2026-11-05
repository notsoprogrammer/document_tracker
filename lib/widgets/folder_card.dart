import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One entry in the document-folder grid.
class FolderSpec {
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  const FolderSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.accent,
    required this.onTap,
  });
}

/// A folder tile: white surface, hairline border, and a single small tinted
/// icon chip carrying the colour. Replaces the full-bleed gradient blocks,
/// which fought each other for attention and made counts hard to read.
class FolderCard extends StatefulWidget {
  final FolderSpec spec;
  const FolderCard({super.key, required this.spec});

  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: AppTheme.brLg,
          border: Border.all(
            color: _hovered ? s.accent.withValues(alpha: 0.45) : AppTheme.border,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: s.accent.withValues(alpha: 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppTheme.brLg,
            onTap: s.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.soften(s.accent),
                      borderRadius: AppTheme.br,
                    ),
                    child: Icon(s.icon, size: 20, color: s.accent),
                  ),
                  const SizedBox(width: AppTheme.gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.gapSm),
                  // Count reads as data, not as a badge competing with the title.
                  Text(
                    '${s.count}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the folder cards out in a grid whose column count follows the
/// available width, so the same screen works on a phone and a desktop browser.
class FolderGrid extends StatelessWidget {
  final List<FolderSpec> folders;
  const FolderGrid({super.key, required this.folders});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = AppTheme.gridColumns(constraints.maxWidth);
        const spacing = AppTheme.gap;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final f in folders)
              SizedBox(width: cardWidth, child: FolderCard(spec: f)),
          ],
        );
      },
    );
  }
}
