import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/user_location_model.dart';
import '../services/gstr_report_service.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../utils/download_bytes.dart';

/// Admin invoice / GSTR reports — data from Firestore (bill `items` JSON on each doc).
class ReportsScreen extends StatefulWidget {
  final String userId;
  final String? userDocId;
  final String? userName;

  const ReportsScreen({
    super.key,
    required this.userId,
    this.userDocId,
    this.userName,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _service = GstrReportService();

  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  String? _selectedLocationId;
  bool _showRegularBillsOnly = true;

  bool _loadingMeta = true;
  bool _generatingInvoice = false;
  bool _generatingItems = false;
  bool _generatingGstr = false;
  String? _metaError;

  String? _resolvedUserDocId;
  GstrBusinessInfo? _business;
  List<UserLocationModel> _locations = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingMeta = true;
      _metaError = null;
    });
    try {
      final docId = await _resolveUserDocId();
      if (docId == null) {
        throw Exception('User document not found for ${widget.userId}');
      }
      final business = await _service.loadBusinessInfo(docId);
      final locations = await _service.loadLocations(docId);
      if (!mounted) return;
      setState(() {
        _resolvedUserDocId = docId;
        _business = business;
        _locations = locations;
        _showRegularBillsOnly = business.gstType == GstType.regular;
        _loadingMeta = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _metaError = e.toString();
        _loadingMeta = false;
      });
    }
  }

  Future<String?> _resolveUserDocId() async {
    if ((widget.userDocId ?? '').trim().isNotEmpty) {
      return widget.userDocId!.trim();
    }
    final uid = widget.userId.trim();
    if (uid.isEmpty) return null;

    final byField = await FirebaseFirestore.instance
        .collection('users')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();
    if (byField.docs.isNotEmpty) return byField.docs.first.id;

    final direct = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (direct.exists) return direct.id;
    return null;
  }

  bool _validateDateRange() {
    final from = DateTime(_dateFrom.year, _dateFrom.month, _dateFrom.day);
    final to = DateTime(_dateTo.year, _dateTo.month, _dateTo.day);
    if (to.isBefore(from)) {
      _snack('Date to must be on or after date from', Colors.orange);
      return false;
    }
    return true;
  }

  void _snack(String msg, [Color? color]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? Colors.grey[800]),
    );
  }

  String _locationLabel() {
    final id = _selectedLocationId;
    if (id == null || id.isEmpty) return 'All locations';
    if (id == kDefaultLocationFilterId) return 'Default location';
    for (final l in _locations) {
      if (l.id == id) return l.name.isEmpty ? l.id : l.name;
    }
    return id;
  }

  Future<void> _runInvoiceList() async {
    if (!_validateDateRange() || _resolvedUserDocId == null || _business == null) {
      return;
    }
    setState(() => _generatingInvoice = true);
    try {
      final bills = await _service.fetchBillsInRange(
        userDocId: _resolvedUserDocId!,
        from: _dateFrom,
        to: _dateTo,
      );
      final profileIds = await _service.resolveLocationProfileIds(
        userDocId: _resolvedUserDocId!,
        selectedLocationId: _selectedLocationId,
        locations: _locations,
      );
      final entries = _service.buildSaleBillEntries(
        bills: bills,
        locationProfileIds: profileIds,
        regularOnly: _showRegularBillsOnly,
        forGstr: false,
      );
      if (entries.isEmpty) {
        _snack('No invoices found in the selected date range.', Colors.orange);
        return;
      }
      final result = await _service.generateInvoiceListExcel(
        business: _business!,
        from: _dateFrom,
        to: _dateTo,
        saleEntries: entries,
        locationLabel: _locationLabel(),
      );
      await downloadBytes(result.bytes, result.filename);
      _snack(
        'Downloaded ${result.invoiceCount} invoice(s): ${result.filename}',
        Colors.green,
      );
    } catch (e) {
      debugPrint('Invoice list report error: $e');
      _snack('Error generating invoice report: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _generatingInvoice = false);
    }
  }

  Future<void> _runInvoiceItems() async {
    if (!_validateDateRange() || _resolvedUserDocId == null || _business == null) {
      return;
    }
    setState(() => _generatingItems = true);
    try {
      final bills = await _service.fetchBillsInRange(
        userDocId: _resolvedUserDocId!,
        from: _dateFrom,
        to: _dateTo,
      );
      final profileIds = await _service.resolveLocationProfileIds(
        userDocId: _resolvedUserDocId!,
        selectedLocationId: _selectedLocationId,
        locations: _locations,
      );
      final entries = _service.buildSaleBillEntries(
        bills: bills,
        locationProfileIds: profileIds,
        regularOnly: _showRegularBillsOnly,
        forGstr: false,
      );
      final rows = _service.aggregateInvoiceItems(entries);
      if (rows.isEmpty) {
        _snack('No items sold in the selected date range.', Colors.orange);
        return;
      }
      final result = await _service.generateInvoiceItemsExcel(
        business: _business!,
        from: _dateFrom,
        to: _dateTo,
        rows: rows,
        locationLabel: _locationLabel(),
      );
      await downloadBytes(result.bytes, result.filename);
      _snack(
        'Downloaded item report (${rows.length} item(s)): ${result.filename}',
        Colors.green,
      );
    } catch (e) {
      debugPrint('Invoice items report error: $e');
      _snack('Error generating item list report: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _generatingItems = false);
    }
  }

  Future<void> _runGstr() async {
    if (!_validateDateRange() || _resolvedUserDocId == null || _business == null) {
      return;
    }
    if (_business!.gstType == GstType.unregistered) {
      _snack('GSTR reports are not available for unregistered GST type.', Colors.orange);
      return;
    }

    setState(() => _generatingGstr = true);
    try {
      final bills = await _service.fetchBillsInRange(
        userDocId: _resolvedUserDocId!,
        from: _dateFrom,
        to: _dateTo,
      );
      final profileIds = await _service.resolveLocationProfileIds(
        userDocId: _resolvedUserDocId!,
        selectedLocationId: _selectedLocationId,
        locations: _locations,
      );
      final saleEntries = _service.buildSaleBillEntries(
        bills: bills,
        locationProfileIds: profileIds,
        regularOnly: _showRegularBillsOnly,
        forGstr: true,
        accountGstType: _business!.gstType,
      );
      final returnEntries = _service.buildReturnBillEntries(
        bills: bills,
        locationProfileIds: profileIds,
      );
      final profileCodeOrder =
          await _service.loadProfileCodeOrder(_resolvedUserDocId!);

      if (saleEntries.isEmpty) {
        _snack('No invoices found in the selected date range.', Colors.orange);
        return;
      }

      final result = await _service.generateGstrExcel(
        business: _business!,
        from: _dateFrom,
        to: _dateTo,
        saleEntries: saleEntries,
        returnEntries: returnEntries,
        profileCodeOrder: profileCodeOrder,
      );

      if (result.hsnConflictLines.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('HSN tax rate mismatch'),
            content: SingleChildScrollView(
              child: Text(
                'These HSN codes appear with different GST rates in GSTR-1 B2C HSN:\n\n'
                '${result.hsnConflictLines.join('\n')}\n\n'
                'Each HSN will be listed separately for each tax rate.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      }

      await downloadBytes(result.bytes, result.filename);
      _snack(
        'Downloaded ${result.filename} '
        '(${result.invoiceCount} invoices'
        '${result.returnCount > 0 ? ', ${result.returnCount} returns' : ''})',
        Colors.green,
      );
    } catch (e) {
      debugPrint('GSTR report error: $e');
      _snack('Error generating GSTR report: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _generatingGstr = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleName = widget.userName?.trim().isNotEmpty == true
        ? widget.userName!
        : widget.userId;
    final business = _business;
    final showGstReports =
        business != null && business.gstType != GstType.unregistered;
    final gstrButtonLabel = business?.gstType == GstType.regular
        ? 'Generate GSTR-1 report'
        : 'Generate composition report';

    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: AppColors.primaryText,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text(
          'Invoice Report — $titleName',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator())
          : _metaError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_metaError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _bootstrap,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Select a period and location, then open or export invoice / GSTR reports. '
                            'Bill line items are read from Firestore (JSON on each bill document).',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primaryGrey,
                              height: 1.4,
                            ),
                          ),
                          if (business != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'GST type: ${business.gstType.name}'
                              '${business.gstNumber.isNotEmpty ? ' · ${business.gstNumber}' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primaryText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (_locations.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('Filters'),
                            const SizedBox(height: 8),
                            _card(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedLocationId ?? '',
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Location',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('All locations'),
                                  ),
                                  const DropdownMenuItem(
                                    value: kDefaultLocationFilterId,
                                    child: Text('Default location'),
                                  ),
                                  ..._locations.where((l) => !l.isDefault).map(
                                        (l) => DropdownMenuItem(
                                          value: l.id,
                                          child: Text(
                                            l.name.isEmpty ? l.id : l.name,
                                          ),
                                        ),
                                      ),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedLocationId =
                                        (val == null || val.isEmpty) ? null : val;
                                  });
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _sectionLabel('Report period'),
                          const SizedBox(height: 8),
                          _card(
                            child: Column(
                              children: [
                                _dateRow(
                                  label: 'Date from',
                                  value: _dateFrom,
                                  onTap: () => _pickDate(isFrom: true),
                                ),
                                const SizedBox(height: 12),
                                _dateRow(
                                  label: 'Date to',
                                  value: _dateTo,
                                  onTap: () => _pickDate(isFrom: false),
                                ),
                              ],
                            ),
                          ),
                          if (business?.gstType == GstType.regular) ...[
                            const SizedBox(height: 20),
                            _sectionLabel('Bill type'),
                            const SizedBox(height: 8),
                            _card(
                              child: SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                value: _showRegularBillsOnly,
                                title: const Text('Regular bills only'),
                                subtitle: const Text(
                                  'Exclude composite bills from invoice and GSTR reports.',
                                ),
                                onChanged: (v) =>
                                    setState(() => _showRegularBillsOnly = v),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _sectionLabel('Reports'),
                          const SizedBox(height: 8),
                          _card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _actionButton(
                                  label: 'View invoices',
                                  loading: _generatingInvoice,
                                  onPressed: _runInvoiceList,
                                ),
                                const SizedBox(height: 12),
                                _actionButton(
                                  label: 'View invoice item report',
                                  loading: _generatingItems,
                                  onPressed: _runInvoiceItems,
                                ),
                                if (showGstReports) ...[
                                  const SizedBox(height: 12),
                                  _actionButton(
                                    label: gstrButtonLabel,
                                    loading: _generatingGstr,
                                    onPressed: _runGstr,
                                    primary: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _sectionLabel(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: Colors.grey[700],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _dateRow({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(DateFormat('dd-MM-yyyy').format(value)),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              primary ? AppColors.primaryGreen : AppColors.primaryGreen.withValues(alpha: 0.9),
          foregroundColor: Colors.white,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
