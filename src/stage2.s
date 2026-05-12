; Stage 2: VGA image viewer
include 'constants.inc'

use16
org STAGE2_LOAD_ADDRESS

macro VGA_SET_MODE mode {
  mov ah, 0x00
  mov al, mode
  int 0x10
}

VGA_MODE_640x480_16_COLOR = 0x12
VGA_FRAMEBUFFER_SEGMENT = 0xA000
VGA_GRAPHICS_DATA  = 0x03CF
VGA_GRAPHICS_INDEX = 0x03CE
VGA_SEQUENCER_DATA = 0x03C5
VGA_SEQUENCER_INDEX = 0x03C4

start:
  cld ; Clear the direction flag to ensure we copy forward
  VGA_SET_MODE VGA_MODE_640x480_16_COLOR

  call read_rle_mode ; Read the RLE planes status
  call init_attr_palette ; Initialize the VGA palette to a known state
  call load_palette ; Set the VGA palette to match the image palette

  ; Fill ds:si with the start of the image data
  mov ax, IMAGE_LOAD_SEGMENT
  mov ds, ax
  ; Start of the image data (after header and palette)
  mov si, IMAGE_LOAD_OFFSET + IMAGE_MAGIC_SIZE + 1 + 16 * 3

  call setup_vga_direct_write ; Setup VGA registers for direct writes to the framebuffer

  xor bx, bx ; bl = plane index (0-3)
.plane_loop:
  mov dl, bl
  call display_plane ; Display the current plane

  inc bl
  cmp bl, 4 ; We have 4 planes to display
  jb .plane_loop

halt:
  hlt
  jmp halt


read_rle_mode:
  push ax
  push es

  mov ax, IMAGE_LOAD_SEGMENT
  mov es, ax
  mov al, byte [es:IMAGE_LOAD_OFFSET + IMAGE_MAGIC_SIZE] ; Load the image header
  mov [rle_plane_mode], al ; Store the RLE mode for later use

  pop es
  pop ax
ret

init_attr_palette:
  xor bl, bl

  .loop:
  mov bh, bl        ; map entry N -> DAC color N
  mov ax, 0x1000    ; set individual palette register
  int 0x10

  inc bl
  cmp bl, 16
  jb .loop
ret

load_palette:
  ; Set the palette to match the image palette.
  mov ax, IMAGE_LOAD_SEGMENT
  mov es, ax
  mov si, IMAGE_LOAD_OFFSET + IMAGE_MAGIC_SIZE + 1; Start of the palette data
  xor bx, bx ; Start at the first palette entry
  .loop:
  mov dh, byte [es:si] ; Red
  shr dh, 2 ; Convert from 8-bit to 6-bit color (0-63)
  inc si

  mov ch, byte [es:si] ; Green
  shr ch, 2 ; Convert from 8-bit to 6-bit color (0-63)
  inc si

  mov cl, byte [es:si] ; Blue
  shr cl, 2 ; Convert from 8-bit to 6-bit color (0-63)
  inc si

  mov ax, 0x1010 ; BIOS set palette entry function
  int 0x10
  inc bx ; Move to the next palette entry
  cmp bx, 16 ; We have 16 palette entries in mode 0x12
  jb .loop
ret

display_plane:
  ; Display a single plane from the image data.
  ; input:
  ;   dl = plane number (0-3)
  ;   ds:si = pointer to the start of the plane data
  ; stores:
  ;   es:di = pointer to the start of the framebuffer for this plane

  ; Stack allocation indexes:
  push ax
  push bx
  push cx
  push dx
  push bp

  mov bp, sp ; Set BP to the current stack pointer

  PLANE_INDEX_OFFSET = -1 ; Offset for the plane number (dl)
  PLANE_SIZE_OFFSET = -3 ; Offset for the plane size (word)
  STACK_ALLOC_SIZE = 4
  sub sp, STACK_ALLOC_SIZE ; Allocate space on the stack for local variables

  mov byte [bp + PLANE_INDEX_OFFSET], dl ; Store the plane number on the stack

  ; read the plane size
  lodsw ; ax = [ds:si], si += 2
  mov word [bp + PLANE_SIZE_OFFSET], ax ; Store the plane size on the stack

  mov dx, VGA_FRAMEBUFFER_SEGMENT
  mov es, dx
  xor di, di

  ; Check if RLE is enabled for this plane
  mov bh, [cs:rle_plane_mode]
  mov bl, 1 ; Get the plane index
  mov cl, byte [bp + PLANE_INDEX_OFFSET]
  shl bl, cl ; bl = 1 << plane_index

  ; Set the plane mask to select the current plane
  mov al, bl
  call set_vga_plane_mask

  mov cx, word [bp + PLANE_SIZE_OFFSET] ; Get the plane size
  test bh, bl ; Check if RLE is enabled for this plane.
  jz .display_uncompressed
  ; RLE is enabled for this plane, we need to decode it
  ; [COUNT][BYTE] pairs
  ; Copy the decoded data to the framebuffer
.display_rle:
  cmp cx, 0
  je .done

  cmp si, 0xF000
  jb .rle_read_count
  call normalize_ds_si

.rle_read_count:
  lodsb ; Load the count byte into al
  dec cx
  mov bl, al
.rle_read_value:
  lodsb
  dec cx
.rle_write_loop:
  ; Write 'count' bytes of 'value' to the framebuffer
  stosb ; Store byte from al to [es:di] and
  dec bl
  jnz .rle_write_loop ; If count is not zero, write the next byte
  jmp .display_rle
.display_uncompressed:
  ; Copy the plane data to the framebuffer
  cmp cx, 0
  je .done
  movsb ; Copy byte from [ds:si] to [es:di]
  dec cx

  cmp si, 0xF000; Align every 24575 bytes
  jb .display_uncompressed
  ; Normalize DS:SI to avoid crossing segment boundaries
  call normalize_ds_si
  jmp .display_uncompressed


.done:
  add sp, STACK_ALLOC_SIZE ; Clean up the stack

  pop bp
  pop dx
  pop cx
  pop bx
  pop ax
ret

set_vga_plane_mask:
 ; input: AL = map
 push ax
 push dx

 mov ah, al

 mov dx, VGA_SEQUENCER_INDEX
 mov al, 0x02
 out dx, al

 inc dx
 mov al, ah
 out dx, al

 pop dx
 pop ax
ret

setup_vga_direct_write:
  push ax
  push dx

  ; Graphics Controller: Set/Reset = 0
  mov dx, VGA_GRAPHICS_INDEX
  mov al, 0x00
  out dx, al
  inc dx
  xor al, al
  out dx, al

  ; Graphics Controller: Read Map Select = 0
  mov dx, VGA_GRAPHICS_INDEX
  mov al, 0x04
  out dx, al
  inc dx
  xor al, al
  out dx, al

  pop dx
  pop ax
ret

normalize_ds_si:
  push ax
  push bx

  mov bx, si
  shr bx, 4 ; Get the segment (si / 16)
  mov ax, ds
  add ax, bx
  mov ds, ax
  and si, 0x0F ; Get the offset (si % 16)

  pop bx
  pop ax
ret

rle_plane_mode: db 0; RLE enabled per plane (bit 0 = plane 0, bit 1 = plane 1, etc.)

; Pad to closest 512-byte sector boundary
DATA_SIZE = ($ - $$)
CLOSEST_SECTOR_SIZE = ((DATA_SIZE + 511) / 512) * 512

; Fill the remaining space with zeros
times (CLOSEST_SECTOR_SIZE - DATA_SIZE) db 0
