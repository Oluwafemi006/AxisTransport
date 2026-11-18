import 'package:intl/intl.dart';

final _time = DateFormat('HH:mm', 'fr_FR');
final _dateTime = DateFormat("d MMM y, HH:mm", 'fr_FR');
final _fullDateTime = DateFormat("EEEE d MMMM y, HH:mm", 'fr_FR');
final _money = NumberFormat.decimalPattern('fr_FR');

String formatTime(DateTime value) => _time.format(value);

String formatDateTime(DateTime value) => _dateTime.format(value);

String formatFullDateTime(DateTime value) => _fullDateTime.format(value);

/// Le franc CFA s'affiche « FCFA », jamais avec son code « XOF ».
String formatMoney(num amount, [String currency = 'XOF']) {
  final unit = currency == 'XOF' ? 'FCFA' : currency;
  return '${_money.format(amount)} $unit';
}

/// Date et heure au Bénin (UTC+1), quel que soit le fuseau du téléphone.
String formatBeninDateTime(DateTime value) {
  final benin = value.toUtc().add(const Duration(hours: 1));
  return _dateTime.format(
    DateTime(benin.year, benin.month, benin.day, benin.hour, benin.minute),
  );
}
