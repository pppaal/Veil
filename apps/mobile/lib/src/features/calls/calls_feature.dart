/// Calls stay off until a call can be placed: this build has no WebRTC, so
/// the call screen only plays timers and the history rows cannot call back.
/// While false, the Calls tab, the call history and the call screen have no
/// route, and nothing in the app offers a call.
const bool kCallsEnabled = false;
