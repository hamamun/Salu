import 'package:flutter/foundation.dart';

import 'channel_grouping.dart';

/// The channel list's view choices — grouping mode, open accordion group,
/// and whether a search is flattening the list.
///
/// Owned here instead of the panel widget so Prev/Next step the same
/// order the panel shows even when the panel is closed or the step comes
/// from the keyboard. Still a pure view choice: it never touches the
/// queue itself (M45) — only the order Prev/Next walk. A fresh channel
/// load resets it through [reset] (M6/M-7).
class ChannelViewService {
  ChannelViewService._internal();

  /// The one and only channel view state for the whole app.
  static final ChannelViewService instance = ChannelViewService._internal();

  /// The grouping the viewer chose — Flat until they say otherwise (M6).
  final ValueNotifier<ChannelGroupMode> groupMode =
      ValueNotifier<ChannelGroupMode>(ChannelGroupMode.flat);

  /// The accordion's one open group (its stable key), or `null` while
  /// every group is collapsed. A stale key simply opens nothing.
  final ValueNotifier<String?> openGroup = ValueNotifier<String?>(null);

  /// Whether a search is flattening the list (§10.3): the grouping is
  /// suspended, not forgotten — and Prev/Next suspend with it, stepping
  /// raw list order until the search clears.
  final ValueNotifier<bool> searching = ValueNotifier<bool>(false);

  /// A new channel load: the view starts blank — Flat, accordion closed,
  /// no search.
  void reset() {
    groupMode.value = ChannelGroupMode.flat;
    openGroup.value = null;
    searching.value = false;
  }
}
