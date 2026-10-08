import 'package:intl/intl.dart';

final _dateTime = DateFormat("d MMM y, HH:mm", 'fr_FR');
final _fullDateTime = DateFormat("EEEE d MMMM y, HH:mm", 'fr_FR');
final _money = NumberFormat.decimalPattern('fr_FR');

String formatDateTime(DateTime value) => _dateTime.format(value);

String formatFullDateTime(DateTime value) => _fullDateTime.format(value);

String formatMoney(num amount, [String currency = 'XOF']) {
  return '${_money.format(amount)} $currency';
}
