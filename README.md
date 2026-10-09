<p align="center"><img src="TexConverter.png" width="160" alt="TexConverter logo"></p>

# Serious Sam TEX Converter

View and convert the texture files (`.tex`) of **Serious Sam 1, 2 and 3** - and turn ordinary images into Serious Sam 1 textures.
Runs on **Windows and Linux**. Written in [PureBasic](https://www.purebasic.com).

## Features

- **Open** `.tex` files from Serious Engine 1 (version 3 and 4, effect textures), Serious Engine 2 and Serious Engine 3 (BFE 2011 and Fusion 2017), including DXT, BC5 normal maps and HDR skies.
- **Open straight from `.gro` archives**, with a search field.
- **Save as** TGA, PNG, PCX, BMP, TIFF, JPG, DDS (DXT1, DXT5, BC5 or uncompressed, with mipmaps), Radiance HDR, or as a **Serious Sam 1 `.tex`**.
- Also opens TGA, PNG, PCX, BMP, TIFF, JPG, DDS and HDR images.
- **Warnings** before anything is lost while saving (transparency, HDR brightness, size, clipping).
- **HDR** exposure and tone (editor-style clip or filmic), lossless export to `.hdr`.
- **Editing with Undo/Redo**: Levels, Auto levels (never clips), Resize (good-quality downscaling, "fit Serious Sam 1" in one click), channel tools (extract, load or invert alpha), normal map tools (flip green, rebuild Z, normalize, create from a height map).
- **Histogram** window, including real HDR brightness in stops.
- **Batch conversion** of many files or whole archives at once.
- **Skybox** window: finds all faces of a set, checks how they fit, and exports separate faces, a strip, a cross or a 360-degree panorama (also as HDR).
- Preferences, remembered folders and window position, and a full **help file** (English) with background information on the formats, HDR and cube maps.

## Download

Get the latest version from the **[Releases](../../releases)** page. **Windows**: unzip `SS-TexConverter-1.00-Windows.zip` anywhere and run `SS1TexConverter2.exe`. **Linux**: unpack `SS-TexConverter-1.00-Linux.tar.gz` (`tar -xzf ...`) and run `./SS1TexConverter2`. Keep the `Help` folder next to the program so **Help > Help** (Ctrl+H) works.

## Building from source

1. Install **PureBasic 6.41** or newer (Windows or Linux).
2. Open `TexConverter.pb` and compile it (all `.pbi` files are included automatically).
   From the command line: `pbcompiler TexConverter.pb /EXE SS1TexConverter2.exe` (Windows) or `pbcompiler -e TexConverter TexConverter.pb` (Linux).
3. Put the `Help` folder next to the program.
4. On Linux, `sh build-linux.sh` compiles the program and makes the release archive in one go. A program compiled on Linux can also be packed on Windows with `make-linux-release.ps1`.

The code uses no Windows API, so the same source compiles on Linux. The comments in the source code are in Dutch.

| File | What it does |
|------|--------------|
| `TexConverter.pb` | Main program: window, menus, open/save |
| `TexReader.pbi`, `TexReaderSE2.pbi`, `TexReaderSE3.pbi` | Reading Serious Engine 1, 2 and 3 textures |
| `TexWriterSE1.pbi` | Writing Serious Sam 1 textures |
| `ImageReader.pbi` | Reading TGA, PCX, DDS, HDR, TIFF and other images |
| `TGAWriter.pbi`, `PCXWriter.pbi`, `TIFFWriter.pbi`, `HDRWriter.pbi`, `DDSWriter.pbi` | Writing image formats |
| `DXT.pbi`, `DXTEncode.pbi` | DXT1/3/5 and BC5 decoding and encoding |
| `GroReader.pbi` | Reading `.gro` archives |
| `Adjust.pbi`, `Resize.pbi`, `Channels.pbi`, `NormalMap.pbi` | Image editing |
| `EditHistory.pbi` | Undo and Redo |
| `Histogram.pbi`, `Skybox.pbi`, `Batch.pbi` | The extra windows |
| `Settings.pbi`, `Preferences.pbi` | Settings and the Preferences window |
| `Help/TexConverter-Help.html` | The help file |

## Credits

- Concept & design: **Thei van Duin** (TheySoft)
- Programming & debugging: **Claude Opus** (Anthropic)

## License

[MIT](LICENSE) - free to use, change and share, as long as the copyright notice stays with it.

*Serious Sam is a trademark of Croteam. This is a fan-made tool and is not affiliated with or endorsed by Croteam or Devolver Digital. No game files are included.*
