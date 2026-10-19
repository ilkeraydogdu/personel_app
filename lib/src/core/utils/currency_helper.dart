class CurrencyHelper {
  static const String defaultCurrency = 'TRY';

  static const Map<String, String> symbols = {
    'TRY': '₺',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
  };

  static const Map<String, String> names = {
    'TRY': 'Türk Lirası',
    'USD': 'ABD Doları',
    'EUR': 'Euro',
    'GBP': 'İngiliz Sterlini',
  };

  static const List<String> supportedCurrencies = [
    'TRY - Türk Lirası (₺)',
    'USD - ABD Doları (\$)',
    'EUR - Euro (€)',
    'GBP - İngiliz Sterlini (£)',
  ];

  static String getSymbol(String? currency) {
    if (currency == null || currency.isEmpty) return '₺';
    final code = currency.split(' ').first.toUpperCase().trim();
    return symbols[code] ?? '₺';
  }

  static String format(num amount, {String currency = 'TRY', int decimals = 2}) {
    final code = currency.split(' ').first.toUpperCase().trim();
    final symbol = getSymbol(code);
    final formattedNum = amount.toStringAsFixed(decimals);

    if (code == 'TRY') {
      return '$formattedNum $symbol';
    }
    return '$symbol$formattedNum';
  }
}
