
; Address map for the bootloader
STAGE1_LOAD_ADDRESS = 0x0000_7C00 ; Address to load stage1
STAGE2_LOAD_ADDRESS = 0x0000_8000 ; Address to load stage2
IMAGE_LOAD_ADDRESS =  0x0001_0000 ; Address to load the image

; Image load segment and offset for stage2
IMAGE_LOAD_SEGMENT = (IMAGE_LOAD_ADDRESS shr 4)
IMAGE_LOAD_OFFSET  = IMAGE_LOAD_ADDRESS and 0xF
