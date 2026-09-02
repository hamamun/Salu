/// A named 10-band graphic-equalizer curve.
///
/// Bands (Hz): 31.25 · 62.5 · 125 · 250 · 500 · 1k · 2k · 4k · 8k · 16k
/// Gains are in decibels (−12 … +12).
class EqualizerPreset {
  const EqualizerPreset(this.name, this.gains);

  final String name;
  final List<double> gains;
}

/// The preset library shown in the Audio Tab (Phase 4 · Step 4).
///
/// The list is split by file type exactly as the spec requires: audio files
/// get the full music set, video files get the cinema/dialogue set.
class EqualizerPresets {
  EqualizerPresets._();

  /// Center frequency of each of the 10 bands.
  static const List<double> bands = <double>[
    31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  static const List<double> flat = <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  static const List<EqualizerPreset> audio = <EqualizerPreset>[
    EqualizerPreset('Acoustic', <double>[4, 3, 2, 2, 0, 0, 1, 2, 3, 4]),
    EqualizerPreset('Bass and Treble', <double>[5, 4, 3, 1, 0, 0, 1, 3, 4, 5]),
    EqualizerPreset('Bass Only', <double>[7, 6, 5, 4, 2, 0, 0, 0, 0, 0]),
    EqualizerPreset('Classical', <double>[4, 3, 2, 1, 0, 0, 1, 2, 3, 4]),
    EqualizerPreset('Dance', <double>[6, 5, 3, 0, 1, 2, 3, 4, 5, 5]),
    EqualizerPreset('Electronic', <double>[5, 4, 1, 0, 1, 2, 2, 3, 4, 5]),
    EqualizerPreset('Flat', flat),
    EqualizerPreset('Jazz', <double>[3, 2, 1, 1, 1, 0, 2, 3, 4, 4]),
    EqualizerPreset('Pop', <double>[1, 2, 3, 3, 2, 0, 1, 2, 3, 3]),
    EqualizerPreset('Rock', <double>[5, 4, 2, 0, 0, 1, 3, 4, 4, 4]),
    EqualizerPreset('Soft', <double>[3, 2, 1, 0, 1, 2, 3, 3, 3, 2]),
    EqualizerPreset('Techno', <double>[5, 4, 2, 0, 2, 2, 3, 4, 4, 4]),
    EqualizerPreset('Treble Only', <double>[0, 0, 0, 0, 1, 2, 4, 6, 8, 9]),
  ];

  static const List<EqualizerPreset> video = <EqualizerPreset>[
    EqualizerPreset('Cinema', <double>[5, 4, 3, 2, 1, 0, 1, 2, 3, 4]),
    EqualizerPreset('Documentary (Dialogue)', <double>[0, 0, 0, 2, 4, 5, 4, 2, 0, 0]),
    EqualizerPreset('Flat', flat),
    EqualizerPreset('Music Video (Bass Booster)', <double>[7, 6, 5, 4, 2, 1, 0, 1, 2, 2]),
  ];
}
