/// Attachments stay off until a file can be picked, sent and opened: this
/// build has no file picker and a received attachment stops at the download
/// ticket. The attachment screen says what it sends instead (a 2 KB
/// placeholder of random bytes under a typed name, sealed and uploaded the
/// way a chosen file will be). While false, the composer has no attach
/// button, the attachment screen has no route, and an attachment in a
/// message is shown as what it is, with a line saying this version cannot
/// open it in place of the download button.
///
/// The transfer code underneath (sealing, upload tickets, retry) is real and
/// stays tested: it is what a file picker will feed.
const bool kAttachmentsEnabled = false;
