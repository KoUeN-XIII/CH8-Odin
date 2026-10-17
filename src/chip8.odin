package main 

import "core:fmt"
import "core:container/queue"
import "core:math/rand"
import "core:os"

import rl "vendor:raylib"


DISPLAY_UPDATE :: 60
DISPLAY_WIDTH  :: 64
DISPLAY_HEIGHT :: 32
DISPLAY_SIZE   :: DISPLAY_WIDTH * DISPLAY_HEIGHT
OFF_COLOR    :: rl.Color{0x2e, 0x30, 0x37, 0xFF} // #2e3037 Obra Dinn - IBM 8503 Palette
ON_COLOR :: rl.Color{0xeb, 0xe5, 0xce, 0xFF} // #ebe5ce by PureAsbestos

WINDOW_WIDTH   :: 640
WINDOW_HEIGHT  :: 320

MEMORY_SIZE :: 4096

FONT_START_ADDR :: 0x050;


FONTSET := [80]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
}

KEY_MAPPING := [16]rl.KeyboardKey{
	0x1 = .ONE,
	0x2 = .TWO,
	0x3 = .THREE,
	0xC = .FOUR,
	
	0x4 = .Q,
	0x5 = .W,
	0x6 = .E,
	0xD = .R,
	
	0x7 = .A,
	0x8 = .S,
	0x9 = .D,
	0xE = .F,
	
	0xA = .Z,
	0x0 = .X,
	0xB = .C,
	0xF = .V,
}

BEEP_WAV_BYTES :: #load("beep.wav")

CHIP_8 :: struct
{
  memory : [MEMORY_SIZE]u8,
  pc : u16,
  i: u16,
  delay_timer : u8,
  sound_timer : u8,
  v_registers : [16]u8,
  display: [DISPLAY_SIZE]bool,
  keys: [16]bool,
  stack: queue.Queue(u16),
}

decrement_timer :: proc(timer: ^u8)
{
    if timer^ > 0 {timer^ -= 1;}
}

tick_timers :: proc(chip_8: ^CHIP_8)
{
    decrement_timer(&chip_8.delay_timer)
    decrement_timer(&chip_8.sound_timer)
}

beep :: proc(sound_timer: u8, sound: rl.Sound) 
{
    if sound_timer > 0 && !rl.IsSoundPlaying(sound) {rl.PlaySound(sound)} 
    else if sound_timer == 0 && rl.IsSoundPlaying(sound) {rl.StopSound(sound)}
}

delay :: proc(delay_timer: u8) {if delay_timer > 0 {}}

fetch :: proc(chip_8: ^CHIP_8) ->  (instruction: u16)
{
  first_byte, second_byte : u8

  first_byte  = chip_8.memory[chip_8.pc]
  second_byte = chip_8.memory[chip_8.pc+1]

  instruction = (u16(first_byte) << 8) | u16(second_byte)
  chip_8.pc += 0x2

  return 
}

clear_screen :: proc(display: []bool) {for &pixel in display {pixel = false}}
return_from_subroutine :: proc(pc: ^u16, stack: ^queue.Queue(u16)) {pc^ = queue.back(stack); queue.pop_back(stack)}
jump_to_address :: proc(pc: ^u16, address: u16) {pc^ = address}
call_subroutine_at_address :: proc(pc: ^u16,  stack: ^queue.Queue(u16), address: u16) {queue.push_back(stack, pc^); pc^ = address}

skip_next_instruction_if_vx ::proc(pc: ^u16, v_register: []u8, opcode: u8, x: u8, nn: u8) 
{
  if opcode == 0x3 {if v_register[x] == nn {pc^ += 0x2} else {}}
  else if opcode == 0x4 {if v_register[x] != nn {pc^ += 0x2} else{}}
}

skip_next_instruction_if_vx_vy ::proc(pc: ^u16, v_register: []u8, opcode : u8, x: u8, y: u8) 
{
  if opcode == 0x5 { if v_register[x] == v_register[y] {pc^ += 0x2} else {}}
  else if opcode == 0x9 {if v_register[x] != v_register[y] {pc^ += 0x2} else {}}
}

set_vx_value :: proc(v_register: []u8, opcode: u8, x: u8, nn: u8) 
{
  switch opcode 
  {
  case 0x6:
    v_register[x] = nn
  case 0x7:
    v_register[x] += nn
  case 0xC:
    v_register[x] = u8(rand.int_max(255)) & nn
  }
}

set_vx_vy :: proc(v_register: []u8, x: u8, y: u8, n: u8) 
{
  switch n 
  {
  case 0x0:
    v_register[x] = v_register[y]
  case 0x1:
    v_register[x] = v_register[x] | v_register[y]
  case 0x2:
    v_register[x] = v_register[x] & v_register[y]
  case 0x3:
    v_register[x] = v_register[x] ~ v_register[y]

  case 0x4:
    sum := u16(v_register[x]) + u16(v_register[y])
    v_register[0xF] = 1 if sum > 0xFF else 0 
    v_register[x] = u8(sum)         

  case 0x5:
    v_register[0xF] = 1 if v_register[x] >= v_register[y] else 0
    v_register[x] = v_register[x] - v_register[y]

  case 0x6:
    v_register[0xF] = v_register[x] & 1
    v_register[x] /= 2

  case 0x7:
    v_register[0xF] = 1 if v_register[y] >= v_register[x] else 0
    v_register[x] = v_register[y] - v_register[x]

  case 0xE:
    v_register[0xF] = (v_register[x] >> 7) & 1
    v_register[x] *= 2
  }
}

set_i_register :: proc(i: ^u16, address: u16) {i^ = address}
jump_with_offset :: proc(pc: ^u16, v_register: []u8, address: u16) {pc^ = address + u16(v_register[0x0])}


is_pixel_on :: proc(display: []bool, x_coord: u8, y_coord: u8) -> bool {return display[(y_coord * DISPLAY_WIDTH) + x_coord] }
set_pixel :: proc(display: []bool, x_coord: u8, y_coord: u8, is_on: bool ) {display[(y_coord * DISPLAY_WIDTH) + x_coord] = is_on}

display :: proc(chip_8: ^CHIP_8, x: u8, y: u8, n: u8) 
{
    vx := chip_8.v_registers[x]
    vy := chip_8.v_registers[y]

    chip_8.v_registers[0xF] = 0

    for j in 0..<n
    {
        sprite_byte := chip_8.memory[chip_8.i + u16(j)]
        

        y_coord := (vy + u8(j)) % DISPLAY_HEIGHT

        for k in 0..<8
        {

            is_bit_on := ((sprite_byte >> u8(7 - k)) & 1) != 0 
            if !is_bit_on do continue


            x_coord := (vx + u8(k)) % DISPLAY_WIDTH

            index := u32(y_coord) * DISPLAY_WIDTH + u32(x_coord)

            if chip_8.display[index] 
            {
                chip_8.display[index] = false
                chip_8.v_registers[0xF] = 1
            } 
            else 
            { 
                chip_8.display[index] = true 
            }
        }
    }
}

input_update :: proc(chip_8: ^CHIP_8)
{
	for i in 0..<16
  {
    kb_key := KEY_MAPPING[i]
		chip_8.keys[i] = rl.IsKeyDown(kb_key)
	}
}

skip_on_key :: proc(pc: ^u16, keys: []bool, v_registers: []u8, nn: u8, x: u8) 
{
	key_val := v_registers[x] & 0x0F
	switch nn 
  {
	case 0x9E:
		if keys[key_val] {pc^ += 2}
	case 0xA1:
		if !keys[key_val] {pc^ += 2}
	}
}

store_pressed_key :: proc(pc: ^u16, keys: []bool, v_register: []u8, x: u8) 
{
	key_pressed := false
	for i in 0..<16 
  {
		if keys[i] 
    {
			v_register[x] = u8(i)
			key_pressed = true
			break
		}
	}
	if !key_pressed 
  {
		pc^ -= 2
	}
}

set_vx_to_delay_timer :: proc(delay_timer: u8, v_register: []u8, x: u8) {v_register[x] = delay_timer}
set_delay_timer_to_vx :: proc(delay_timer: ^u8, v_register: []u8, x: u8) {delay_timer^ = v_register[x]}
set_sound_timer_to_vx :: proc(sound_timer: ^u8, v_register: []u8, x: u8) {sound_timer^ = v_register[x]}
set_i_to_i_plus_vx :: proc(v_register: []u8, i: ^u16, x: u8) {i^ = i^ + u16(v_register[x])}
store_bcd_of_vx_in_memory :: proc(memory: []u8, v_register: []u8, i: u16, x:u8) 
{
  memory[i] = v_register[x] / 100;
  memory[i+1] = (v_register[x] % 100) / 10;
  memory[i+2] = v_register[x] % 10;
}

store_v0_to_vx_in_memory :: proc(memory: []u8, v_register: []u8, i: u16, x: u8) 
{
	for j in 0..=x {memory[i + u16(j)] = v_register[j]}
}

read_v0_to_vx_from_memory :: proc(memory: []u8, v_register: []u8, i: u16, x: u8)
{
	for j in 0..=x {v_register[j] = memory[i + u16(j)]}
}

execute_f_instructions :: proc(chip_8: ^CHIP_8, x: u8, nn: u8)
{
	switch nn
	{
	case 0x07:
		set_vx_to_delay_timer(chip_8.delay_timer, chip_8.v_registers[:], x)
  case 0x0A:
		store_pressed_key(&chip_8.pc, chip_8.keys[:], chip_8.v_registers[:], x)
	case 0x15:
		set_delay_timer_to_vx(&chip_8.delay_timer, chip_8.v_registers[:], x)
	case 0x18:
		set_sound_timer_to_vx(&chip_8.sound_timer, chip_8.v_registers[:], x)
	case 0x1E:
		set_i_to_i_plus_vx(chip_8.v_registers[:], &chip_8.i, x)
	case 0x29:
		chip_8.i = FONT_START_ADDR + u16(chip_8.v_registers[x]) * 5
	case 0x33:
		store_bcd_of_vx_in_memory(chip_8.memory[:], chip_8.v_registers[:], chip_8.i, x)
	case 0x55:
		store_v0_to_vx_in_memory(chip_8.memory[:], chip_8.v_registers[:], chip_8.i, x)
	case 0x65:
		read_v0_to_vx_from_memory(chip_8.memory[:], chip_8.v_registers[:], chip_8.i, x)
	}
}


decode_and_execute :: proc(chip_8: ^CHIP_8, instruction: u16)
{
  opcode : u8 = u8((instruction >> 12) & 0xF);
  x      : u8 = u8((instruction >> 8) & 0xF);
  y      : u8 = u8((instruction >> 4) & 0xF);
  n      : u8 = u8(instruction & 0xF);
  nn     : u8 = u8(instruction & 0xFF);
  nnn := instruction & 0xFFF;

  switch opcode 
  {
  case 0x0:
    if nn      == 0xE0 {clear_screen(chip_8.display[:])}
    else if nn == 0xEE {return_from_subroutine(&chip_8.pc, &chip_8.stack)}
    else {}

  case 0x1:
    jump_to_address(&chip_8.pc ,nnn)

  case 0x2:
    call_subroutine_at_address(&chip_8.pc, &chip_8.stack, nnn)

case 0x3, 0x4:
  skip_next_instruction_if_vx(&chip_8.pc, chip_8.v_registers[:], opcode, x, nn)

case 0x5, 0x9:
  skip_next_instruction_if_vx_vy(&chip_8.pc, chip_8.v_registers[:], opcode, x, y)

  case 0x6, 0x7, 0xC:
    set_vx_value(chip_8.v_registers[:], opcode, x, nn)


  case 0x8:
    set_vx_vy(chip_8.v_registers[:], x, y, n)

  case 0xA:
    set_i_register(&chip_8.i, nnn)

  case 0xB:
    jump_with_offset(&chip_8.pc, chip_8.v_registers[:], nnn)

  
  case 0xD:
    display(chip_8, x, y, n)
  case 0xE:
    skip_on_key(&chip_8.pc, chip_8.keys[:], chip_8.v_registers[:], nn, x)
  case 0xF:
    execute_f_instructions(chip_8, x, nn)
  case : 
  }

}


load_rom :: proc(memory: []u8, filepath: string) -> bool
{
    data, err := os.read_entire_file(filepath, context.allocator)
    if err != nil { return false }
    defer delete(data, context.allocator)

    copy(memory[0x200:], data)
    return true
}

main :: proc() 
{
  if len(os.args) < 2
  {
    fmt.println("Missing argument: Please provide the ROM path.")
    return
  }
  else if len(os.args) > 2
  {
    fmt.println("Too many arguments: Only the ROM path should be provided.")
    return
  }
    
  chip_8: CHIP_8
  queue.init(&chip_8.stack)
  copy(chip_8.memory[0x050:], FONTSET[:])
  defer queue.destroy(&chip_8.stack)

  chip_8.pc = 0x200

  if !load_rom(chip_8.memory[:], os.args[1])
  { 
    fmt.println("Failed to load ROM!")
    return
  }

  rl.SetConfigFlags({.WINDOW_RESIZABLE})
  rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "CHIP-8 Emulator")
  rl.SetTargetFPS(60)

  rl.InitAudioDevice()
  defer rl.CloseAudioDevice()

  wave := rl.LoadWaveFromMemory(".wav", raw_data(BEEP_WAV_BYTES), i32(len(BEEP_WAV_BYTES)))
  defer rl.UnloadWave(wave)

  beep_sound := rl.LoadSoundFromWave(wave)
  defer rl.UnloadSound(beep_sound)

  for !rl.WindowShouldClose() 
  {
    input_update(&chip_8)

    for _ in 0..<10
    {
    instruction := fetch(&chip_8)
    decode_and_execute(&chip_8, instruction)
    }

    tick_timers(&chip_8)
    beep(chip_8.sound_timer, beep_sound)

    window_w := f32(rl.GetScreenWidth())
    window_h := f32(rl.GetScreenHeight())

    scale_x := int(window_w / DISPLAY_WIDTH)
    scale_y := int(window_h / DISPLAY_HEIGHT)
    scale := min(scale_x, scale_y)
    if scale < 1 { scale = 1 }

    offset_x := (int(window_w) - (DISPLAY_WIDTH * scale)) / 2
    offset_y := (int(window_h) - (DISPLAY_HEIGHT * scale)) / 2

    rl.BeginDrawing()
    rl.ClearBackground(OFF_COLOR)
   for y in 0..<DISPLAY_HEIGHT
   {
     for x in 0..<DISPLAY_WIDTH 
     {
       index := (y * DISPLAY_WIDTH) + x
       if chip_8.display[index] 
       {
         rx := i32(offset_x + (x * scale))
         ry := i32(offset_y + (y * scale))
         rl.DrawRectangle(rx, ry, i32(scale), i32(scale), ON_COLOR)
       }
     }
   }
  rl.EndDrawing()
  }
  rl.CloseWindow()
}


