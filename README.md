# CH8-Odin
CHIP_8 emulator written in odin for learning purposes 
<img width="3072" height="1664" alt="Screenshot From 2026-10-18 01-10-06" src="https://github.com/user-attachments/assets/f433afee-b070-461c-967e-026b1d6332ad" />
<img width="884" height="638" alt="Screenshot From 2026-10-18 01-12-59" src="https://github.com/user-attachments/assets/b8342ec5-cc54-41ba-9f14-2cf9157c9e0c" />

## Controls

The standard 16-key CHIP-8 keypad is mapped to a QWERTY keyboard layout as follows:

| CHIP-8 Keypad | Keyboard Mapping |
| :---: | :---: |
| `1` `2` `3` `C` | `1` `2` `3` `4` |
| `4` `5` `6` `D` | `Q` `W` `E` `R` |
| `7` `8` `9` `E` | `A` `S` `D` `F` |
| `A` `0` `B` `F` | `Z` `X` `C` `V` |


## Building and Running

1. Clone the repository and navigate to the project directory:
   ```bash
   git clone https://github.com/KoUeN-XIII/CH8-Odin.git
   cd CH8-Odin
   odin build ./src -out:chip8
   ./chip8 roms/path/to/your/rom
   ```
