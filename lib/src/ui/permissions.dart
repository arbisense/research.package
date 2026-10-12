part of '../../ui.dart';

/// Requests the OS permissions declared on the sections of a
/// [RPConsentDocument].
///
/// This is the only place in Research Package which talks to the platform about
/// permissions. It is used by [RPUIVisualConsentStep] when the step has
/// [RPVisualConsentStep.askPermission] set to `true`, but can also be called
/// directly by an app which wants to ask for a permission outside a consent
/// flow.
class RPPermissions {
  RPPermissions._();

  /// Asks the OS for [type] and returns the outcome.
  ///
  /// If the participant has already granted the permission the OS does not show
  /// a dialog and [RPPermissionStatus.granted] is returned right away.
  ///
  /// Never throws — a platform without an implementation for the permission
  /// resolves to [RPPermissionStatus.unknown] rather than interrupting the
  /// consent flow.
  static Future<RPPermissionStatus> request(RPPermissionType type) async {
    // iOS grants background execution through declared background modes.
    if (type == RPPermissionType.ignoreBatteryOptimizations &&
        defaultTargetPlatform != TargetPlatform.android) {
      return RPPermissionStatus.unsupported;
    }

    try {
      // Background location requires the foreground one first, on both
      // platforms.
      if (type == RPPermissionType.locationAlways) {
        final foreground = _statusOf(
          await ph.Permission.locationWhenInUse.request(),
        );
        if (foreground != RPPermissionStatus.granted) return foreground;
      }

      // Android 12 replaced the Bluetooth permission - which is granted
      // without asking - with the "Nearby devices" pair. Asking for both in
      // one call shows a single dialog.
      if (type == RPPermissionType.bluetooth &&
          defaultTargetPlatform == TargetPlatform.android) {
        final statuses = await [
          ph.Permission.bluetoothScan,
          ph.Permission.bluetoothConnect,
        ].request();

        return statuses.values
            .map(_statusOf)
            .firstWhere(
              (status) => status != RPPermissionStatus.granted,
              orElse: () => RPPermissionStatus.granted,
            );
      }

      return _statusOf(await _permissionOf(type).request());
    } catch (error) {
      debugPrint('$RPPermissions - error requesting $type - error: $error');
      return RPPermissionStatus.unknown;
    }
  }

  /// The platform permission to ask for to obtain [type].
  ///
  /// Most types map one-to-one, but activity recognition does not exist as such
  /// on iOS, where the equivalent data comes from CoreMotion.
  static ph.Permission _permissionOf(RPPermissionType type) {
    switch (type) {
      case RPPermissionType.location:
        return ph.Permission.locationWhenInUse;
      case RPPermissionType.locationAlways:
        return ph.Permission.locationAlways;
      case RPPermissionType.microphone:
        return ph.Permission.microphone;
      case RPPermissionType.camera:
        return ph.Permission.camera;
      case RPPermissionType.notification:
        return ph.Permission.notification;
      case RPPermissionType.activityRecognition:
        // iOS has no such permission - the data comes from CoreMotion.
        return Platform.isIOS
            ? ph.Permission.sensors
            : ph.Permission.activityRecognition;
      case RPPermissionType.sensors:
        return ph.Permission.sensors;
      case RPPermissionType.bluetooth:
        return ph.Permission.bluetooth;
      case RPPermissionType.ignoreBatteryOptimizations:
        return ph.Permission.ignoreBatteryOptimizations;
    }
  }

  static RPPermissionStatus _statusOf(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      // Partial access - some photos, provisional notifications - still counts.
      case ph.PermissionStatus.limited:
      case ph.PermissionStatus.provisional:
        return RPPermissionStatus.granted;
      case ph.PermissionStatus.denied:
        return RPPermissionStatus.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return RPPermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return RPPermissionStatus.restricted;
    }
  }
}
