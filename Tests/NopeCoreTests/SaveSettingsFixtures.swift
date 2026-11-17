import NopeCore

extension SaveSettings {
    /// RAW plus HEIF, signed: the first-launch settings before issue #80 made RAW only and
    /// signing off the defaults. The save pipeline tests use it as a typical choice that
    /// develops a copy and signs every file.
    static var rawPlusHEIFSigned: SaveSettings {
        var settings = SaveSettings()
        settings.setFormat(.heif, isSelected: true)
        settings.metadata.signsPhotos = true
        return settings
    }
}
