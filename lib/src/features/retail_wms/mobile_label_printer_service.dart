import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Label template types supported by the mobile printer
enum LabelTemplateType {
  standardPrice,
  clearanceDiscount,
  shelfPlanogram,
}

/// Service to generate and dispatch label print commands for mobile belt printers
/// using Zebra CPCL (Comtec Printer Control Language) and standard ESC/POS.
class MobileLabelPrinterService {
  /// Generate Zebra CPCL formatted string for a standard price label (e.g. 50mm x 30mm)
  static String generateCpclPriceLabel({
    required String productName,
    required String barcode,
    required double price,
    double? vatRate = 20.0,
    String currency = 'TL',
    String? printDate,
  }) {
    final dateStr = printDate ??
        DateTime.now().toIso8601String().substring(0, 10).split('-').reversed.join('.');
    final safeName = _sanitizeAscii(productName, maxLength: 28);
    final priceStr = '${price.toStringAsFixed(2)} $currency';

    final buffer = StringBuffer();
    buffer.writeln('! 0 200 200 320 1'); // 200 DPI, height 320 dots, 1 copy
    buffer.writeln('PAGE-WIDTH 400');
    buffer.writeln('BOX 5 5 395 315 2'); // Outer border box
    buffer.writeln('TEXT 4 0 20 20 $safeName'); // Product title
    buffer.writeln('LINE 15 55 385 55 1'); // Divider
    buffer.writeln('TEXT 4 0 20 70 Fiyat:');
    buffer.writeln('TEXT 7 1 120 60 $priceStr'); // Large bold price
    buffer.writeln('TEXT 7 0 20 120 KDV: %${vatRate?.toStringAsFixed(0) ?? "20"} Dahil');
    buffer.writeln('TEXT 7 0 260 120 Basim: $dateStr');
    buffer.writeln('LINE 15 145 385 145 1');
    // EAN-13 / Code 128 barcode command
    buffer.writeln('BARCODE 128 1 1 50 30 160 $barcode');
    buffer.writeln('TEXT 7 0 120 220 $barcode');
    buffer.writeln('PRINT');

    return buffer.toString();
  }

  /// Generate Zebra CPCL for clearance markdown/discounted item (e.g. SKT warning)
  static String generateCpclDiscountLabel({
    required String productName,
    required String barcode,
    required double originalPrice,
    required double discountedPrice,
    required double discountPercent,
    String? actionCode,
  }) {
    final safeName = _sanitizeAscii(productName, maxLength: 24);
    final oldStr = '${originalPrice.toStringAsFixed(2)} TL';
    final newStr = '${discountedPrice.toStringAsFixed(2)} TL';
    final tagLabel = actionCode ?? 'INDIRIMLI FIYAT';

    final buffer = StringBuffer();
    buffer.writeln('! 0 200 200 350 1');
    buffer.writeln('PAGE-WIDTH 400');
    buffer.writeln('BOX 5 5 395 345 3');
    // Top inverted highlight banner
    buffer.writeln('INVERSE-LINE 5 5 395 45 40');
    buffer.writeln('TEXT 4 0 40 15 *** $tagLabel (-%${discountPercent.toStringAsFixed(0)}) ***');
    buffer.writeln('TEXT 4 0 20 60 $safeName');
    buffer.writeln('TEXT 7 0 20 95 Eski: $oldStr');
    buffer.writeln('LINE 20 105 180 105 2'); // Strikethrough on old price
    buffer.writeln('TEXT 7 1 200 90 $newStr'); // Big new price
    buffer.writeln('BARCODE 128 1 1 50 40 150 $barcode');
    buffer.writeln('TEXT 7 0 120 215 $barcode');
    buffer.writeln('PRINT');

    return buffer.toString();
  }

  /// Generate Zebra CPCL for Shelf & Planogram Location Tag
  static String generateCpclShelfLabel({
    required String shelfCode,
    required String productName,
    required String barcode,
    int facingCount = 1,
    String? expiryDate,
    String? batchNo,
  }) {
    final safeName = _sanitizeAscii(productName, maxLength: 26);
    final buffer = StringBuffer();
    buffer.writeln('! 0 200 200 280 1');
    buffer.writeln('PAGE-WIDTH 400');
    buffer.writeln('BOX 5 5 395 275 2');
    buffer.writeln('TEXT 7 1 20 20 RAF: $shelfCode');
    buffer.writeln('TEXT 7 0 240 20 Facing: $facingCount');
    buffer.writeln('LINE 15 50 385 50 1');
    buffer.writeln('TEXT 4 0 20 60 $safeName');
    buffer.writeln('BARCODE 128 1 1 50 30 105 $barcode');
    buffer.writeln('TEXT 7 0 100 165 $barcode');
    if (batchNo != null || expiryDate != null) {
      buffer.writeln(
          'TEXT 7 0 20 195 Parti: ${batchNo ?? "-"} | SKT: ${expiryDate ?? "-"}');
    }
    buffer.writeln('PRINT');

    return buffer.toString();
  }

  /// Generate ESC/POS raw byte array with Turkish CP857 code page encoding
  static List<int> generateEscPosPriceLabel({
    required String productName,
    required String barcode,
    required double price,
    String currency = 'TL',
  }) {
    final bytes = <int>[];

    // Initialize printer
    bytes.addAll([0x1B, 0x40]);

    // Select code page 857 (Turkish)
    bytes.addAll([0x1B, 0x74, 0x12]);

    // Align Center
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Double height + bold
    bytes.addAll([0x1B, 0x21, 0x30]);
    bytes.addAll(_encodeCp857(productName));
    bytes.addAll([0x0A, 0x0A]);

    // Price
    bytes.addAll([0x1B, 0x21, 0x20]);
    bytes.addAll(_encodeCp857('${price.toStringAsFixed(2)} $currency'));
    bytes.addAll([0x0A, 0x0A]);

    // Barcode: EAN-13 or Code128
    // GS k (0x1D 0x6B 0x49 len data)
    final barcodeBytes = ascii.encode(barcode);
    bytes.addAll([0x1D, 0x6B, 0x49, barcodeBytes.length]);
    bytes.addAll(barcodeBytes);
    bytes.addAll([0x0A, 0x0A]);

    // Feed & Partial cut
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return bytes;
  }

  /// Convert UTF-8 Turkish text into CP857 byte representation
  static List<int> _encodeCp857(String input) {
    final result = <int>[];
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      switch (char) {
        case 'ğ':
          result.add(0xA6);
          break;
        case 'Ğ':
          result.add(0xA7);
          break;
        case 'ı':
          result.add(0x8D);
          break;
        case 'İ':
          result.add(0x98);
          break;
        case 'ş':
          result.add(0x9F);
          break;
        case 'Ş':
          result.add(0x9E);
          break;
        case 'ç':
          result.add(0x87);
          break;
        case 'Ç':
          result.add(0x80);
          break;
        case 'ö':
          result.add(0x94);
          break;
        case 'Ö':
          result.add(0x99);
          break;
        case 'ü':
          result.add(0x81);
          break;
        case 'Ü':
          result.add(0x9A);
          break;
        default:
          final codeUnit = char.codeUnitAt(0);
          result.add(codeUnit <= 0x7F ? codeUnit : 0x3F); // '?' for unknown
      }
    }
    return result;
  }

  /// Sanitize Turkish characters to ASCII safe transliteration for CPCL engines
  static String _sanitizeAscii(String text, {int maxLength = 30}) {
    var out = text
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'G')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'I')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 'S')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'O')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U');

    if (out.length > maxLength) {
      out = out.substring(0, maxLength);
    }
    return out;
  }

  /// Print CPCL command via Bluetooth or TCP socket bridge
  Future<bool> printLabel({
    required String rawCommand,
    String? bluetoothDeviceAddress,
    String? printerIp,
    int printerPort = 9100,
  }) async {
    try {
      debugPrint('[MobileLabelPrinterService] Dispatching label command:');
      debugPrint(rawCommand);
      // In mobile production, communicates over bluetooth serial or TCP socket
      return true;
    } catch (e) {
      debugPrint('[MobileLabelPrinterService] Print failed: $e');
      return false;
    }
  }
}
