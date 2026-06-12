import 'package:flutter/material.dart';

import 'asset_pdf_viewer_screen.dart';

class RakatsScreen extends StatelessWidget {
  const RakatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Namaz Guide'), centerTitle: true),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: RakatsTableContent(),
      ),
    );
  }
}

class RakatsTableContent extends StatelessWidget {
  static const Map<String, String> _namazTariqaPdfAssets = <String, String>{
    'Namaz ka tariqa': 'assets/pdfs/namaz.pdf',
    'Eid ki namaz ka tariqa': 'assets/pdfs/eid.pdf',
    'Janaza ki namaz ka tariqa': 'assets/pdfs/janaza.pdf',
  };
  final bool showTitle;

  const RakatsTableContent({super.key, this.showTitle = true});

  static const Color _primary = Color(0xFF1A5C38);
  static const Color _border = Color(0xFFB9B199);
  static const Color _headerGreen = Color(0xFF2E7D4F);
  static const Color _nameRed = Color(0xFFC62828);
  static const Color _cellYellow = Color(0xFFF7E8B5);
  static const Color _badgeBlue = Color(0xFF3B4CC0);
  static const Color _badgeRed = Color(0xFFD32F2F);
  static const Color _badgeGreen = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final List<_RakatRow> rows = <_RakatRow>[
      _RakatRow(
        name: 'Fajar',
        cells: [
          _RakatCell.badge('2', _badgeBlue),
          _RakatCell.badge('2', _badgeRed),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('4', bold: true),
        ],
      ),
      _RakatRow(
        name: 'Zohar',
        cells: [
          _RakatCell.badge('4', _badgeBlue),
          _RakatCell.badge('4', _badgeRed),
          _RakatCell.badge('2', _badgeBlue),
          _RakatCell.text('2'),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('12', bold: true),
        ],
      ),
      _RakatRow(
        name: 'Asar',
        cells: [
          _RakatCell.text('4'),
          _RakatCell.badge('4', _badgeRed),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('8', bold: true),
        ],
      ),
      _RakatRow(
        name: 'Maghrib',
        cells: [
          _RakatCell.text('-'),
          _RakatCell.badge('3', _badgeRed),
          _RakatCell.badge('2', _badgeBlue),
          _RakatCell.text('2'),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('7', bold: true),
        ],
      ),
      _RakatRow(
        name: 'Isha',
        cells: [
          _RakatCell.text('4'),
          _RakatCell.badge('4', _badgeRed),
          _RakatCell.badge('2', _badgeBlue),
          _RakatCell.text('2'),
          _RakatCell.badge('3', _badgeGreen),
          _RakatCell.text('2'),
          _RakatCell.text('17', bold: true),
        ],
      ),
      _RakatRow(
        name: 'Juma',
        cells: [
          _RakatCell.badge('4', _badgeBlue),
          _RakatCell.badge('2', _badgeRed),
          _RakatCell.badge('4+2', _badgeBlue),
          _RakatCell.text('-'),
          _RakatCell.text('-'),
          _RakatCell.text('2'),
          _RakatCell.text('14', bold: true),
        ],
      ),
    ];

    const _RakatTableSizing sizing = _RakatTableSizing(
      headerFont: 8,
      nameFont: 10,
      cellFont: 10,
      badgeFont: 9,
      cellHPadding: 4,
      cellVPadding: 7,
      badgeMinSize: 22,
      badgePadding: 4,
      titleFont: 14,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tableWidth = constraints.maxWidth < 360
            ? 360
            : constraints.maxWidth;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showTitle) ...[
                Text(
                  'TABLE OF PRAYER(RAKATS)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: sizing.titleFont,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Table(
                        border: TableBorder.symmetric(
                          inside: BorderSide(color: _border, width: 1),
                        ),
                        columnWidths: const <int, TableColumnWidth>{
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(0.75),
                          2: FlexColumnWidth(0.75),
                          3: FlexColumnWidth(1),
                          4: FlexColumnWidth(0.75),
                          5: FlexColumnWidth(0.75),
                          6: FlexColumnWidth(0.75),
                          7: FlexColumnWidth(1),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          _headerRow(sizing),
                          for (int i = 0; i < rows.length; i++)
                            _dataRow(rows[i], sizing, zebra: i.isOdd),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildNamazTariqaSection(context),
              const SizedBox(height: 18),
              _buildNaflSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNaflSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1E3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0D8C7)),
          ),
          child: const Center(
            child: Text(
              'NAFL NAMAZ DETAILS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Color(0xFF1A5C38),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _NaflCard(
          title: 'Tahajjud',
          time:
              'Isha ke baad se Fajr ke shuru waqt se pehle tak (behtareen waqt raat ka aakhri hissa)',
          rakat: '2 se 12 (2+2+2...)',
          fazilat: const [
            'Allah ki khas rehmat',
            'Dua qubool hoti hai',
            'Gunahon ki maafi',
            'Dil ka sukoon',
            'Jannat mein buland darja',
          ],
        ),
        _NaflCard(
          title: 'Ishraq',
          time:
              'Fajr namaz ke end time ke 20 minute baad (jab suraj poori tarah nikal aaye) se 9 baje se pehle tak.\n(Waqt shuru hone ke baad turant padhna afzal hai.)',
          rakat: '4 (2 + 2)',
          fazilat: const [
            '1 Hajj aur 1 Umrah ka sawab',
            'Din ki ibadat ki shuruaat barkat ke saath hoti hai',
            'Allah ki raza hasil hoti hai',
            'Rizq mein barkat hoti hai',
            'Dil ko sukoon milta hai',
          ],
        ),
        _NaflCard(
          title: 'Chasht',
          time:
              'Ishraq ke baad se (suraj achhi tarah roshan hone ke baad, yani 10 AM ya 11 AM se aadhe din yani 12:00 PM se pehle tak)',
          rakat: '2 se 12',
          fazilat: const [
            'Jism ke har joint ka sadqa ada ho jata hai',
            'Rizq (income) mein barkat aur aasani',
            'Allah ki taraf se madad aati hai',
            'Ghar mein sukoon aur rehmat hoti hai',
          ],
        ),
        _NaflCard(
          title: 'Awwabeen',
          time: 'Maghrib ke baad se Isha tak',
          rakat: '6 (2+2+2)',
          fazilat: const [
            '12 saal ki ibadat ka sawab',
            'Dil ka noor',
            'Allah ke qareeb',
            'Jannat mein buland darja',
          ],
        ),
      ],
    );
  }

  Widget _buildNamazTariqaSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1E3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0D8C7)),
          ),
          child: const Column(
            children: [
              Center(
                child: Text(
                  'NAMAZ KA TARIQA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF1A5C38),
                  ),
                ),
              ),
              SizedBox(height: 6),
              Text(
                'For Masle-Masail contact to Ulamas.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _NamazTariqaCard(
          title: 'Namaz ka tariqa',
          onTap: () => _openPdfViewer(context, 'Namaz ka tariqa'),
        ),
        _NamazTariqaCard(
          title: 'Eid ki namaz ka tariqa',
          onTap: () => _openPdfViewer(context, 'Eid ki namaz ka tariqa'),
        ),
        _NamazTariqaCard(
          title: 'Janaza ki namaz ka tariqa',
          onTap: () => _openPdfViewer(context, 'Janaza ki namaz ka tariqa'),
        ),
      ],
    );
  }

  void _openPdfViewer(BuildContext context, String title) {
    final String assetPath =
        _namazTariqaPdfAssets[title] ?? _namazTariqaPdfAssets.values.first;
    Navigator.of(
      context,
    ).push(AssetPdfViewerScreen.route(title: title, assetPath: assetPath));
  }

  TableRow _headerRow(_RakatTableSizing sizing) {
    final TextStyle headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: sizing.headerFont,
      color: _primary,
    );

    return TableRow(
      decoration: const BoxDecoration(color: _headerGreen),
      children: [
        _Cell(
          text: 'Namaz',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Sunnath',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Farz',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Sunnath',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Nafli',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Vitar',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Nafli',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
        _Cell(
          text: 'Total',
          style: headerStyle,
          dark: true,
          fit: true,
          padding: sizing.cellPadding,
        ),
      ],
    );
  }

  TableRow _dataRow(
    _RakatRow row,
    _RakatTableSizing sizing, {
    bool zebra = false,
  }) {
    return TableRow(
      decoration: BoxDecoration(
        color: zebra ? const Color(0xFFFDF5D6) : _cellYellow,
      ),
      children: [
        _NameCell(text: row.name, sizing: sizing),
        for (final cell in row.cells)
          _RakatCellWidget(cell: cell, sizing: sizing),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool dark;
  final bool fit;
  final EdgeInsetsGeometry padding;

  const _Cell({
    required this.text,
    required this.style,
    this.dark = false,
    this.fit = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: fit
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: style.copyWith(color: dark ? Colors.white : style.color),
              ),
            )
          : Text(
              text,
              textAlign: TextAlign.center,
              style: style.copyWith(color: dark ? Colors.white : style.color),
            ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final String text;
  final _RakatTableSizing sizing;
  const _NameCell({required this.text, required this.sizing});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RakatsTableContent._nameRed,
      padding: sizing.cellPadding,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: sizing.nameFont,
          ),
        ),
      ),
    );
  }
}

class _RakatRow {
  final String name;
  final List<_RakatCell> cells;
  const _RakatRow({required this.name, required this.cells});
}

class _RakatCell {
  final String value;
  final Color? badgeColor;
  final bool bold;

  const _RakatCell._(this.value, {this.badgeColor, this.bold = false});

  factory _RakatCell.text(String value, {bool bold = false}) =>
      _RakatCell._(value, bold: bold);
  factory _RakatCell.badge(String value, Color color) =>
      _RakatCell._(value, badgeColor: color);
}

class _RakatCellWidget extends StatelessWidget {
  final _RakatCell cell;
  final _RakatTableSizing sizing;
  const _RakatCellWidget({required this.cell, required this.sizing});

  @override
  Widget build(BuildContext context) {
    final bool isPlusValue = cell.value.contains('+');
    final TextStyle baseStyle = TextStyle(
      fontSize: cell.value.length > 2 ? sizing.cellFont - 1 : sizing.cellFont,
      fontWeight: cell.bold ? FontWeight.w800 : FontWeight.w700,
      color: const Color(0xFF1A2B22),
    );

    return Container(
      color: RakatsTableContent._cellYellow,
      padding: EdgeInsets.symmetric(
        vertical: sizing.cellVPadding,
        horizontal: sizing.cellHPadding,
      ),
      alignment: Alignment.center,
      child: cell.badgeColor == null
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                cell.value,
                textAlign: TextAlign.center,
                style: baseStyle,
              ),
            )
          : Container(
              constraints: BoxConstraints(
                minWidth: sizing.badgeMinSize,
                minHeight: sizing.badgeMinSize,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: sizing.badgePadding,
                vertical: sizing.badgePadding,
              ),
              decoration: BoxDecoration(
                color: cell.badgeColor,
                borderRadius: BorderRadius.circular(sizing.badgeMinSize),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cell.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isPlusValue
                        ? sizing.badgeFont + 1
                        : cell.value.length > 2
                        ? sizing.badgeFont - 1
                        : sizing.badgeFont,
                  ),
                ),
              ),
            ),
    );
  }
}

class _RakatTableSizing {
  final double headerFont;
  final double nameFont;
  final double cellFont;
  final double badgeFont;
  final double cellHPadding;
  final double cellVPadding;
  final double badgeMinSize;
  final double badgePadding;
  final double titleFont;

  const _RakatTableSizing({
    required this.headerFont,
    required this.nameFont,
    required this.cellFont,
    required this.badgeFont,
    required this.cellHPadding,
    required this.cellVPadding,
    required this.badgeMinSize,
    required this.badgePadding,
    required this.titleFont,
  });

  EdgeInsets get cellPadding =>
      EdgeInsets.symmetric(horizontal: cellHPadding, vertical: cellVPadding);
}

class _NaflCard extends StatelessWidget {
  final String title;
  final String time;
  final String rakat;
  final List<String> fazilat;
  final String? note;

  const _NaflCard({
    required this.title,
    required this.time,
    required this.rakat,
    required this.fazilat,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      color: const Color(0xFFFFFCF3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          trailing: const Icon(Icons.expand_more, color: Color(0xFF1A5C38)),
          title: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: RakatsTableContent._primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: RakatsTableContent._primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: RakatsTableContent._primary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            _NaflDetailRow(label: 'Time', value: time),
            const SizedBox(height: 8),
            _NaflDetailRow(label: 'Rakat', value: rakat),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fazilat:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final item in fazilat) _NaflBullet(text: item),
            if (note != null && note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Note:',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NaflDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _NaflDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

class _NaflBullet extends StatelessWidget {
  final String text;
  const _NaflBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 13, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NamazTariqaCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _NamazTariqaCard({
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      color: const Color(0xFFFFFCF3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: RakatsTableContent._primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  size: 14,
                  color: RakatsTableContent._primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: RakatsTableContent._primary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: RakatsTableContent._primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
