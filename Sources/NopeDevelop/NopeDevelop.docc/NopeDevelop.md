# ``NopeDevelop``

RAW development to HEIF and JPEG with Core Image and the system encoders.

## Overview

`NopeDevelop` turns the RAW from the sensor into HEIF and JPEG, neutrally: no noise reduction,
sharpening or local tone mapping, and never the phone's own pipeline. It encodes only with the
system encoders through ImageIO.

``RAWDeveloper`` renders the DNG with `CoreImageRAWRenderer` and encodes it with the system
encoders (``EncodingSettings``), writing only the metadata `MetadataPlan` built from the
allowlist. ``ImageIOReadBack`` reads every finished file back for the fail-closed check: the
project's own tag reader in `NopeCore`, plus every key ImageIO reports when it opens the file.

Related documentation: `docs/ARCHITECTURE.md` and `docs/PRIVACY.md` in the repository.

## Topics

### Development

- ``RAWDeveloper``
- ``EncodingSettings``

### Read-back

- ``ImageIOReadBack``
