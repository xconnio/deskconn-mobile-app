import 'package:flutter/material.dart';

/// Raw brand colors used only by the theme builder in [app_theme.dart].
/// Widgets must resolve colors via [DeskconnPalette.of] or `Theme.of(context)`
/// so light/dark are driven from a single source of truth.
class DeskconnColors {
  static const primary = Color(0xFF111827);
  static const primaryHover = Color(0xFF1F2937);
  static const primarySoft = Color(0xFFE8EAED);
  static const onPrimary = Colors.white;
  static const secondary = Color(0xFF2C2E33);

  static const body = Color(0xFFF8FAFC);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceTint = Color(0xFFF1F5F9);
  static const border = Color(0xFFE2E8F0);
  static const cardBorder = Color(0xFFE8ECF0);

  static const text = Color(0xFF334155);
  static const heading = Color(0xFF1E293B);
  static const muted = Color(0xFF475569);
  static const subtle = Color(0xFF64748B);

  static const overlay = Color(0x662C2E33);

  // Dark fallback derived from the same slate family so theme toggle stays coherent.
  static const darkBackground = Color(0xFF0F1724);
  static const darkSurface = Color(0xFF141E31);
  static const darkSurfaceTint = Color(0xFF1A2538);
  static const darkBorder = Color(0xFF334155);
  static const darkOnSurface = Color(0xFFE2E8F0);
}

/// App-specific semantic colors that Material 3 roles can't express.
/// Each token carries a light and dark value, resolved at build time from the
/// active [ThemeData] via [DeskconnPalette.of]. This is the single source of
/// truth for these colors — widgets must not hardcode light/dark pairs.
class DeskconnPalette extends ThemeExtension<DeskconnPalette> {
  final Color background;
  final Color surface;
  final Color surfaceTint;
  final Color border;
  final Color cardBorder;
  final Color text;
  final Color heading;
  final Color muted;
  final Color subtle;

  final Color statusOnline;
  final Color statusRouted;
  final Color statusOffline;

  final Color fileTileBackground;
  final Color fileTilePlaceholder;
  final Color fileTileText;
  final Color fileTextSubtle;
  final Color googleBlue;
  final Color iconFile;
  final Color iconFolder;
  final Color iconSymlink;

  // File-type accent family (mirrors the color-by-type convention of most
  // desktop/mobile file managers). Each is a light/dark pair.
  final Color typeImage;
  final Color typeVideo;
  final Color typeAudio;
  final Color typeWord;
  final Color typeExcel;
  final Color typePowerPoint;
  final Color typeText;
  final Color typeArchive;
  final Color typePdf;
  final Color typeExecutable;
  final Color typeDefault;

  final Color osUbuntu;
  final Color osKubuntu;
  final Color osXubuntu;
  final Color osMint;
  final Color osDebian;
  final Color osFedora;
  final Color osWindows;

  const DeskconnPalette({
    required this.background,
    required this.surface,
    required this.surfaceTint,
    required this.border,
    required this.cardBorder,
    required this.text,
    required this.heading,
    required this.muted,
    required this.subtle,
    required this.statusOnline,
    required this.statusRouted,
    required this.statusOffline,
    required this.fileTileBackground,
    required this.fileTilePlaceholder,
    required this.fileTileText,
    required this.fileTextSubtle,
    required this.googleBlue,
    required this.iconFile,
    required this.iconFolder,
    required this.iconSymlink,
    required this.typeImage,
    required this.typeVideo,
    required this.typeAudio,
    required this.typeWord,
    required this.typeExcel,
    required this.typePowerPoint,
    required this.typeText,
    required this.typeArchive,
    required this.typePdf,
    required this.typeExecutable,
    required this.typeDefault,
    required this.osUbuntu,
    required this.osKubuntu,
    required this.osXubuntu,
    required this.osMint,
    required this.osDebian,
    required this.osFedora,
    required this.osWindows,
  });

  static const light = DeskconnPalette(
    background: DeskconnColors.body,
    surface: DeskconnColors.surface,
    surfaceTint: DeskconnColors.surfaceTint,
    border: DeskconnColors.border,
    cardBorder: DeskconnColors.cardBorder,
    text: DeskconnColors.text,
    heading: DeskconnColors.heading,
    muted: DeskconnColors.muted,
    subtle: DeskconnColors.subtle,
    statusOnline: Color(0xFF16A34A),
    statusRouted: Color(0xFFB45309),
    statusOffline: Color(0xFFDC2626),
    fileTileBackground: Color(0xFFE6E8F1),
    fileTilePlaceholder: Color(0xFFE2E8F0),
    fileTileText: Color(0xFF2F323A),
    fileTextSubtle: Color(0xFF5C5F68),
    googleBlue: Color(0xFF1A73E8),
    iconFile: Color(0xFF565F72),
    iconFolder: Color(0xFF565F72),
    iconSymlink: Color(0xFF64748B),
    typeImage: Color(0xFF7C3AED),
    typeVideo: Color(0xFFE11D48),
    typeAudio: Color(0xFFDB2777),
    typeWord: Color(0xFF2563EB),
    typeExcel: Color(0xFF16A34A),
    typePowerPoint: Color(0xFFEA580C),
    typeText: Color(0xFF0D9488),
    typeArchive: Color(0xFFB45309),
    typePdf: Color(0xFFDC2626),
    typeExecutable: Color(0xFF4F46E5),
    typeDefault: Color(0xFF565F72),
    osUbuntu: Color(0xFF2C82C9),
    osKubuntu: Color(0xFFE95420),
    osXubuntu: Color(0xFF77216F),
    osMint: Color(0xFF0E8420),
    osDebian: Color(0xFF2C2C2C),
    osFedora: Color(0xFF294172),
    osWindows: Color(0xFFC7162B),
  );

  static const dark = DeskconnPalette(
    background: DeskconnColors.darkBackground,
    surface: DeskconnColors.darkSurface,
    surfaceTint: DeskconnColors.darkSurfaceTint,
    border: DeskconnColors.darkBorder,
    cardBorder: DeskconnColors.darkBorder,
    text: DeskconnColors.darkOnSurface,
    heading: Colors.white,
    muted: Color(0xFF94A3B8),
    subtle: Color(0xFFA8ABB5),
    statusOnline: Color(0xFF4ADE80),
    statusRouted: Color(0xFFFBBF24),
    statusOffline: Color(0xFFF87171),
    fileTileBackground: Color(0xFF1D2026),
    fileTilePlaceholder: Color(0xFF111827),
    fileTileText: Color(0xFFE3E5EF),
    fileTextSubtle: Color(0xFFA8ABB5),
    googleBlue: Color(0xFF1A73E8),
    iconFile: Color(0xFFBDC7DC),
    iconFolder: Color(0xFFBDC7DC),
    iconSymlink: Color(0xFFCBD5E1),
    typeImage: Color(0xFFC4B5FD),
    typeVideo: Color(0xFFFDA4AF),
    typeAudio: Color(0xFFF9A8D4),
    typeWord: Color(0xFF93C5FD),
    typeExcel: Color(0xFF86EFAC),
    typePowerPoint: Color(0xFFFDBA74),
    typeText: Color(0xFF5EEAD4),
    typeArchive: Color(0xFFFCD34D),
    typePdf: Color(0xFFFCA5A5),
    typeExecutable: Color(0xFFA5B4FC),
    typeDefault: Color(0xFFCBD5E1),
    osUbuntu: Color(0xFF2C82C9),
    osKubuntu: Color(0xFFE95420),
    osXubuntu: Color(0xFF77216F),
    osMint: Color(0xFF0E8420),
    osDebian: Color(0xFF9E9E9E),
    osFedora: Color(0xFF294172),
    osWindows: Color(0xFFC7162B),
  );

  static DeskconnPalette of(BuildContext context) {
    return Theme.of(context).extension<DeskconnPalette>()!;
  }

  @override
  DeskconnPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceTint,
    Color? border,
    Color? cardBorder,
    Color? text,
    Color? heading,
    Color? muted,
    Color? subtle,
    Color? statusOnline,
    Color? statusRouted,
    Color? statusOffline,
    Color? fileTileBackground,
    Color? fileTilePlaceholder,
    Color? fileTileText,
    Color? fileTextSubtle,
    Color? googleBlue,
    Color? iconFile,
    Color? iconFolder,
    Color? iconSymlink,
    Color? typeImage,
    Color? typeVideo,
    Color? typeAudio,
    Color? typeWord,
    Color? typeExcel,
    Color? typePowerPoint,
    Color? typeText,
    Color? typeArchive,
    Color? typePdf,
    Color? typeExecutable,
    Color? typeDefault,
    Color? osUbuntu,
    Color? osKubuntu,
    Color? osXubuntu,
    Color? osMint,
    Color? osDebian,
    Color? osFedora,
    Color? osWindows,
  }) {
    return DeskconnPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceTint: surfaceTint ?? this.surfaceTint,
      border: border ?? this.border,
      cardBorder: cardBorder ?? this.cardBorder,
      text: text ?? this.text,
      heading: heading ?? this.heading,
      muted: muted ?? this.muted,
      subtle: subtle ?? this.subtle,
      statusOnline: statusOnline ?? this.statusOnline,
      statusRouted: statusRouted ?? this.statusRouted,
      statusOffline: statusOffline ?? this.statusOffline,
      fileTileBackground: fileTileBackground ?? this.fileTileBackground,
      fileTilePlaceholder: fileTilePlaceholder ?? this.fileTilePlaceholder,
      fileTileText: fileTileText ?? this.fileTileText,
      fileTextSubtle: fileTextSubtle ?? this.fileTextSubtle,
      googleBlue: googleBlue ?? this.googleBlue,
      iconFile: iconFile ?? this.iconFile,
      iconFolder: iconFolder ?? this.iconFolder,
      iconSymlink: iconSymlink ?? this.iconSymlink,
      typeImage: typeImage ?? this.typeImage,
      typeVideo: typeVideo ?? this.typeVideo,
      typeAudio: typeAudio ?? this.typeAudio,
      typeWord: typeWord ?? this.typeWord,
      typeExcel: typeExcel ?? this.typeExcel,
      typePowerPoint: typePowerPoint ?? this.typePowerPoint,
      typeText: typeText ?? this.typeText,
      typeArchive: typeArchive ?? this.typeArchive,
      typePdf: typePdf ?? this.typePdf,
      typeExecutable: typeExecutable ?? this.typeExecutable,
      typeDefault: typeDefault ?? this.typeDefault,
      osUbuntu: osUbuntu ?? this.osUbuntu,
      osKubuntu: osKubuntu ?? this.osKubuntu,
      osXubuntu: osXubuntu ?? this.osXubuntu,
      osMint: osMint ?? this.osMint,
      osDebian: osDebian ?? this.osDebian,
      osFedora: osFedora ?? this.osFedora,
      osWindows: osWindows ?? this.osWindows,
    );
  }

  @override
  DeskconnPalette lerp(DeskconnPalette? other, double t) {
    if (other == null) return this;
    return DeskconnPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceTint: Color.lerp(surfaceTint, other.surfaceTint, t)!,
      border: Color.lerp(border, other.border, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      text: Color.lerp(text, other.text, t)!,
      heading: Color.lerp(heading, other.heading, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      statusOnline: Color.lerp(statusOnline, other.statusOnline, t)!,
      statusRouted: Color.lerp(statusRouted, other.statusRouted, t)!,
      statusOffline: Color.lerp(statusOffline, other.statusOffline, t)!,
      fileTileBackground: Color.lerp(fileTileBackground, other.fileTileBackground, t)!,
      fileTilePlaceholder: Color.lerp(fileTilePlaceholder, other.fileTilePlaceholder, t)!,
      fileTileText: Color.lerp(fileTileText, other.fileTileText, t)!,
      fileTextSubtle: Color.lerp(fileTextSubtle, other.fileTextSubtle, t)!,
      googleBlue: Color.lerp(googleBlue, other.googleBlue, t)!,
      iconFile: Color.lerp(iconFile, other.iconFile, t)!,
      iconFolder: Color.lerp(iconFolder, other.iconFolder, t)!,
      iconSymlink: Color.lerp(iconSymlink, other.iconSymlink, t)!,
      typeImage: Color.lerp(typeImage, other.typeImage, t)!,
      typeVideo: Color.lerp(typeVideo, other.typeVideo, t)!,
      typeAudio: Color.lerp(typeAudio, other.typeAudio, t)!,
      typeWord: Color.lerp(typeWord, other.typeWord, t)!,
      typeExcel: Color.lerp(typeExcel, other.typeExcel, t)!,
      typePowerPoint: Color.lerp(typePowerPoint, other.typePowerPoint, t)!,
      typeText: Color.lerp(typeText, other.typeText, t)!,
      typeArchive: Color.lerp(typeArchive, other.typeArchive, t)!,
      typePdf: Color.lerp(typePdf, other.typePdf, t)!,
      typeExecutable: Color.lerp(typeExecutable, other.typeExecutable, t)!,
      typeDefault: Color.lerp(typeDefault, other.typeDefault, t)!,
      osUbuntu: Color.lerp(osUbuntu, other.osUbuntu, t)!,
      osKubuntu: Color.lerp(osKubuntu, other.osKubuntu, t)!,
      osXubuntu: Color.lerp(osXubuntu, other.osXubuntu, t)!,
      osMint: Color.lerp(osMint, other.osMint, t)!,
      osDebian: Color.lerp(osDebian, other.osDebian, t)!,
      osFedora: Color.lerp(osFedora, other.osFedora, t)!,
      osWindows: Color.lerp(osWindows, other.osWindows, t)!,
    );
  }
}
