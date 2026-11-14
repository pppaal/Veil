// What this browser tells the relay about its device when it registers or
// claims a device transfer. The relay stores both (devices.device_name and
// devices.platform) and can read them, so neither depends on the browser:
// the name says only that this is the web client, never navigator.platform
// ('MacIntel', 'Win32', 'Linux x86_64'), which would tell the server the
// user's operating system. The user may rename it when claiming a transfer.
// The relay's DevicePlatform enum has no value for a browser yet, so every
// browser registers as 'android': wrong in the devices list, but the same
// for every browser, so it tells the server nothing either.

export const WEB_DEVICE_NAME = 'VEIL Web';
export const WEB_DEVICE_PLATFORM = 'android';
