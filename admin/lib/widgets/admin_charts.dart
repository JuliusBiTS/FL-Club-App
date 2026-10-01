import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The club's chart palette: olive first (the brand), then colours that stay
/// distinguishable from it and from each other, in light and dark.
List<Color> chartPalette(BuildContext context) => <Color>[
      FlcColors.accent(context),
      const Color(0xFFB7CC6C),
      const Color(0xFF8A6D3B),
      const Color(0xFF5E7F9A),
      const Color(0xFFB8860B),
      const Color(0xFF9A5E7F),
    ];

/// One white card with a title, an optional line of context, and the chart.
class ChartCard extends StatelessWidget {
  const ChartCard({required this.title, required this.child, this.subtitle, this.trailing, this.width, super.key});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(FlcSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(title, style: FlcTextStyles.h3)),
                  if (trailing != null) trailing!,
                ],
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: FlcSpace.xxs),
                Text(subtitle!, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context))),
              ],
              const SizedBox(height: FlcSpace.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyChart extends StatelessWidget {
  const EmptyChart(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 120,
        child: Center(child: Text(message, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)))),
      );
}

/// A nice round top for the y axis (e.g. 37 -> 40, 1130 -> 1200).
double niceMax(double v) {
  if (v <= 0) return 1;
  final double mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final double n = v / mag;
  final double step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return step * mag;
}

String compact(double v) => NumberFormat.compact(locale: 'en_GB').format(v);

/// Points on a time axis (day by day) as a smooth area line.
class AdminLineChart extends StatelessWidget {
  const AdminLineChart({required this.points, required this.format, this.height = 220, super.key});

  final List<(DateTime, double)> points;

  /// How a value reads in the tooltip (e.g. "£1,250" or "12 tickets").
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const EmptyChart('Nothing to show yet.');
    final Color color = FlcColors.accent(context);
    final Color muted = FlcColors.secondary(context);
    final double maxY = niceMax(points.map(((DateTime, double) p) => p.$2).reduce(math.max));
    const double minX = 0;
    final double maxX = math.max(1, points.length - 1).toDouble();
    final int labelEvery = math.max(1, (points.length / 6).ceil());

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (double _) => FlLine(color: muted.withValues(alpha: 0.18), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: maxY / 4,
                getTitlesWidget: (double v, TitleMeta meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(compact(v), style: FlcTextStyles.caption.copyWith(color: muted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (double v, TitleMeta meta) {
                  final int i = v.round();
                  if (i < 0 || i >= points.length || i % labelEvery != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(DateFormat('d MMM').format(points[i].$1), style: FlcTextStyles.caption.copyWith(color: muted)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> spots) => <LineTooltipItem>[
                for (final LineBarSpot s in spots)
                  LineTooltipItem(
                    '${DateFormat('EEE d MMM').format(points[s.x.round()].$1)}\n${format(s.y)}',
                    FlcTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: <FlSpot>[for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2)],
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: points.length <= 14),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.14)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical bars with a label under each (days, months…).
class AdminBarChart extends StatelessWidget {
  const AdminBarChart({required this.bars, required this.format, this.height = 200, super.key});

  final List<(String, double)> bars;
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || bars.every(((String, double) b) => b.$2 == 0)) return const EmptyChart('Nothing to show yet.');
    final Color color = FlcColors.accent(context);
    final Color muted = FlcColors.secondary(context);
    final double maxY = niceMax(bars.map(((String, double) b) => b.$2).reduce(math.max));
    final int labelEvery = math.max(1, (bars.length / 8).ceil());

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (double _) => FlLine(color: muted.withValues(alpha: 0.18), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: maxY / 4,
                getTitlesWidget: (double v, TitleMeta meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(compact(v), style: FlcTextStyles.caption.copyWith(color: muted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (double v, TitleMeta meta) {
                  final int i = v.round();
                  if (i < 0 || i >= bars.length || i % labelEvery != 0) return const SizedBox.shrink();
                  return SideTitleWidget(meta: meta, child: Text(bars[i].$1, style: FlcTextStyles.caption.copyWith(color: muted)));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (BarChartGroupData g, int gi, BarChartRodData rod, int ri) => BarTooltipItem(
                '${bars[gi].$1}\n${format(rod.toY)}',
                FlcTextStyles.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: <BarChartGroupData>[
            for (int i = 0; i < bars.length; i++)
              BarChartGroupData(
                x: i,
                barRods: <BarChartRodData>[
                  BarChartRodData(
                    toY: bars[i].$2,
                    color: color,
                    width: math.max(6, math.min(28, 520 / bars.length)),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A ring showing how a total splits (e.g. tickets by type), with a legend.
class AdminDonut extends StatelessWidget {
  const AdminDonut({required this.slices, required this.format, super.key});

  final List<(String, double)> slices;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final List<(String, double)> shown = slices.where(((String, double) s) => s.$2 > 0).toList();
    if (shown.isEmpty) return const EmptyChart('No tickets sold yet.');
    final List<Color> palette = chartPalette(context);
    final double total = shown.fold(0, (double a, (String, double) s) => a + s.$2);

    return Row(
      children: <Widget>[
        SizedBox(
          width: 150,
          height: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 44,
              sections: <PieChartSectionData>[
                for (int i = 0; i < shown.length; i++)
                  PieChartSectionData(value: shown[i].$2, color: palette[i % palette.length], radius: 22, showTitle: false),
              ],
            ),
          ),
        ),
        const SizedBox(width: FlcSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < shown.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: <Widget>[
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: palette[i % palette.length], shape: BoxShape.circle)),
                      const SizedBox(width: FlcSpace.xs),
                      Expanded(child: Text(shown[i].$1, overflow: TextOverflow.ellipsis)),
                      Text('${format(shown[i].$2)} · ${(shown[i].$2 / total * 100).round()}%', style: FlcTextStyles.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled bar: "Standard — 42 of 70". Plain widgets, no chart library.
class FillBar extends StatelessWidget {
  const FillBar({required this.label, required this.value, required this.of, this.trailing, this.color, super.key});

  final String label;
  final int value;

  /// The total it fills; 0 means "no limit set".
  final int of;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final double fraction = of <= 0 ? 0 : (value / of).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlcSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(of > 0 ? '$value of $of' : '$value', style: FlcTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
              if (trailing != null) ...<Widget>[const SizedBox(width: FlcSpace.sm), Text(trailing!, style: FlcTextStyles.bodySmall)],
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: of <= 0 ? null : fraction,
              minHeight: 8,
              backgroundColor: FlcColors.secondary(context).withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color ?? FlcColors.accent(context)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single big number with a caption — the "tiles" row at the top of a page.
class StatTile extends StatelessWidget {
  const StatTile({required this.label, required this.value, this.caption, this.icon, super.key});

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(FlcSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[Icon(icon, size: 18, color: FlcColors.secondary(context)), const SizedBox(width: FlcSpace.xs)],
                  Expanded(child: Text(label, style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)))),
                ],
              ),
              const SizedBox(height: FlcSpace.xs),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              if (caption != null) Text(caption!, style: FlcTextStyles.caption.copyWith(color: FlcColors.secondary(context))),
            ],
          ),
        ),
      ),
    );
  }
}
