import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _gstType = 'Regular';
  String _labelSize = '38mm * 25mm';
  bool _enableHsn = false;
  bool _showTaxOnBill = false;
  bool _taxToggle = false;
  bool _applyRoundOff = true;
  bool _adminMode = true;
  String? _adminPin;
  bool isUpdatingSettings = false;
  String _taxRateType = 'Inclusive';
  double _compositionTaxRate = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final settingsDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('app')
            .get();

        if (settingsDoc.exists) {
          final data = settingsDoc.data()!;
          setState(() {
            _gstType = data['gstType'] ?? 'Regular';
            _labelSize = data['labelSize'] ?? '38mm * 25mm';
            _enableHsn = data['enableHsn'] ?? false;
            _showTaxOnBill = data['showTaxOnBill'] ?? false;
            _taxToggle = data['taxToggle'] ?? false;
            _applyRoundOff = data['applyRoundOff'] ?? true;
            _adminMode = data['adminMode'] ?? true;
            _taxRateType = data['taxRateType'] ?? 'Inclusive';
            _compositionTaxRate = (data['compositionTaxRate'] ?? 1.0)
                .toDouble();
          });
        } else {
          // Initialize from constants
          setState(() {
            _gstType = GST_TYPE == GstType.regular
                ? 'Regular'
                : (GST_TYPE == GstType.composite
                      ? 'Composition'
                      : 'Unregistered');
            _labelSize = LABEL_SIZE;
            _enableHsn = ENABLE_HSN;
            _showTaxOnBill = SHOW_TAX_ON_BILL;
            _applyRoundOff = APPLY_ROUND_OFF;
            _taxToggle = TAX_TOGGLE;
            _adminMode = ADMIN_MODE;
            _taxRateType = TAX_RATE_INCLUSIVE ? 'Inclusive' : 'Exclusive';
            _compositionTaxRate = GSTR_CMP_TAX_PERC;
          });
        }

        // Load admin PIN
        final pinDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('admin_pin')
            .get();

        if (pinDoc.exists) {
          setState(() {
            _adminPin = pinDoc.data()?['pin'] as String?;
          });
        }
      }
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading settings: $e')));
      }
    }
  }

  Future<void> _setAdminPin(String pin) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('admin_pin')
            .set({'pin': pin});
        setState(() {
          _adminPin = pin;
        });
      }
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error setting PIN: $e')));
      }
    }
  }

  Future<void> _showSetPinDialog({bool isReset = false}) async {
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isReset ? 'Reset Admin PIN' : 'Set Admin PIN',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
              hintText: 'Enter a PIN (min 4 digits)',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.length < 4) {
                return 'Enter at least 4 digits';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text(isReset ? 'Reset PIN' : 'Set PIN'),
          ),
        ],
      ),
    );
    if (result == true) {
      await _setAdminPin(pinController.text);
      if (!isReset) {
        setState(() {
          _adminMode = false;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isReset ? 'PIN reset successfully' : 'PIN set successfully',
            ),
          ),
        );
      }
    } else if (!isReset) {
      // If cancelled, revert the switch
      setState(() {
        _adminMode = true;
      });
    }
  }

  Future<void> _showVerifyPinDialog() async {
    final pinController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Enter Admin PIN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'Enter your PIN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () async {
                  Navigator.pop(context); // Close PIN dialog
                  await _showResetPinDialog();
                },
                child: Text(
                  "Forgot PIN? Reset",
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    decoration: TextDecoration.underline,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text == _adminPin) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (result == true) {
      setState(() {
        _adminMode = true;
      });
    } else {
      setState(() {
        _adminMode = false;
      });
    }
  }

  Future<void> _showResetPinDialog() async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Reset PIN',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Enter your account password',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Password required';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  final cred = EmailAuthProvider.credential(
                    email: user!.email!,
                    password: passwordController.text,
                  );
                  await user.reauthenticateWithCredential(cred);
                  Navigator.pop(context, true);
                  await _showSetPinDialog(isReset: true);
                } catch (e) {
                  await logErrorToFile(e.toString(), StackTrace.current);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password incorrect')),
                    );
                  }
                }
              }
            },
            child: const Text('Verify & Reset'),
          ),
        ],
      ),
    );
    // No need to handle result here, _showSetPinDialog will be called on success
  }

  @override
  Widget build(BuildContext context) {
    final currentGstType = _gstType == "Regular"
        ? GstType.regular
        : (_gstType == "Composition"
              ? GstType.composite
              : GstType.unregistered);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.backgroundGrey,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.primaryGreen),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            color: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: AppColors.primaryGreen.withOpacity(0.13),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _adminMode == true
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GST Type',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.primaryGrey,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: _gstType,
                              items: const [
                                DropdownMenuItem(
                                  value: 'Regular',
                                  child: Text('Regular'),
                                ),
                                DropdownMenuItem(
                                  value: 'Composition',
                                  child: Text('Composition'),
                                ),
                                DropdownMenuItem(
                                  value: 'Unregistered',
                                  child: Text('Unregistered'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _gstType = val!;
                                });
                              },
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.activeGreen.withOpacity(
                                      0.18,
                                    ),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Label size',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.primaryGrey,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: _labelSize,
                              items: const [
                                DropdownMenuItem(
                                  value: '38mm * 25mm',
                                  child: Text('38mm * 25mm'),
                                ),
                                DropdownMenuItem(
                                  value: '50mm * 25mm',
                                  child: Text('50mm * 25mm'),
                                ),
                                DropdownMenuItem(
                                  value: '50mm * 38mm',
                                  child: Text('50mm * 38mm'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _labelSize = val!;
                                });
                              },
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: AppColors.activeGreen.withOpacity(
                                      0.18,
                                    ),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            if (currentGstType == GstType.regular)
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 18),
                                  Text(
                                    'Tax Rate Type',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.primaryGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    value: _taxRateType,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Inclusive',
                                        child: Text('Inclusive'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Exclusive',
                                        child: Text('Exclusive'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        _taxRateType = val!;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: AppColors.activeGreen
                                              .withOpacity(0.18),
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            if (currentGstType == GstType.composite)
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 18),
                                  Text(
                                    'Composition Tax Rate (%)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.primaryGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<double>(
                                    value: _compositionTaxRate,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 1.0,
                                        child: Text('1%'),
                                      ),
                                      DropdownMenuItem(
                                        value: 5.0,
                                        child: Text('5%'),
                                      ),
                                      DropdownMenuItem(
                                        value: 6.0,
                                        child: Text('6%'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      setState(() {
                                        _compositionTaxRate = val!;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                          color: AppColors.activeGreen
                                              .withOpacity(0.18),
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 18),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Apply round off',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.primaryGrey,
                                ),
                              ),
                              activeColor: AppColors.activeGreen,
                              value: _applyRoundOff,
                              onChanged: (val) {
                                setState(() {
                                  _applyRoundOff = val;
                                });
                              },
                            ),
                            if (currentGstType != GstType.composite)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Tax Toggle',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.primaryGrey,
                                  ),
                                ),
                                activeColor: AppColors.activeGreen,
                                value: _taxToggle,
                                onChanged: (val) {
                                  setState(() {
                                    _taxToggle = val;
                                  });
                                },
                              ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Enable HSN',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.primaryGrey,
                                ),
                              ),
                              activeColor: AppColors.activeGreen,
                              value: _enableHsn,
                              onChanged: (val) {
                                setState(() {
                                  _enableHsn = val;
                                });
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Show Tax on Bill',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.primaryGrey,
                                ),
                              ),
                              activeColor: AppColors.activeGreen,
                              value: _showTaxOnBill,
                              onChanged: (val) {
                                setState(() {
                                  _showTaxOnBill = val;
                                });
                              },
                            ),
                          ],
                        )
                      : Container(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Admin Mode',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primaryGrey,
                      ),
                    ),
                    activeColor: AppColors.activeGreen,
                    value: _adminMode,
                    onChanged: (val) async {
                      if (!val) {
                        // Disabling: only ask for PIN if not set
                        if (_adminPin == null || _adminPin!.isEmpty) {
                          await _showSetPinDialog();
                        } else {
                          setState(() {
                            _adminMode = false;
                          });
                        }
                      } else {
                        // Enabling: verify PIN
                        await _showVerifyPinDialog();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: isUpdatingSettings
                  ? null
                  : () async {
                      try {
                        setState(() {
                          isUpdatingSettings = true;
                        });
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .collection('settings')
                              .doc('app')
                              .set({
                                'gstType': _gstType,
                                'labelSize': _labelSize,
                                'taxToggle': _taxToggle,
                                'enableHsn': _enableHsn,
                                'showTaxOnBill': _showTaxOnBill,
                                'applyRoundOff': _applyRoundOff,
                                'adminMode': _adminMode,
                                'taxRateType': _taxRateType,
                                'compositionTaxRate': _compositionTaxRate,
                              }, SetOptions(merge: true));

                          // Update constants
                          GST_TYPE = _gstType == "Regular"
                              ? GstType.regular
                              : (_gstType == "Composition"
                                    ? GstType.composite
                                    : GstType.unregistered);
                          LABEL_SIZE = _labelSize;
                          ENABLE_HSN = _enableHsn;
                          TAX_TOGGLE = _taxToggle;
                          SHOW_TAX_ON_BILL = _showTaxOnBill;
                          APPLY_ROUND_OFF = _applyRoundOff;
                          ADMIN_MODE = _adminMode;
                          TAX_RATE_INCLUSIVE = _taxRateType == 'Inclusive';
                          GSTR_CMP_TAX_PERC = _compositionTaxRate;

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Settings saved successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        }
                      } catch (e) {
                        await logErrorToFile(e.toString(), StackTrace.current);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error saving settings: $e'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            isUpdatingSettings = false;
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isUpdatingSettings
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.backgroundGrey,
    );
  }
}
