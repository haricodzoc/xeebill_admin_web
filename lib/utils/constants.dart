// const String BASE_URL = 'https://35c27b0f78f4.ngrok-free.app';

import 'package:flutter/material.dart';

const String BASE_URL = 'https://1a66662dcbae.ngrok-free.app';
// const String BASE_URL = 'http://192.168.1.7:3000';
String ACTIVE_PROFILE_ID = '';
bool IS_ACCOUNT_EXPIRED = false;
String ACTIVE_PROFILE_PREFIX = '1';
String ACTIVE_PROFILE_NAME = '';
String ACTIVE_PROFILE_CODE = '';
bool IS_SUB_PROFILE = false;
BuildContext? REFRESH_SYNC_CONTEXT;
int ITEM_SYNC_BACKWARD_INSTANCE = 1;
int BILL_SYNC_BACKWARD_INSTANCE = 1;
int CATEGORY_SYNC_BACKWARD_INSTANCE = 1;
int DISCOUNT_SYNC_BACKWARD_INSTANCE = 1;
bool IS_CUSTOMER_REPLACED_FROM_BILL = false;
String REPLACED_CUSTOMER_CODE = '';

Map<String, bool> PERMISSIONS = {
  'Bills': false,
  'Categories': false,
  'Items': false,
  'Reports': false,
  'Discounts': false,
  'Button': false,
};
Map<String, bool> ITEM_PERMISSIONS = {
  'Add items': false,
  'Edit items': false,
  'Delete items': false,
  'Map items': false,
  'Print label': false,
};
Map<String, bool> CATEGORY_PERMISSIONS = {
  'Add categories': false,
  'Edit categories': false,
  'Delete categories': false,
};
Map<String, bool> REPORT_PERMISSIONS = {
  'View sales report': false,
  'View invoice report': false,
  'View inventory report': false,
};

const String LOGIN_URL = '/check-email';

const String ITEMS_URL = '/items';

const String ITEM_DELETE_URL = '/items';

const String PRODUCTS_INFO_URL = '/product-info';

const String BULK_ITEMS_URL = '/bulk-insert-items';

const String WASTAGE_URL = '/wastage-percentage';

const String CATEGORY_URL = '/categories';

const String UNITS_URL = '/units';

const String REPORT_AVAILABILITY_URL = '/allow-generate-report';

const String GENERATE_REPORT_URL = '/generate-report';

const String PROFILE_ID = '0';

const String PROFILE_NAME = 'ADMIN';

double GSTR_CMP_TAX_PERC = 1;

bool TAX_RATE_INCLUSIVE = true;

const String ADD_ITEMS_URL = '/items';

const String ACTIVE_ITEMS = '/active-items';

const String RAZORPAY_KEY_ID = "rzp_test_RU8Ab5OOnpo1Qu";

GstType GST_TYPE = GstType.regular;

List<String> PROFILE_CODES = ['MP'];

String LABEL_SIZE = '38mm * 25mm';

DateTime? ACCOUNT_EXPIRY_DATE;

bool IS_BILL_SUBSCRIBED = false;

bool IS_ITEMS_SUBSCRIBED = false;
bool IS_CUST_INFO_SUBSCRIBED = false;
bool IS_CUST_PAYMENT_SUBSCRIBED = false;

bool IS_CATEGORIES_SUBSCRIBED = false;

bool IS_DISCOUNTS_SUBSCRIBED = false;

String SCANNED_BARCODE_WHILE_ADDING_MANUALLY = '';

bool ENABLE_HSN = false;

bool SHOW_TAX_ON_BILL = false;

bool APPLY_ROUND_OFF = false;

bool TAX_TOGGLE = false;

bool ADMIN_MODE = true;

bool ADD_GEN_CAT = true;

const int SUCCESS = 200;

const bool CREATE_CATEGORIES_AUTOMATICALLY = true;

double DEFAULT_TAX_PERC = 0;

double DEFAULT_RECHARGE_AMOUNT = 600;

const double DEFAULT_MARGIN_PERC = 40;

const int EXPIRED_TODAY_ITEM = 2;

const int EXPIRED_WEEK_ITEM = 3;

const int OTHERS = 4;

const int ADD_SUCCESS = 201;

const int USER_INVALID_RESPONSE = 100;

const int USER_UNAUTH_RESPONSE = 401;

const int NO_INTERNET = 101;

const int INVALID_FORMAT = 102;

const int UNKNOWN_ERROR = 103;

const String USE_ITEM_DESC = 'Did you use this item?';

const String OPEN_ITEM_DESC = 'Did you open this item?';

const String DNA_DESC =
    'No items here yet!\nAdd an item and keep track and stay fresh';

const String UPDATE_MSG = 'Item updated successfully';

const String DELETE_MSG = 'Item deleted successfully';

const String UPDATE_FAILED_MSG = 'Something went wrong.Item not updated';

const String DELETE_FAILED_MSG = 'Something went wrong.Item not deleted';

const String STATUS_UPDATE_FAILED_MSG =
    'Something went wrong.Item status not updated';

const String REPORT_GEN_MSG = 'Report sent to your email!';

const String INVALID_IMAGE_MSG =
    "Oops! Couldn't read the image. Try again with a clearer picture.";

const String PSWD_RESET_MSG = 'Password reset email sent! Check your inbox.';

const String NAME_UPDATE_MSG = 'Name updated successfully!';

const String OPEN_API_ENDPOINT = "https://api.openai.com/v1/chat/completions";

String OPENAI_API_KEY = "";

/// Unit of measure list. Overwritten at startup from Remote Config `units_json` when fetch succeeds.
List<Map<String, dynamic>> UNITS = [
  {"name": "Number", "abbreviation": "nos", "uom_type": "count"},
  {"name": "Piece", "abbreviation": "pcs", "uom_type": "count"},
  {"name": "Meter", "abbreviation": "m", "uom_type": "length"},
  {"name": "Litre", "abbreviation": "L", "uom_type": "volume"},
  {"name": "Kg", "abbreviation": "kg", "uom_type": "weight"},
  {"name": "Pack", "abbreviation": "pk", "uom_type": "count"},
  {"name": "Box", "abbreviation": "bx", "uom_type": "count"},
  {"name": "Dozen", "abbreviation": "dz", "uom_type": "count"},
  {"name": "Roll", "abbreviation": "rl", "uom_type": "count"},
  {"name": "Gram", "abbreviation": "g", "uom_type": "weight"},
  {"name": "Millilitre", "abbreviation": "ml", "uom_type": "volume"},
  {"name": "Set", "abbreviation": "st", "uom_type": "count"},
  {"name": "Packet", "abbreviation": "pkt", "uom_type": "count"},
  {"name": "inch", "abbreviation": "in", "uom_type": "length"},
  {"name": "Feet", "abbreviation": "ft", "uom_type": "length"},
  {"name": "Yard", "abbreviation": "yd", "uom_type": "length"},
  {"name": "Bottle", "abbreviation": "btl", "uom_type": "count"},
  {"name": "Jar", "abbreviation": "jar", "uom_type": "count"},
  {"name": "Tube", "abbreviation": "tube", "uom_type": "count"},
  {"name": "Carton", "abbreviation": "carton", "uom_type": "count"},
  {"name": "Bag", "abbreviation": "bag", "uom_type": "count"},
  {"name": "Can", "abbreviation": "can", "uom_type": "count"},
  {"name": "Cup", "abbreviation": "cup", "uom_type": "count"},
  {"name": "Glass", "abbreviation": "glass", "uom_type": "count"},
  {"name": "Plate", "abbreviation": "plate", "uom_type": "count"},
  {"name": "Bowl", "abbreviation": "bowl", "uom_type": "count"},
  {"name": "Spoon", "abbreviation": "spoon", "uom_type": "count"},
  {"name": "Fork", "abbreviation": "fork", "uom_type": "count"},
  {"name": "Knife", "abbreviation": "knife", "uom_type": "count"},
  {"name": "Spatula", "abbreviation": "spatula", "uom_type": "count"},
  {"name": "Spatula", "abbreviation": "spatula", "uom_type": "count"},
];

/// Sorts [UNITS] by `name` (case-insensitive). Call after assigning from Remote Config.
void sortUnitsAlphabetically() {
  UNITS.sort((a, b) {
    final an = (a['name'] as String? ?? '').toLowerCase();
    final bn = (b['name'] as String? ?? '').toLowerCase();
    return an.compareTo(bn);
  });
}

List<Map<String, dynamic>> TAX_SLABS = [];

enum GstType { regular, composite, unregistered, saleReturn }

enum PaymentModes { cash, credit, card, upi, wallet, cheque, multiPay }

enum AttributeFieldType {
  singleSelect(1),
  multiSelect(2),
  textBox(3),
  dateField(4);

  final int value;
  const AttributeFieldType(this.value);

  String get displayName {
    switch (this) {
      case AttributeFieldType.singleSelect:
        return 'Single Select';
      case AttributeFieldType.multiSelect:
        return 'Multi Select';
      case AttributeFieldType.textBox:
        return 'Text Box';
      case AttributeFieldType.dateField:
        return 'Date Field';
    }
  }

  static AttributeFieldType? fromValue(int value) {
    return AttributeFieldType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AttributeFieldType.singleSelect,
    );
  }
}
