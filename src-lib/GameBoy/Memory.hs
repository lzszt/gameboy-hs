{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoFieldSelectors #-}

module GameBoy.Memory where

import Control.Monad
import Data.ByteString qualified as BS
import Data.Vector (Vector)
import Data.Vector qualified as Vector
import Optics

import GameBoy.BitStuff

type Memory = Vector U8

data MemoryBus = MemoryBus
    { _cartridge :: Memory
    -- ^ Cartridge RAM: $0000 - $7fff
    , _vram :: Memory
    -- ^ VRAM: $8000 - $9fff
    , _sram :: Memory
    -- ^ SRAM: $a000 - $bfff
    , _wram :: Memory
    -- ^ WRAM: $c000 - $dfff
    , _oam :: Memory
    -- ^ Object attribute memory: $fe00 - $fe9f
    , _io :: Memory
    -- ^ IO registers: $ff00 - $ff7f
    , _hram :: Memory
    -- ^ HRAM: $ff80 - $fffe
    , _ie :: U8
    -- ^ Interrupt register: $ffff
    }
    deriving (Show)

makeLenses ''MemoryBus

-- | Target the n-th byte of a memory array.  This is (of course) only a lens if
-- and only if the index is inside the boundaries of the array.
byte :: U16 -> Lens' Memory U8
byte n =
    lens
        (\mem -> mem Vector.! fromIntegral n)
        (\mem x -> mem Vector.// [(fromIntegral n, x)])

readByte :: MemoryBus -> U16 -> U8
readByte bus addr
    | addr < 0x8000 = bus._cartridge Vector.! fromIntegral addr
    | addr < 0xa000 = bus._vram Vector.! fromIntegral (addr - 0x8000)
    | addr < 0xc000 = bus._sram Vector.! fromIntegral (addr - 0xa000)
    | addr < 0xe000 = bus._wram Vector.! fromIntegral (addr - 0xc000)
    | addr < 0xfe00 = bus._wram Vector.! fromIntegral (addr - 0xc000) -- echoes WRAM
    | addr < 0xfea0 = bus._oam Vector.! fromIntegral (addr - 0xfe00)
    | addr < 0xff00 = 0 -- forbidden area
    | addr < 0xff80 = bus._io Vector.! fromIntegral (addr - 0xff00)
    | addr < 0xffff = bus._hram Vector.! fromIntegral (addr - 0xff80)
    | addr == 0xffff = bus._ie
    | otherwise = error "the impossible happened"

writeByte :: U16 -> U8 -> MemoryBus -> MemoryBus
writeByte addr n bus
    -- writes to cartridge ROM cannot happen, but can be used to trigger MBC
    -- interaction
    | addr < 0x8000 = bus
    | addr < 0xa000 = writeTo vram 0x8000
    | addr < 0xc000 = writeTo sram 0xa000
    | addr < 0xe000 = writeTo wram 0xc000
    | addr < 0xfe00 = writeTo wram 0xc000 -- echoes WRAM
    | addr < 0xfea0 = writeTo oam 0xfe00
    | addr < 0xff00 = bus -- forbidden area
    | addr < 0xff80 = writeIO addr n bus
    | addr < 0xffff = writeTo hram 0xff80
    | addr == 0xffff = bus & ie .~ n
    | otherwise = error "the impossible happened"
  where
    writeTo dest offset =
        bus & dest % byte (addr - offset) .~ n

writeIO :: U16 -> U8 -> MemoryBus -> MemoryBus
writeIO addr n bus =
    case addr of
        -- writing anything to the divider or scanline register resets them
        0xff04 -> bus & divider .~ 0
        0xff44 -> bus & scanline .~ 0
        _ -> bus & io % byte relativeAddr .~ n
  where
    relativeAddr = addr - 0xff00

readU16 :: MemoryBus -> U16 -> U16
readU16 bus addr =
    -- GameBoy is little-endian
    combineBytes (readByte bus $ addr + 1) (readByte bus addr)

scanline :: Lens' MemoryBus U8
scanline = io % byte 0x44

lcdc :: Lens' MemoryBus U8
lcdc = io % byte 0x40

lcdEnable :: Lens' MemoryBus Bool
lcdEnable = lcdc % bit 7

displayWindow :: Lens' MemoryBus Bool
displayWindow = lcdc % bit 5

objSize :: Lens' MemoryBus Bool
objSize = lcdc % bit 2

objEnabled :: Lens' MemoryBus Bool
objEnabled = lcdc % bit 1

lcdStatus :: Lens' MemoryBus U8
lcdStatus = io % byte 0x41

viewportY :: Lens' MemoryBus U8
viewportY = io % byte 0x42

viewportX :: Lens' MemoryBus U8
viewportX = io % byte 0x43

lyc :: Lens' MemoryBus U8
lyc = io % byte 0x45

windowY :: Lens' MemoryBus U8
windowY = io % byte 0x4a

windowX :: Lens' MemoryBus U8
windowX = io % byte 0x4b

divider :: Lens' MemoryBus U8
divider = io % byte 0x04

tima :: Lens' MemoryBus U8
tima = io % byte 0x05

tma :: Lens' MemoryBus U8
tma = io % byte 0x06

tac :: Lens' MemoryBus U8
tac = io % byte 0x07

timerEnable :: Lens' MemoryBus Bool
timerEnable = tac % bit 2

interruptFlags :: Lens' MemoryBus U8
interruptFlags = io % byte 0x0f

timerIntRequested :: Lens' MemoryBus Bool
timerIntRequested = interruptFlags % bit 2

dma :: Lens' MemoryBus U8
dma = io % byte 0x46

{- FOURMOLU_DISABLE -}

bios :: Memory
bios =
    [ 0x31, 0xfe, 0xff, 0xaf, 0x21, 0xff, 0x9f, 0x32, 0xcb, 0x7c, 0x20, 0xfb, 0x21, 0x26, 0xff, 0x0e
    , 0x11, 0x3e, 0x80, 0x32, 0xe2, 0x0c, 0x3e, 0xf3, 0xe2, 0x32, 0x3e, 0x77, 0x77, 0x3e, 0xfc, 0xe0
    , 0x47, 0x11, 0x04, 0x01, 0x21, 0x10, 0x80, 0x1a, 0xcd, 0x95, 0x00, 0xcd, 0x96, 0x00, 0x13, 0x7b
    , 0xfe, 0x34, 0x20, 0xf3, 0x11, 0xd8, 0x00, 0x06, 0x08, 0x1a, 0x13, 0x22, 0x23, 0x05, 0x20, 0xf9
    , 0x3e, 0x19, 0xea, 0x10, 0x99, 0x21, 0x2f, 0x99, 0x0e, 0x0c, 0x3d, 0x28, 0x08, 0x32, 0x0d, 0x20
    , 0xf9, 0x2e, 0x0f, 0x18, 0xf3, 0x67, 0x3e, 0x64, 0x57, 0xe0, 0x42, 0x3e, 0x91, 0xe0, 0x40, 0x04
    , 0x1e, 0x02, 0x0e, 0x0c, 0xf0, 0x44, 0xfe, 0x90, 0x20, 0xfa, 0x0d, 0x20, 0xf7, 0x1d, 0x20, 0xf2
    , 0x0e, 0x13, 0x24, 0x7c, 0x1e, 0x83, 0xfe, 0x62, 0x28, 0x06, 0x1e, 0xc1, 0xfe, 0x64, 0x20, 0x06
    , 0x7b, 0xe2, 0x0c, 0x3e, 0x87, 0xe2, 0xf0, 0x42, 0x90, 0xe0, 0x42, 0x15, 0x20, 0xd2, 0x05, 0x20
    , 0x4f, 0x16, 0x20, 0x18, 0xcb, 0x4f, 0x06, 0x04, 0xc5, 0xcb, 0x11, 0x17, 0xc1, 0xcb, 0x11, 0x17
    , 0x05, 0x20, 0xf5, 0x22, 0x23, 0x22, 0x23, 0xc9, 0xce, 0xed, 0x66, 0x66, 0xcc, 0x0d, 0x00, 0x0b
    , 0x03, 0x73, 0x00, 0x83, 0x00, 0x0c, 0x00, 0x0d, 0x00, 0x08, 0x11, 0x1f, 0x88, 0x89, 0x00, 0x0e
    , 0xdc, 0xcc, 0x6e, 0xe6, 0xdd, 0xdd, 0xd9, 0x99, 0xbb, 0xbb, 0x67, 0x63, 0x6e, 0x0e, 0xec, 0xcc
    , 0xdd, 0xdc, 0x99, 0x9f, 0xbb, 0xb9, 0x33, 0x3e, 0x3c, 0x42, 0xb9, 0xa5, 0xb9, 0xa5, 0x42, 0x3c
    , 0x21, 0x04, 0x01, 0x11, 0xa8, 0x00, 0x1a, 0x13, 0xbe, 0x20, 0xfe, 0x23, 0x7d, 0xfe, 0x34, 0x20
    , 0xf5, 0x06, 0x19, 0x78, 0x86, 0x23, 0x05, 0x20, 0xfb, 0x86, 0x20, 0xfe, 0x3e, 0x01, 0xe0, 0x50
    ]

ioInitialValues :: Memory
ioInitialValues =
    [ 0x0f, 0x00, 0x7c, 0xff, 0x00, 0x00, 0x00, 0xf8, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01
    , 0x80, 0xbf, 0xf3, 0xff, 0xbf, 0xff, 0x3f, 0x00, 0xff, 0xbf, 0x7f, 0xff, 0x9f, 0xff, 0xbf, 0xff
    , 0xff, 0x00, 0x00, 0xbf, 0x77, 0xf3, 0xf1, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    , 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff
    , 0x91, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfc, 0x00, 0x00, 0x00, 0x00, 0xff, 0x7e, 0xff, 0xfe
    , 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x3e, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    , 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xc0, 0xff, 0xc1, 0x00, 0xfe, 0xff, 0xff, 0xff
    , 0xf8, 0xff, 0x00, 0x00, 0x00, 0x8f, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    , 0xce, 0xed, 0x66, 0x66, 0xcc, 0x0d, 0x00, 0x0b, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0c, 0x00, 0x0d
    , 0x00, 0x08, 0x11, 0x1f, 0x88, 0x89, 0x00, 0x0e, 0xdc, 0xcc, 0x6e, 0xe6, 0xdd, 0xdd, 0xd9, 0x99
    , 0xbb, 0xbb, 0x67, 0x63, 0x6e, 0x0e, 0xec, 0xcc, 0xdd, 0xdc, 0x99, 0x9f, 0xbb, 0xb9, 0x33, 0x3e
    , 0x45, 0xec, 0x52, 0xfa, 0x08, 0xb7, 0x07, 0x5d, 0x01, 0xfd, 0xc0, 0xff, 0x08, 0xfc, 0x00, 0xe5
    , 0x0b, 0xf8, 0xc2, 0xce, 0xf4, 0xf9, 0x0f, 0x7f, 0x45, 0x6d, 0x3d, 0xfe, 0x46, 0x97, 0x33, 0x5e
    , 0x08, 0xef, 0xf1, 0xff, 0x86, 0x83, 0x24, 0x74, 0x12, 0xfc, 0x00, 0x9f, 0xb4, 0xb7, 0x06, 0xd5
    , 0xd0, 0x7a, 0x00, 0x9e, 0x04, 0x5f, 0x41, 0x2f, 0x1d, 0x77, 0x36, 0x75, 0x81, 0xaa, 0x70, 0x3a
    , 0x98, 0xd1, 0x71, 0x02, 0x4d, 0x01, 0xc1, 0xff, 0x0d, 0x00, 0xd3, 0x05, 0xf9, 0x00, 0x0b, 0x0
    ]

{- FOURMOLU_ENABLE -}

loadCartridgeFromFile :: FilePath -> IO Memory
loadCartridgeFromFile path = do
    bytes <- BS.readFile path
    let len = BS.length bytes
    when (len > 0x8000) (fail $ "Unexpected cartridge size: " <> show len)
    let padded = BS.unpack bytes <> replicate (0x10000 - len) 0
    pure $ Vector.fromList padded

defaultMemoryBus :: MemoryBus
defaultMemoryBus =
    -- TODO: set correct initial values
    MemoryBus
        { _ie = 0x0 -- TODO check this
        , _hram = mkEmptyMemory 0x80
        , _io = ioInitialValues
        , _oam = mkEmptyMemory 0x100
        , _wram = mkEmptyMemory 0x2000
        , _sram = mkEmptyMemory 0x2000
        , _vram = mkEmptyMemory 0x2000
        , _cartridge = mkEmptyMemory 0x8000
        }

mkEmptyMemory :: U16 -> Memory
mkEmptyMemory len =
    Vector.replicate (fromIntegral len) 0

initializeMemoryBus :: FilePath -> IO MemoryBus
initializeMemoryBus path = do
    cart <- loadCartridgeFromFile path
    pure $ set cartridge cart defaultMemoryBus
