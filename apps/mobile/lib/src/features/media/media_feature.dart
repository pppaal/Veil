/// The media picker stays off until it reads the device's photos and
/// videos: this build has no gallery or camera plugin, so its grid is a
/// placeholder and what it "sends" goes nowhere. While false, the picker has
/// no route and nothing opens it.
const bool kMediaPickerEnabled = false;
