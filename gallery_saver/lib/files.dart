// Copied from gallery_saver-2.3.2/lib/files.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class GallerySaver {
  static const MethodChannel _channel = MethodChannel('gallery_saver');

  static Future<bool?> saveImage(String path, {String? albumName, bool toDcim = false}) async {
    final bool? result = await _channel.invokeMethod('saveImage', <String, dynamic>{
      'path': path,
      'albumName': albumName,
      'toDcim': toDcim,
    });
    return result;
  }

  static Future<bool?> saveVideo(String path, {String? albumName, bool toDcim = false}) async {
    final bool? result = await _channel.invokeMethod('saveVideo', <String, dynamic>{
      'path': path,
      'albumName': albumName,
      'toDcim': toDcim,
    });
    return result;
  }
}
