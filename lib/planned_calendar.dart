import 'package:flutter/material.dart';

import 'models.dart';

class PlannedCalendar extends StatefulWidget {
  final DateTime selected;
  final List<DayPlan> plans;
  final ValueChanged<DateTime> onChanged;
  const PlannedCalendar({
    super.key,
    required this.selected,
    required this.plans,
    required this.onChanged,
  });
  @override
  State<PlannedCalendar> createState() => _PlannedCalendarState();
}

class _PlannedCalendarState extends State<PlannedCalendar> {
  late DateTime month;
  @override
  void initState() {
    super.initState();
    month = DateTime(widget.selected.year, widget.selected.month);
  }

  @override
  void didUpdateWidget(covariant PlannedCalendar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      month = DateTime(widget.selected.year, widget.selected.month);
    }
  }

  void changeMonth(int delta) =>
      setState(() => month = DateTime(month.year, month.month + delta));
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        local = MaterialLocalizations.of(context),
        days = DateUtils.getDaysInMonth(month.year, month.month),
        offset = (month.weekday + 6) % 7;
    final plans = {for (final p in widget.plans) p.date: p};
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Mes anterior',
              onPressed: month.year == 2020 && month.month == 1
                  ? null
                  : () => changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                local.formatMonthYear(month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Mes siguiente',
              onPressed: month.year == 2100 && month.month == 12
                  ? null
                  : () => changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final day in ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
              Expanded(
                child: Center(
                  child: Text(day, style: theme.textTheme.labelMedium),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: offset + days,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 48,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            if (index < offset) return const SizedBox();
            final day = DateTime(month.year, month.month, index - offset + 1),
                key = dateKey(day),
                plan = plans[key],
                selected = DateUtils.isSameDay(day, widget.selected),
                today = DateUtils.isSameDay(day, DateTime.now());
            return Semantics(
              label:
                  '${local.formatFullDate(day)}${plan == null
                      ? ''
                      : plan.worn
                      ? ' · Outfit usado'
                      : ' · Outfit planificado'}',
              selected: selected,
              button: true,
              child: Tooltip(
                message: plan == null
                    ? 'Sin outfit'
                    : plan.worn
                    ? 'Outfit usado'
                    : 'Outfit planificado',
                child: InkWell(
                  key: ValueKey('calendar-$key'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onChanged(day),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : plan != null
                          ? theme.colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      border: today
                          ? Border.all(color: theme.colorScheme.primary)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: selected
                                ? theme.colorScheme.onPrimary
                                : null,
                            fontWeight: plan != null ? FontWeight.bold : null,
                          ),
                        ),
                        if (plan != null)
                          Icon(
                            plan.worn ? Icons.check_circle : Icons.circle,
                            size: 8,
                            color: selected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 16,
          children: [Text('● Outfit planificado'), Text('✓ Outfit usado')],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
