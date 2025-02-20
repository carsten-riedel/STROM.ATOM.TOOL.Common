magick -density 256x256 -background transparent STROM_LOGO.svg -define icon:auto-resize=256,128,64,48,32,16 -colors 256 favicon.ico
magick -background transparent -size 256x256 STROM_LOGO.SVG STROM_LOGO_256.png
magick -background transparent -size 128x128 STROM_LOGO.SVG STROM_LOGO_128.png
magick -background transparent -size 64x64 STROM_LOGO.SVG STROM_LOGO_64.png
magick -background transparent -size 48x48 STROM_LOGO.SVG STROM_LOGO_48.png
magick -background transparent -size 32x32 STROM_LOGO.SVG STROM_LOGO_32.png
magick -background transparent -size 16x16 STROM_LOGO.SVG STROM_LOGO_16.png