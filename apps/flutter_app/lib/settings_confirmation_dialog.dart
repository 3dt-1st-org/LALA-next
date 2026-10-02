import 'package:flutter/material.dart';

/// A shared illustration and copy for both layouts and both toggle states.
class SettingsConfirmationDialog extends StatelessWidget {
  const SettingsConfirmationDialog({
    super.key,
    required this.docent,
    required this.title,
    required this.message,
    required this.sectionLabel,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.closeLabel,
    this.showIllustration = true,
    this.dialogKey = const ValueKey('settings-toggle-dialog'),
  });

  final bool docent;
  final String title;
  final String message;
  final String sectionLabel;
  final String confirmLabel;
  final String cancelLabel;
  final String closeLabel;
  final bool showIllustration;
  final Key dialogKey;

  static const jade = Color(0xFF31786C);
  static const ink = Color(0xFF292725);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sideBySide = wide && showIllustration;
    final compact = MediaQuery.sizeOf(context).height < 700;
    final art = Image.asset(
      docent
          ? 'assets/images/onboarding/settings-docent-hanok.png'
          : 'assets/images/onboarding/settings-location-map.png',
      height: wide ? 200 : (compact ? 112 : 164),
      width: wide ? 272 : 264,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: sideBySide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          sectionLabel,
          style: const TextStyle(
            color: jade,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: sideBySide ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            fontSize: wide ? 25 : 22,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    );
    final body = Text(
      message,
      textAlign: sideBySide ? TextAlign.start : TextAlign.center,
      style: const TextStyle(
        fontSize: 14,
        height: 1.75,
        color: Color(0xFF6D7470),
      ),
    );
    final confirm = FilledButton(
      key: const ValueKey('settings-toggle-confirm'),
      style: FilledButton.styleFrom(
        backgroundColor: jade,
        foregroundColor: Colors.white,
        minimumSize: Size(wide ? 148 : double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      onPressed: () => Navigator.pop(context, true),
      child: Text(confirmLabel, textAlign: TextAlign.center),
    );
    final cancel = TextButton(
      style: TextButton.styleFrom(
        foregroundColor: jade,
        minimumSize: const Size(100, 48),
      ),
      onPressed: () => Navigator.pop(context, false),
      child: Text(cancelLabel),
    );
    return Dialog(
      key: dialogKey,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? (showIllustration ? 720 : 560) : 400,
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  wide ? 36 : 24,
                  wide ? 48 : 36,
                  wide ? 36 : 24,
                  wide ? 28 : 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sideBySide)
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                heading,
                                const SizedBox(height: 18),
                                body,
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          art,
                        ],
                      )
                    else ...[
                      heading,
                      if (showIllustration) ...[
                        const SizedBox(height: 18),
                        art,
                      ],
                      const SizedBox(height: 18),
                      body,
                    ],
                    SizedBox(height: wide ? 28 : 24),
                    if (wide)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [cancel, const SizedBox(width: 12), confirm],
                      )
                    else ...[
                      confirm,
                      const SizedBox(height: 4),
                      cancel,
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                key: const ValueKey('settings-toggle-close'),
                tooltip: closeLabel,
                color: const Color(0xFF6D7470),
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close, size: 21),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
