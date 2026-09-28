part of 'settings_dialog.dart';

// ── Associations tab (association.md §4) ──────────────────────────────────
//
// Labels, values and marks only (follow.md rule 1). Ticks are a draft; the
// apply mark writes it, the revert mark drops it, and both sit in a
// reserved slot so nothing shifts. Associations are Windows state, not
// preferences: no group reset marks, and the master reset never reaches
// here.

class _AssociationsTab extends StatefulWidget {
  const _AssociationsTab();

  @override
  State<_AssociationsTab> createState() => _AssociationsTabState();
}

class _AssociationsTabState extends State<_AssociationsTab> {
  AssociationService get _service => AssociationService.instance;
  late Set<String> _draft;

  @override
  void initState() {
    super.initState();
    _service.refresh();
    _draft = Set<String>.of(_service.associated.value);
    _service.associated.addListener(_onRegistryChanged);
  }

  @override
  void dispose() {
    _service.associated.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    if (!mounted) return;
    setState(() => _draft = Set<String>.of(_service.associated.value));
  }

  bool get _dirty => !setEquals(_draft, _service.associated.value);

  void _toggle(String ext) => setState(() {
        if (!_draft.remove(ext)) _draft.add(ext);
      });

  void _toggleGroup(AssociationGroup group) => setState(() {
        final List<String> exts = group.extensions;
        if (exts.every(_draft.contains)) {
          _draft.removeAll(exts);
        } else {
          _draft.addAll(exts);
        }
      });

  void _apply() {
    final Set<String> before = Set<String>.of(_service.associated.value);
    _service.apply(Set<String>.of(_draft));
    OsdController.instance.show(OsdUndoCard(
      label: 'Associations applied',
      onUndo: () => _service.apply(before),
    ));
  }

  void _revert() =>
      setState(() => _draft = Set<String>.of(_service.associated.value));

  @override
  Widget build(BuildContext context) {
    return _TabBody(
      children: <Widget>[
        const _Group(caption: 'Default player', rows: <Widget>[_DefaultRow()]),
        _groupGap,
        ValueListenableBuilder<Set<String>>(
          valueListenable: _service.defaults,
          builder: (BuildContext context, Set<String> defaults, Widget? _) =>
              Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final AssociationGroup group in AssociationGroup.values)
                _ExtensionGroup(
                  group: group,
                  draft: _draft,
                  defaults: defaults,
                  onToggle: _toggle,
                  onToggleGroup: () => _toggleGroup(group),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 26,
          child: _dirty
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    _MarkButton(
                      icon: Icons.undo,
                      tooltip: 'Revert',
                      onPressed: _revert,
                    ),
                    const SizedBox(width: 4),
                    _MarkButton(
                      icon: Icons.check,
                      tooltip: 'Apply',
                      onPressed: _apply,
                    ),
                  ],
                )
              : null,
        ),
        _groupGap,
        const _Group(caption: 'Right-click', rows: <Widget>[_ContextMenuRow()]),
      ],
    );
  }
}

/// "Windows default · 18 / 35" + the door into Windows Default apps.
class _DefaultRow extends StatelessWidget {
  const _DefaultRow();

  @override
  Widget build(BuildContext context) {
    final AssociationService service = AssociationService.instance;
    void open() {
      service.openDefaultApps();
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: service.defaults,
      builder: (BuildContext context, Set<String> defaults, Widget? _) => _Row(
        label: 'Windows default',
        value: '${defaults.length} / ${allAssociableExtensions.length}',
        onTap: open,
        trailing: _MarkButton(
          icon: Icons.open_in_new,
          tooltip: 'Open Windows default apps',
          onPressed: open,
        ),
      ),
    );
  }
}

/// "Play with SALU" + "Add to SALU queue" — one switch for both verbs.
class _ContextMenuRow extends StatelessWidget {
  const _ContextMenuRow();

  @override
  Widget build(BuildContext context) {
    final AssociationService service = AssociationService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: service.contextMenu,
      builder: (BuildContext context, bool on, Widget? _) => _Row(
        label: 'Play · Add to queue',
        tooltip: 'Explorer right-click menu',
        onTap: () => service.setContextMenu(!on),
        trailing: _SaluSwitch(on: on),
      ),
    );
  }
}

/// One extension group: caption + tri-state group box, then a wrap of
/// extension chips.
class _ExtensionGroup extends StatelessWidget {
  const _ExtensionGroup({
    required this.group,
    required this.draft,
    required this.defaults,
    required this.onToggle,
    required this.onToggleGroup,
  });

  final AssociationGroup group;
  final Set<String> draft;
  final Set<String> defaults;
  final ValueChanged<String> onToggle;
  final VoidCallback onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final List<String> exts = group.extensions;
    final int ticked = exts.where(draft.contains).length;
    final bool? state =
        ticked == 0 ? false : (ticked == exts.length ? true : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: SizedBox(
              height: 22,
              child: Row(
                children: <Widget>[
                  Text(group.label.toUpperCase(), style: _captionStyle),
                  const Spacer(),
                  Tooltip(
                    message: 'Select all ${group.label.toLowerCase()}',
                    waitDuration: const Duration(milliseconds: 400),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggleGroup,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: _CheckBox(state: state),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String ext in exts)
                  _ExtChip(
                    ext: ext,
                    checked: draft.contains(ext),
                    isDefault: defaults.contains(ext),
                    onTap: () => onToggle(ext),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One extension: a box and its name. Accent name = SALU is the real
/// Windows default for it right now.
class _ExtChip extends StatefulWidget {
  const _ExtChip({
    required this.ext,
    required this.checked,
    required this.isDefault,
    required this.onTap,
  });

  final String ext;
  final bool checked;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  State<_ExtChip> createState() => _ExtChipState();
}

class _ExtChipState extends State<_ExtChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Widget chip = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 26,
          width: 76,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? _rowHover : Colors.transparent,
            border: Border.all(
              color: widget.checked ? _pillLine : AppColors.surfaceOutline,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              _CheckBox(state: widget.checked),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.ext.substring(1),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.2,
                    color: widget.isDefault
                        ? AppColors.accent
                        : (widget.checked
                            ? AppColors.textPrimary
                            : AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!widget.isDefault) return chip;
    return Tooltip(
      message: 'Windows default',
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }
}

/// SALU's thin checkbox: true = tick, null = dash (part of a group),
/// false = empty outline.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.state});

  final bool? state;

  @override
  Widget build(BuildContext context) {
    final bool on = state != false;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: on ? _pillFill : Colors.transparent,
        border: Border.all(
          color: on ? AppColors.accent : AppColors.textSecondary,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(3.5),
      ),
      child: on
          ? Icon(
              state == true ? Icons.check : Icons.remove,
              size: 11,
              color: AppColors.accent,
            )
          : null,
    );
  }
}
