/// Calls stay off until a call can be placed: this build has no WebRTC and
/// no audio or video capture. Its screens say so rather than play one: the
/// call screen names the person, says no call can be made here and leaves,
/// and the history lists the calls the relay has on record, where a row
/// opens the chat with that person. Neither starts anything at the relay.
/// While false, the Calls tab, the call history and the call screen have no
/// route, and nothing in the app offers a call.
const bool kCallsEnabled = false;
