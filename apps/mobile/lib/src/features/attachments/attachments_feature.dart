/// Attachments stay off until a file can be picked, sent and opened: this
/// build has no file picker, and a received attachment stops at the download
/// ticket. While false, the composer has no attach button and nothing can
/// be attached; an attachment in a received message is shown as what it
/// is, with a line saying this version can't open it in place of the
/// download button.
///
/// The transfer code underneath (sealing, upload tickets, retry) is real and
/// stays tested: it is what a file picker will feed.
const bool kAttachmentsEnabled = false;
