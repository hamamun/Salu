import 'package:flutter/widgets.dart';

/// Global key attached to the OSC bar container.
///
/// Child widgets (like the timeline's hover thumbnail preview) need to know
/// the bar's on-screen rectangle to position a floating overlay relative to
/// it. Keeping the key in its own file avoids a circular import between
/// `osc_panel.dart` (which builds the bar) and `timeline_slider.dart` (which
/// reads it).
final GlobalKey oscBarKey = GlobalKey();
