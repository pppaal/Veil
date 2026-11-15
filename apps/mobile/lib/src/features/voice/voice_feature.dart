/// Voice messages stay off until one can be recorded and sent: this build
/// has no audio plugin, so the recorder only counts seconds and its send
/// button sends nothing. While false, the recorder has no route and nothing
/// opens it.
const bool kVoiceMessagesEnabled = false;
