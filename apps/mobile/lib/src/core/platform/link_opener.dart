import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link from a message in the app the phone has for it, usually
/// the browser. Opening sends Veil to the background like any trip away, so
/// with app lock on, coming back locks it: it is no system sheet the user
/// stays inside (SystemSheetGrace).
abstract interface class LinkOpener {
  /// Opens [uri]; true when the phone did. Only http and https links open:
  /// anything else is not a link and answers false at once.
  Future<bool> open(Uri uri);
}

/// Whether [uri] is a link a message may open: http or https, with a host.
bool isOpenableLink(Uri uri) => (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

/// url_launcher in its external application mode. It is not asked first
/// whether anything can open the link (no canLaunchUrl): the answer of the
/// launch itself says so.
class UrlLauncherLinkOpener implements LinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    if (!isOpenableLink(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No app for it, or the platform refused: the caller says it could
      // not open the link. The link itself is never logged.
      return false;
    }
  }
}

final linkOpenerProvider = Provider<LinkOpener>((ref) => const UrlLauncherLinkOpener());
