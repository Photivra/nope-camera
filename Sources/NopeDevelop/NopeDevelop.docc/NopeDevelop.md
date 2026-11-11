# ``NopeDevelop``

RAW development to HEIF and JPEG with Core Image and the system encoders.

## Overview

`NopeDevelop` turns the RAW from the sensor into HEIF and JPEG, neutrally: no noise reduction,
sharpening or local tone mapping, and never the phone's own pipeline. It encodes only with the
system encoders through ImageIO.

The scaffold contains the encoding settings for each developed format. The Core Image developer
follows.

Related documentation: `docs/ARCHITECTURE.md` and `docs/PRIVACY.md` in the repository.

## Topics

### Encoding

- ``EncodingSettings``
