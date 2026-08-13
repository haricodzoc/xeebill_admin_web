import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xeebill_web/models/general_category_model.dart';
import 'package:xeebill_web/models/rate_tax_definition_model.dart';
import 'package:xeebill_web/utils/app_colors.dart';

class RateTaxDefinitionScreen extends StatefulWidget {
  const RateTaxDefinitionScreen({super.key});

  @override
  State<RateTaxDefinitionScreen> createState() =>
      _RateTaxDefinitionScreenState();
}

class _RateTaxDefinitionScreenState extends State<RateTaxDefinitionScreen> {
  static const _collection = 'rate_tax_definition';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<RateTaxDefinition> _definitions = [];
  List<GeneralCategory> _categories = [];
  bool _saving = false;

  List<RateTaxDefinition> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _definitions;
    return _definitions.where((d) {
      return d.parentCategoryCode.toLowerCase().contains(q) ||
          d.parentCategoryName.toLowerCase().contains(q) ||
          d.slabs.any((s) => s.preview.toLowerCase().contains(q));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _firestore.collection('general_categories').get(),
        _firestore.collection(_collection).get(),
      ]);

      final categories = results[0].docs
          .map(GeneralCategory.fromFirestore)
          .toList()
        ..sort(
          (a, b) => a.categoryName.toLowerCase().compareTo(
                b.categoryName.toLowerCase(),
              ),
        );

      final definitions = results[1].docs
          .map(RateTaxDefinition.fromFirestore)
          .toList()
        ..sort(
          (a, b) => a.parentCategoryCode.toLowerCase().compareTo(
                b.parentCategoryCode.toLowerCase(),
              ),
        );

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _definitions = definitions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load rate tax definitions: $e';
        _loading = false;
      });
    }
  }

  String _docIdForCode(String code) {
    final cleaned = code.trim().replaceAll('/', '-');
    return cleaned.isEmpty ? _firestore.collection(_collection).doc().id : cleaned;
  }

  Future<void> _saveDefinition({
    RateTaxDefinition? existing,
    required String parentCode,
    required String parentName,
    required List<RateTaxSlab> slabs,
  }) async {
    setState(() => _saving = true);
    try {
      final code = parentCode.trim();
      final docId = existing?.id ?? _docIdForCode(code);
      final ref = _firestore.collection(_collection).doc(docId);
      final payload = <String, dynamic>{
        'parent_category_code': code,
        'parent_category_name': parentName.trim(),
        'slabs': slabs.map((s) => s.toMap()).toList(),
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (existing == null) {
        payload['created_at'] = FieldValue.serverTimestamp();
        await ref.set(payload);
      } else {
        await ref.set(payload, SetOptions(merge: true));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Rate tax definition saved for $code'
                : 'Rate tax definition updated for $code',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteDefinition(RateTaxDefinition definition) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete definition?'),
        content: Text(
          'Remove rate-based tax rules for ${definition.parentCategoryCode}'
          '${definition.parentCategoryName.isEmpty ? '' : ' (${definition.parentCategoryName})'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _firestore.collection(_collection).doc(definition.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Definition deleted'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openEditor({RateTaxDefinition? existing}) async {
    final result = await showDialog<_RateTaxEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RateTaxEditorDialog(
        existing: existing,
        categories: _categories,
        existingCodes: _definitions
            .where((d) => d.id != existing?.id)
            .map((d) => d.parentCategoryCode.trim().toLowerCase())
            .toSet(),
      ),
    );
    if (result == null) return;
    await _saveDefinition(
      existing: existing,
      parentCode: result.parentCode,
      parentName: result.parentName,
      slabs: result.slabs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundGrey,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: AppColors.primaryGreen,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Rate based tax definition',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh, color: AppColors.primaryGreen),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openEditor(),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add definition'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.primaryRed),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final items = _filtered;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.percent_rounded,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GST by item rate',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Set tax slabs for a parent category. Example: rate < ₹2,500 → 5%, rate > ₹2,500 → 18%. Add as many rules as you need.',
                            style: TextStyle(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by category code, name, or slab',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${items.length} definition${items.length == 1 ? '' : 's'}',
              style: TextStyle(
                color: AppColors.primaryGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 48,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.rule_folder_outlined,
                        size: 42,
                        color: AppColors.primaryGrey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _definitions.isEmpty
                            ? 'No rate-based tax definitions yet'
                            : 'No matching definitions',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _definitions.isEmpty
                            ? 'Click Add definition to create slabs like rate < 2500 → 5%.'
                            : 'Try a different search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.primaryGrey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...items.map(_buildDefinitionCard),
          ],
        ),
      ),
    );
  }

  Widget _buildDefinitionCard(RateTaxDefinition definition) {
    final name = definition.parentCategoryName.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryGreen,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          definition.parentCategoryCode,
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (name.isNotEmpty)
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: definition.slabs
                        .map(
                          (slab) => Chip(
                            label: Text(slab.preview),
                            backgroundColor: AppColors.backgroundGrey,
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              onPressed: _saving ? null : () => _openEditor(existing: definition),
              icon: Icon(Icons.edit_outlined, color: AppColors.primaryGreen),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: _saving ? null : () => _deleteDefinition(definition),
              icon: Icon(Icons.delete_outline, color: AppColors.primaryRed),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateTaxEditorResult {
  final String parentCode;
  final String parentName;
  final List<RateTaxSlab> slabs;

  const _RateTaxEditorResult({
    required this.parentCode,
    required this.parentName,
    required this.slabs,
  });
}

class _SlabDraft {
  _SlabDraft({
    this.operator = RateCompareOp.lt,
    String amount = '',
    String taxPerc = '',
  })  : amount = TextEditingController(text: amount),
        taxPerc = TextEditingController(text: taxPerc);

  RateCompareOp operator;
  final TextEditingController amount;
  final TextEditingController taxPerc;

  void dispose() {
    amount.dispose();
    taxPerc.dispose();
  }
}

class _RateTaxEditorDialog extends StatefulWidget {
  final RateTaxDefinition? existing;
  final List<GeneralCategory> categories;
  final Set<String> existingCodes;

  const _RateTaxEditorDialog({
    required this.existing,
    required this.categories,
    required this.existingCodes,
  });

  @override
  State<_RateTaxEditorDialog> createState() => _RateTaxEditorDialogState();
}

class _RateTaxEditorDialogState extends State<_RateTaxEditorDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late List<_SlabDraft> _slabs;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _codeController = TextEditingController(
      text: existing?.parentCategoryCode ?? '',
    );
    _nameController = TextEditingController(
      text: existing?.parentCategoryName ?? '',
    );
    if (existing != null && existing.slabs.isNotEmpty) {
      _slabs = existing.slabs
          .map(
            (s) => _SlabDraft(
              operator: s.operator,
              amount: _fmt(s.amount),
              taxPerc: _fmt(s.taxPerc),
            ),
          )
          .toList();
    } else {
      _slabs = [
        _SlabDraft(operator: RateCompareOp.lt, amount: '2500', taxPerc: '5'),
        _SlabDraft(operator: RateCompareOp.gt, amount: '2500', taxPerc: '18'),
      ];
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    for (final slab in _slabs) {
      slab.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  void _fillFromCategory(GeneralCategory category) {
    setState(() {
      _codeController.text = category.code;
      _nameController.text = category.categoryName;
      _error = null;
    });
  }

  void _addSlab() {
    setState(() {
      _slabs.add(_SlabDraft());
    });
  }

  void _removeSlab(int index) {
    if (_slabs.length <= 1) return;
    setState(() {
      _slabs[index].dispose();
      _slabs.removeAt(index);
    });
  }

  void _submit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a parent category code.');
      return;
    }
    if (widget.existing == null &&
        widget.existingCodes.contains(code.toLowerCase())) {
      setState(
        () => _error =
            'A definition already exists for $code. Edit that one instead.',
      );
      return;
    }

    final slabs = <RateTaxSlab>[];
    for (var i = 0; i < _slabs.length; i++) {
      final draft = _slabs[i];
      final amount = double.tryParse(draft.amount.text.trim());
      final tax = double.tryParse(draft.taxPerc.text.trim());
      if (amount == null || amount < 0) {
        setState(() => _error = 'Rule ${i + 1}: enter a valid rate amount.');
        return;
      }
      if (tax == null || tax < 0 || tax > 100) {
        setState(
          () => _error = 'Rule ${i + 1}: tax % must be between 0 and 100.',
        );
        return;
      }
      slabs.add(
        RateTaxSlab(operator: draft.operator, amount: amount, taxPerc: tax),
      );
    }

    Navigator.pop(
      context,
      _RateTaxEditorResult(
        parentCode: code,
        parentName: _nameController.text.trim(),
        slabs: slabs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.percent_rounded, color: AppColors.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'New rate tax definition'
                          : 'Edit rate tax definition',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the parent category, then add dynamic rate slabs with tax %.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Autocomplete<GeneralCategory>(
                        initialValue: TextEditingValue(
                          text: _codeController.text,
                        ),
                        displayStringForOption: (c) =>
                            '${c.code}  ·  ${c.categoryName}',
                        optionsBuilder: (value) {
                          final q = value.text.trim().toLowerCase();
                          if (q.isEmpty) {
                            return widget.categories.take(20);
                          }
                          return widget.categories.where((c) {
                            return c.code.toLowerCase().contains(q) ||
                                c.categoryName.toLowerCase().contains(q);
                          }).take(20);
                        },
                        onSelected: _fillFromCategory,
                        fieldViewBuilder: (
                          context,
                          controller,
                          focusNode,
                          onSubmit,
                        ) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: (v) {
                              _codeController.text = v;
                              final match = widget.categories
                                  .where(
                                    (c) =>
                                        c.code.trim().toLowerCase() ==
                                        v.trim().toLowerCase(),
                                  )
                                  .toList();
                              if (match.length == 1) {
                                _nameController.text = match.first.categoryName;
                              }
                            },
                            decoration: const InputDecoration(
                              labelText: 'Parent category code',
                              hintText: 'Search or type category code',
                              border: OutlineInputBorder(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Parent category name (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text(
                            'Rate slabs',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _addSlab,
                            icon: const Icon(Icons.add),
                            label: const Text('Add rule'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(_slabs.length, _buildSlabRow),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: AppColors.primaryRed),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                    child: Text(widget.existing == null ? 'Save' : 'Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlabRow(int index) {
    final slab = _slabs[index];
    final operatorField = DropdownButtonFormField<RateCompareOp>(
      isExpanded: true,
      value: slab.operator,
      decoration: const InputDecoration(
        labelText: 'If rate is',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      selectedItemBuilder: (context) => RateCompareOp.values
          .map(
            (op) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                op.symbol,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      items: RateCompareOp.values
          .map(
            (op) => DropdownMenuItem(
              value: op,
              child: Text(
                '${op.symbol}  ${op.label}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() => slab.operator = v);
      },
    );
    final amountField = TextField(
      controller: slab.amount,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: const InputDecoration(
        labelText: 'Amount (₹)',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
    final taxField = TextField(
      controller: slab.taxPerc,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: const InputDecoration(
        labelText: 'Tax %',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
    final deleteButton = IconButton(
      tooltip: 'Remove rule',
      onPressed: _slabs.length == 1 ? null : () => _removeSlab(index),
      icon: Icon(Icons.delete_outline, color: AppColors.primaryRed),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                operatorField,
                const SizedBox(height: 8),
                amountField,
                const SizedBox(height: 8),
                taxField,
                Align(alignment: Alignment.centerRight, child: deleteButton),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 3, child: operatorField),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: amountField),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: taxField),
              deleteButton,
            ],
          );
        },
      ),
    );
  }
}
