layout asm

target remote localhost:1234

break *0x7C00
continue
break *0x7E00
break *0x7e22
break *0x7e2c
break *0x7e42
break *0x7e4e
break *0x7e74
break *0x7e7f

