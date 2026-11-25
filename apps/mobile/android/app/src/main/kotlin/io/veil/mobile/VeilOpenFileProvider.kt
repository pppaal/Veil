package io.veil.mobile

import androidx.core.content.FileProvider

/**
 * The app's own FileProvider (authority ${applicationId}.veil_open), serving
 * only cache/veil_open (res/xml/veil_open_paths.xml): a subclass, so no
 * plugin's FileProvider entry can merge with it or widen what it serves.
 */
class VeilOpenFileProvider : FileProvider()
