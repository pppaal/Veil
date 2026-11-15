/// Voice messages stay off until one can be recorded and sent: this build
/// has no audio plugin and never opens the microphone. Its screen says that
/// and leaves; it records nothing and sends nothing. While false, the
/// recorder has no route and nothing opens it.
const bool kVoiceMessagesEnabled = false;
