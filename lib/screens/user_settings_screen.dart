import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';

/// Per-user app settings editor (`users/{id}/settings/app`).
/// Opened from each user card's Settings button.
class UserSettingsScreen extends StatefulWidget {
  final String? userId;
  final String? userDocId;
  final String? userName;

  const UserSettingsScreen({
    super.key,
    this.userId,
    this.userDocId,
    this.userName,
  });

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;
  Object? _buildError;
  StackTrace? _buildStack;

  late final String _docId;

  String _gstType = 'Regular';
  String _labelSize = kDefaultLabelSize;
  String _receiptSize = kDefaultReceiptSize;
  int _labelPrinterDpi = 203;
  String _labelPrinterName = kDefaultLabelPrinterName;
  String _labelGap = kDefaultLabelGap;
  String _jewelTagPrintDirection = 'left';
  bool _labelTemplateDefault = true;
  bool _labelTemplateCustom = false;
  bool _enableHsn = false;
  String _attributeNamePosition = kAttributeNamePositionBefore;
  bool _showTaxOnBill = false;
  bool _enableServices = false;
  bool _disableBillTypeConfirmation = false;
  bool _repeatScanning = false;
  bool _externalScanner = false;
  bool _scannedItemConfirmation = true;
  bool _applyRoundOff = true;
  String _roundOffFrequency = kRoundOffFrequencyNearest10;
  bool _priceMaskingEnabled = false;
  late final List<TextEditingController> _maskDigitControllers;
  bool _adminMode = true;
  bool _voiceBillingEnabled = false;
  bool _barcodeScanningEnabled = true;
  bool _scanServiceOrders = false;
  bool _scanBills = false;
  bool _directItemAdditionEnabled = true;
  bool _flashOnScan = false;
  bool _additionalQuantityOptionEnabled = false;
  bool _printJobName = false;
  bool _tableStyleBillingEnabled = false;
  bool _tableStyleServiceItemsEnabled = false;
  bool _enableItemMrp = false;
  bool _enableItemDiscount = false;
  bool _editPriceWhileBilling = false;
  String _taxRateType = 'Inclusive';
  double _compositionTaxRate = 1.0;

  @override
  void initState() {
    super.initState();
    _docId = (widget.userDocId?.trim().isNotEmpty == true)
        ? widget.userDocId!.trim()
        : (widget.userId?.trim() ?? '');
    _maskDigitControllers = List.generate(
      10,
      (i) => TextEditingController(text: '$i'),
    );
    _loadSettings();
  }

  @override
  void dispose() {
    for (final c in _maskDigitControllers) {
      c.dispose();
    }
    super.dispose();
  }

  TextStyle get _descStyle => TextStyle(fontSize: 12, color: Colors.grey[600]);

  Widget _label(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
        ),
      );

  Widget _desc(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: _descStyle),
      );

  /// Plain [DropdownButton] (not FormField) — avoids Flutter 3.33+ FormField
  /// initialValue assert/layout issues that blanked this screen on web.
  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final T safeValue = items.any((e) => e.value == value)
        ? value
        : (items.first.value as T);
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: safeValue,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle, style: _descStyle),
      value: value,
      onChanged: onChanged,
    );
  }

  void _normalizeLabelTemplateSelection() {
    if (!_labelTemplateDefault && !_labelTemplateCustom) {
      _labelTemplateDefault = true;
    }
  }

  void _sanitizeDropdownValues() {
    if (_gstType != 'Regular' &&
        _gstType != 'Composition' &&
        _gstType != 'Unregistered') {
      _gstType = 'Regular';
    }
    _labelSize = labelSizeFromRemote(_labelSize);
    _receiptSize = receiptSizeFromRemote(_receiptSize);
    _labelPrinterName = labelPrinterNameFromRemote(_labelPrinterName);
    _labelGap = labelGapFromRemote(_labelGap);
    _jewelTagPrintDirection =
        jewelTagPrintDirectionFromRemote(_jewelTagPrintDirection);
    _attributeNamePosition =
        attributeNamePositionFromRemote(_attributeNamePosition);
    _labelPrinterDpi = labelPrinterDpiFromRemote(_labelPrinterDpi);
    _roundOffFrequency = roundOffFrequencyFromRemote(_roundOffFrequency);
    if (_taxRateType != 'Inclusive' && _taxRateType != 'Exclusive') {
      _taxRateType = 'Inclusive';
    }
    if (_compositionTaxRate != 1.0 &&
        _compositionTaxRate != 5.0 &&
        _compositionTaxRate != 6.0) {
      if (_compositionTaxRate <= 2.5) {
        _compositionTaxRate = 1.0;
      } else if (_compositionTaxRate <= 5.5) {
        _compositionTaxRate = 5.0;
      } else {
        _compositionTaxRate = 6.0;
      }
    }
  }

  void _applyPayload(Map<String, dynamic> data) {
    if (data['gstType'] != null) {
      final gstTypeValue = data['gstType'].toString();
      if (gstTypeValue == 'Regular' ||
          gstTypeValue == 'Composition' ||
          gstTypeValue == 'Unregistered') {
        _gstType = gstTypeValue;
      }
    }
    if (data['labelSize'] != null) {
      _labelSize = labelSizeFromRemote(data['labelSize']);
    }
    if (data['receiptSize'] != null) {
      _receiptSize = receiptSizeFromRemote(data['receiptSize']);
    }
    if (data['labelPrinterDpi'] != null) {
      _labelPrinterDpi = labelPrinterDpiFromRemote(data['labelPrinterDpi']);
    }
    if (data['labelPrinterName'] != null) {
      _labelPrinterName = labelPrinterNameFromRemote(data['labelPrinterName']);
    }
    if (data['labelGap'] != null) {
      _labelGap = labelGapFromRemote(data['labelGap']);
    }
    if (data['jewelTagPrintDirection'] != null) {
      _jewelTagPrintDirection =
          jewelTagPrintDirectionFromRemote(data['jewelTagPrintDirection']);
    }
    applyLabelTemplateSettingsFromRemote(data);
    _labelTemplateDefault = LABEL_TEMPLATE_DEFAULT_ENABLED;
    _labelTemplateCustom = LABEL_TEMPLATE_CUSTOM_ENABLED;
    _normalizeLabelTemplateSelection();
    if (data['enableHsn'] != null) _enableHsn = data['enableHsn'] == true;
    if (data['attributeNamePosition'] != null) {
      _attributeNamePosition =
          attributeNamePositionFromRemote(data['attributeNamePosition']);
    }
    if (data['showTaxOnBill'] != null) {
      _showTaxOnBill = data['showTaxOnBill'] == true;
    }
    if (data['enableServices'] != null) {
      _enableServices = data['enableServices'] == true;
    }
    if (data['scanServiceOrders'] != null) {
      _scanServiceOrders = data['scanServiceOrders'] == true;
    }
    if (data['scanBills'] != null) _scanBills = data['scanBills'] == true;
    if (data['applyRoundOff'] != null) {
      _applyRoundOff = data['applyRoundOff'] == true;
    }
    if (data['roundOffFrequency'] != null) {
      _roundOffFrequency =
          roundOffFrequencyFromRemote(data['roundOffFrequency']);
    }
    if (data['priceMaskingEnabled'] != null) {
      _priceMaskingEnabled = data['priceMaskingEnabled'] == true;
    }
    if (data['maskedJson'] != null) {
      final m = normalizedMaskedJsonFromValue(data['maskedJson']);
      for (int i = 0; i < 10; i++) {
        final k = '$i';
        _maskDigitControllers[i].text = m[k] ?? k;
      }
    }
    _disableBillTypeConfirmation =
        disableBillTypeConfirmationFromRemoteSettings(data);
    if (data['additionalQuantityOptionEnabled'] != null) {
      _additionalQuantityOptionEnabled =
          data['additionalQuantityOptionEnabled'] == true;
    }
    if (data['printJobName'] != null) {
      _printJobName = data['printJobName'] == true;
    }
    if (data['enableTableStyleBilling'] != null) {
      _tableStyleBillingEnabled = data['enableTableStyleBilling'] == true;
    }
    if (data['enableTableStyleServiceItems'] != null) {
      _tableStyleServiceItemsEnabled =
          data['enableTableStyleServiceItems'] == true;
    }
    if (data['enableItemMrp'] != null || data['enableItemDiscount'] != null) {
      if (data['enableItemMrp'] != null) {
        _enableItemMrp = data['enableItemMrp'] == true;
      }
      if (data['enableItemDiscount'] != null) {
        _enableItemDiscount = data['enableItemDiscount'] == true;
      }
    } else if (data['enableMrpDiscount'] != null) {
      final legacy = data['enableMrpDiscount'] == true;
      _enableItemMrp = legacy;
      _enableItemDiscount = legacy;
    }
    if (data['editPriceWhileBilling'] != null) {
      _editPriceWhileBilling = data['editPriceWhileBilling'] == true;
    }
    if (data['adminMode'] != null) _adminMode = data['adminMode'] == true;
    if (data['taxRateType'] != null) {
      _taxRateType = data['taxRateType'].toString();
    }
    if (data['compositionTaxRate'] != null) {
      _compositionTaxRate = (data['compositionTaxRate'] as num).toDouble();
    }
    if (data['voiceBillingEnabled'] != null) {
      _voiceBillingEnabled = data['voiceBillingEnabled'] == true;
    }
    if (data['barcodeScanningEnabled'] != null) {
      _barcodeScanningEnabled = data['barcodeScanningEnabled'] == true;
    }
    if (data['directItemAdditionEnabled'] != null) {
      _directItemAdditionEnabled = data['directItemAdditionEnabled'] == true;
    }
    if (data['flashOnScan'] != null) {
      _flashOnScan = data['flashOnScan'] == true;
    }
    if (data['repeatScanning'] != null) {
      _repeatScanning = data['repeatScanning'] == true;
    }
    if (data['externalScanner'] != null) {
      _externalScanner = data['externalScanner'] == true;
    }
    if (data['scannedItemConfirmation'] != null) {
      _scannedItemConfirmation = data['scannedItemConfirmation'] == true;
    }
    _sanitizeDropdownValues();
  }

  Map<String, dynamic> _buildPayload() {
    _normalizeLabelTemplateSelection();
    return {
      'gstType': _gstType,
      'labelSize': _labelSize,
      'receiptSize': _receiptSize,
      'labelPrinterDpi': _labelPrinterDpi,
      'labelPrinterName': _labelPrinterName,
      'labelGap': _labelGap,
      'jewelTagPrintDirection': _jewelTagPrintDirection,
      'labelTemplateDefault': _labelTemplateDefault,
      'labelTemplateCustom': _labelTemplateCustom,
      'disableBillTypeConfirmation': _disableBillTypeConfirmation,
      'repeatScanning': _repeatScanning,
      'externalScanner': _externalScanner,
      'scannedItemConfirmation': _scannedItemConfirmation,
      'flashOnScan': _flashOnScan,
      'enableHsn': _enableHsn,
      'attributeNamePosition': _attributeNamePosition,
      'showTaxOnBill': _showTaxOnBill,
      'enableServices': _enableServices,
      'applyRoundOff': _applyRoundOff,
      'roundOffFrequency': _roundOffFrequency,
      'priceMaskingEnabled': _priceMaskingEnabled,
      'maskedJson': normalizedMaskedJsonFromValue({
        for (int j = 0; j < 10; j++) '$j': _maskDigitControllers[j].text,
      }),
      'adminMode': _adminMode,
      'taxRateType': _taxRateType,
      'compositionTaxRate': _compositionTaxRate,
      'voiceBillingEnabled': _voiceBillingEnabled,
      'barcodeScanningEnabled': _barcodeScanningEnabled,
      'scanServiceOrders': _scanServiceOrders,
      'scanBills': _scanBills,
      'directItemAdditionEnabled': _directItemAdditionEnabled,
      'additionalQuantityOptionEnabled': _additionalQuantityOptionEnabled,
      'printJobName': _printJobName,
      'enableTableStyleBilling': _tableStyleBillingEnabled,
      'enableTableStyleServiceItems': _tableStyleServiceItemsEnabled,
      'enableItemMrp': _enableItemMrp,
      'enableItemDiscount': _enableItemDiscount,
      'editPriceWhileBilling': _editPriceWhileBilling,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _loadSettings() async {
    if (_docId.isEmpty) {
      setState(() {
        _isLoading = false;
        _loadError = 'Missing user document id';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _loadError = null;
      _buildError = null;
      _buildStack = null;
    });
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_docId)
          .collection('settings')
          .doc('app')
          .get();
      if (settingsDoc.exists && settingsDoc.data() != null) {
        _applyPayload(settingsDoc.data()!);
      } else {
        _sanitizeDropdownValues();
      }
    } catch (e) {
      _loadError = 'Error loading settings: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_docId.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_docId)
          .collection('settings')
          .doc('app')
          .set(_buildPayload(), SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<Widget> _formChildren() {
    return [
      Text(
        'App settings for ${widget.userName ?? _docId}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
        ),
      ),
      const SizedBox(height: 4),
      Text('users/$_docId/settings/app', style: _descStyle),
      const Divider(height: 28),
      _label('GST Type'),
      _desc('How the business is registered for GST.'),
      _dropdown<String>(
        value: _gstType,
        items: const [
          DropdownMenuItem(value: 'Regular', child: Text('Regular')),
          DropdownMenuItem(value: 'Composition', child: Text('Composition')),
          DropdownMenuItem(
            value: 'Unregistered',
            child: Text('Unregistered'),
          ),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() {
            _gstType = val;
            if (val == 'Regular') _disableBillTypeConfirmation = false;
          });
        },
      ),
      _label('Label size'),
      _desc('Width and height of item labels.'),
      _dropdown<String>(
        value: _labelSize,
        items: LABEL_SIZE_OPTIONS
            .map(
              (size) => DropdownMenuItem(
                value: size,
                child: Text(
                  size == '70mm * 15mm'
                      ? '70mm × 15mm (Jewel Tag)'
                      : size.replaceAll('*', '×'),
                ),
              ),
            )
            .toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _labelSize = val);
        },
      ),
      _label('Label printer'),
      _desc('Brand of the label printer.'),
      _dropdown<String>(
        value: _labelPrinterName,
        items: LABEL_PRINTER_NAME_OPTIONS
            .map((name) => DropdownMenuItem(value: name, child: Text(name)))
            .toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _labelPrinterName = val);
        },
      ),
      _label('Label gap'),
      _desc('Gap between labels on the roll.'),
      _dropdown<String>(
        value: _labelGap,
        items: LABEL_GAP_OPTIONS
            .map((gap) => DropdownMenuItem(value: gap, child: Text(gap)))
            .toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _labelGap = val);
        },
      ),
      _label('Label template'),
      _desc('Which label layouts are available.'),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Default'),
        value: _labelTemplateDefault,
        onChanged: (val) {
          setState(() {
            _labelTemplateDefault = val ?? false;
            _normalizeLabelTemplateSelection();
          });
        },
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Custom'),
        value: _labelTemplateCustom,
        onChanged: (val) {
          setState(() {
            _labelTemplateCustom = val ?? false;
            _normalizeLabelTemplateSelection();
          });
        },
      ),
      if (_labelSize == '70mm * 15mm') ...[
        _label('Jewel tag print direction'),
        _desc('Which edge the jewel fold tag starts printing from.'),
        _dropdown<String>(
          value: _jewelTagPrintDirection,
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Left')),
            DropdownMenuItem(value: 'right', child: Text('Right')),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() => _jewelTagPrintDirection = val);
          },
        ),
      ],
      _label('Receipt size'),
      _desc('Paper width for bill receipts.'),
      _dropdown<String>(
        value: _receiptSize,
        items: RECEIPT_SIZE_OPTIONS
            .map((size) => DropdownMenuItem(value: size, child: Text(size)))
            .toList(),
        onChanged: (val) {
          if (val == null) return;
          setState(() => _receiptSize = val);
        },
      ),
      _label('Label printer DPI (TSPL)'),
      _desc('Use 203 dpi for most printers; 300 dpi for finer print.'),
      _dropdown<int>(
        value: _labelPrinterDpi,
        items: const [
          DropdownMenuItem(value: 203, child: Text('203 dpi (~8 dots/mm)')),
          DropdownMenuItem(value: 300, child: Text('300 dpi (~12 dots/mm)')),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() => _labelPrinterDpi = val);
        },
      ),
      if (_gstType == 'Regular') ...[
        _label('Tax Rate Type'),
        _desc(
          'Inclusive: prices include tax. Exclusive: tax added separately.',
        ),
        _dropdown<String>(
          value: _taxRateType,
          items: const [
            DropdownMenuItem(value: 'Inclusive', child: Text('Inclusive')),
            DropdownMenuItem(value: 'Exclusive', child: Text('Exclusive')),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() => _taxRateType = val);
          },
        ),
      ],
      if (_gstType == 'Composition') ...[
        _label('Composition Tax Rate (%)'),
        _desc('Fixed GST rate on composition-scheme bills.'),
        _dropdown<double>(
          value: _compositionTaxRate,
          items: const [
            DropdownMenuItem(value: 1.0, child: Text('1%')),
            DropdownMenuItem(value: 5.0, child: Text('5%')),
            DropdownMenuItem(value: 6.0, child: Text('6%')),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() => _compositionTaxRate = val);
          },
        ),
      ],
      const Divider(height: 28),
      _switch(
        title: 'Apply round off',
        subtitle: 'Round the bill grand total automatically.',
        value: _applyRoundOff,
        onChanged: (val) => setState(() => _applyRoundOff = val),
      ),
      if (_applyRoundOff) ...[
        _label('Round-off frequency'),
        _dropdown<String>(
          value: _roundOffFrequency,
          items: const [
            DropdownMenuItem(
              value: kRoundOffFrequencyDecimal,
              child: Text('Nearest rupee (drop paise)'),
            ),
            DropdownMenuItem(
              value: kRoundOffFrequencyNearest5,
              child: Text('Nearest ₹5'),
            ),
            DropdownMenuItem(
              value: kRoundOffFrequencyNearest10,
              child: Text('Nearest ₹10'),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() => _roundOffFrequency = val);
          },
        ),
      ],
      _switch(
        title: 'Price masking',
        subtitle: 'Replace price digits with custom characters.',
        value: _priceMaskingEnabled,
        onChanged: (val) => setState(() => _priceMaskingEnabled = val),
      ),
      _label('Digit mask characters'),
      _desc('One substitute character per digit 0–9.'),
      for (int i = 0; i < 10; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(width: 28, child: Text('$i')),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: _maskDigitControllers[i],
                  maxLength: 1,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('→ shown instead of $i', style: _descStyle),
              ),
            ],
          ),
        ),
      if (_gstType != 'Regular')
        _switch(
          title: 'Disable bill type confirmation',
          subtitle: 'Skip the GST bill type popup when starting a new bill.',
          value: _disableBillTypeConfirmation,
          onChanged: (val) =>
              setState(() => _disableBillTypeConfirmation = val),
        ),
      _switch(
        title: 'Flash On Scan',
        subtitle: 'Use the camera flash/torch when scanning barcodes.',
        value: _flashOnScan,
        onChanged: (val) => setState(() => _flashOnScan = val),
      ),
      _switch(
        title: 'Enable HSN',
        subtitle: 'Show HSN code on items and in GST billing flows.',
        value: _enableHsn,
        onChanged: (val) => setState(() => _enableHsn = val),
      ),
      _label('Attribute value position in item name'),
      _desc(
        'Place attach-to-name attribute values before or after the category name.',
      ),
      _dropdown<String>(
        value: _attributeNamePosition,
        items: const [
          DropdownMenuItem(
            value: kAttributeNamePositionBefore,
            child: Text('Before category name'),
          ),
          DropdownMenuItem(
            value: kAttributeNamePositionAfter,
            child: Text('After category name'),
          ),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() => _attributeNamePosition = val);
        },
      ),
      _switch(
        title: 'Show tax on bill',
        subtitle: 'Print and display GST/tax breakdown on bills and PDFs.',
        value: _showTaxOnBill,
        onChanged: (val) => setState(() => _showTaxOnBill = val),
      ),
      _switch(
        title: 'Enable services',
        subtitle:
            'Show New service order in the home bill-type dialog. New profiles inherit this default.',
        value: _enableServices,
        onChanged: (val) => setState(() => _enableServices = val),
      ),
      _switch(
        title: 'Voice billing',
        subtitle: 'Use microphone voice search while creating bills.',
        value: _voiceBillingEnabled,
        onChanged: (val) => setState(() => _voiceBillingEnabled = val),
      ),
      _switch(
        title: 'Barcode scanning',
        subtitle: 'Show barcode scan buttons on billing and items screens.',
        value: _barcodeScanningEnabled,
        onChanged: (val) => setState(() => _barcodeScanningEnabled = val),
      ),
      _switch(
        title: 'Print job name',
        subtitle: 'On service item labels, print job from item job attribute.',
        value: _printJobName,
        onChanged: (val) => setState(() => _printJobName = val),
      ),
      _switch(
        title: 'Enable table style billing',
        subtitle: 'Enter bill items in a table. New profiles inherit this.',
        value: _tableStyleBillingEnabled,
        onChanged: (val) => setState(() => _tableStyleBillingEnabled = val),
      ),
      _switch(
        title: 'Enable table style service items',
        subtitle: 'Enter service items in a table. New profiles inherit this.',
        value: _tableStyleServiceItemsEnabled,
        onChanged: (val) =>
            setState(() => _tableStyleServiceItemsEnabled = val),
      ),
      _switch(
        title: 'Enable item MRP',
        subtitle: 'Show MRP field when adding/editing items and in billing.',
        value: _enableItemMrp,
        onChanged: (val) => setState(() => _enableItemMrp = val),
      ),
      _switch(
        title: 'Enable item discount',
        subtitle:
            'Show discount field when adding/editing items and in billing.',
        value: _enableItemDiscount,
        onChanged: (val) => setState(() => _enableItemDiscount = val),
      ),
      _switch(
        title: 'Edit price while billing',
        subtitle: 'Allow changing sell price in table-style billing.',
        value: _editPriceWhileBilling,
        onChanged: (val) => setState(() => _editPriceWhileBilling = val),
      ),
      _switch(
        title: 'Scan service orders',
        subtitle: 'Show a scan button on service orders.',
        value: _scanServiceOrders,
        onChanged: (val) => setState(() => _scanServiceOrders = val),
      ),
      _switch(
        title: 'Scan Bills',
        subtitle: 'Show a scan button on the home screen for bills.',
        value: _scanBills,
        onChanged: (val) => setState(() => _scanBills = val),
      ),
      _switch(
        title: 'Repeat scanning',
        subtitle: 'Keep the scanner ready after confirming a scan.',
        value: _repeatScanning,
        onChanged: (val) => setState(() => _repeatScanning = val),
      ),
      _switch(
        title: 'External scanner',
        subtitle: 'Enable Bluetooth SPP barcode scanners.',
        value: _externalScanner,
        onChanged: (val) => setState(() => _externalScanner = val),
      ),
      _switch(
        title: 'Scanned item confirmation',
        subtitle: 'Show a quantity dialog before each scanned item is added.',
        value: _scannedItemConfirmation,
        onChanged: (val) => setState(() => _scannedItemConfirmation = val),
      ),
      _switch(
        title: 'Additional quantity controls',
        subtitle: 'Show fine-tune arrows in the quantity dialog.',
        value: _additionalQuantityOptionEnabled,
        onChanged: (val) =>
            setState(() => _additionalQuantityOptionEnabled = val),
      ),
      _switch(
        title: 'Direct item addition',
        subtitle: 'Show quick-add shortcuts on billing and service screens.',
        value: _directItemAdditionEnabled,
        onChanged: (val) => setState(() => _directItemAdditionEnabled = val),
      ),
      _switch(
        title: 'Admin Mode',
        subtitle:
            'When off, sensitive settings require an admin PIN on device.',
        value: _adminMode,
        onChanged: (val) => setState(() => _adminMode = val),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildForm() {
    try {
      final children = _formChildren();
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: children,
      );
    } catch (e, st) {
      debugPrint('UserSettingsScreen build error: $e\n$st');
      // Defer setState so we don't call it during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _buildError = e;
          _buildStack = st;
        });
      });
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to render settings:\n$e',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleName = (widget.userName ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primaryText,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (titleName.isNotEmpty)
              Text(
                titleName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading || _isSaving ? null : _loadSettings,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadSettings,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          child: Text(
                            'Settings UI error:\n$_buildError\n\n$_buildStack',
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ),
                    )
                  : _buildForm(),
      bottomNavigationBar: (_isLoading || _loadError != null)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving…' : 'Save Changes'),
                  ),
                ),
              ),
            ),
    );
  }
}
