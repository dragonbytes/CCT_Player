*********************************************************************************
* Coco ChipTunes Player for OS-9 v1.6
* Written by Todd Wallace (LordDragon)
*
* I had tons of help with this, so thanks everyone on discord for answering 
* my constant questions and being patient with me. In no particular order:
*
* L. Curtis Boyle, William Astle, Deek, Dave Philipsen, and my assembly 
* language mentor, Simon Jonassen.
* 
* Special thanks to Ed Snider for providing me with the details of his CCT file
* format and the technique he uses to turn off the various registers of OPL chip
* when playback is done. If you don't do that, some songs end in a wonky way LOL.
*********************************************************************************

; Definitions/equates 
mpi_reg           	EQU   $FF7F
ymf_status        	EQU   ymf_rsel_0
ymf_rsel_0        	EQU   $FF50
ymf_data_0        	EQU   $FF51
ymf_rsel_1        	EQU   $FF52
ymf_data_1        	EQU   $FF53
ymf_reset         	EQU   $FF54

mmmpi_extended_reg	EQU 	$FF42

; CoCoPSG Definitions and Equates
psg_mem_bank_0 		EQU 	$FF5A 
psg_mem_bank_1  		EQU 	$FF5B 
psg_control_reg 		EQU 	$FF5D 
psg_ym_reg_select 	EQU 	$FF5E
psg_ym_data_port 		EQU 	$FF5F

; Game Master Cartridge Definitions and Equates
gmc_register 		EQU  	$FF41 

cct_block_count   	EQU   vgmDataBuffer+30
vgm_block_end     	EQU   $4000
vgm_block_start   	EQU   $2000

cr_lf  			EQU  	$0D0A

STDIN 			EQU   0
STDOUT            	EQU   1
H6309    			set   1

	include 	os9.d
	include 	rbf.d
	include 	scf.d 
	pragma 	cescapes

; Module header setup info 
	MOD 	MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
**************************************************************************************
; -----------------------------------------------------
; Variables 
		org 	0

uRegImage         RMB   2
prevMPI 		RMB 	1
prevPIA           RMB   1
mpiOPL 		RMB 	1
mpiGMC  		RMB  	1
mpiPSG  		RMB 	1
cpuMode           RMB   1
abortFlag         RMB   1
oplDetectFlag 	RMB  	1
playlistFlag 	RMB 	1
reservedMMUflag 	RMB  	1
mpiExtFeatures 	RMB 	1
cmdlinePtr  	RMB  	2

vgmBufferEndPtr   RMB   2
vgmBlockCount     RMB   1
vgmBlockMapPtr    RMB   2
blockCounter      RMB   1
vgmChipType       RMB   1
vgmClockCounter 	RMB 	1
psgClock	  	RMB  	1

songFilePath      RMB   1
playlistFilePath  RMB   1
playlistTotal     RMB   1
playlistCurTrack  RMB   1
playlistPtr 	RMB 	2
playlistByteTotal RMB 	2
filenamePtr       RMB   2
tempPath  		RMB 	1

u32Value          RMB   4
u16Value          RMB   2
u8Value           RMB   1
strNumeric        RMB   16

strCCTdeviceName  RMB   17
strCCTauthorName  RMB   25
strCCTtitleName   RMB   25

; vgm format variables 
vgmVersion        RMB   2
vgmDataOffset     RMB   4
vgmGD3start       RMB   4
vgmBytesLeft      RMB   4
vgmLoopOffset     RMB   4
vgmLoopCount      RMB   1
vgmLoopBlockPtr   RMB   2
vgmLoopStart      RMB   2
vgmLoopParam      RMB   1
vgmLoopSamples    RMB   4
vgmCurrentClock 	RMB 	4

vgmBlockMap       RMB   256
vgmDataBuffer     RMB   256
vgmTotalSamples   RMB   4
vgmSongLengthMins RMB   1
vgmSongLengthSecs RMB   1

; gd3 tag variables 
gd3TagFlag        RMB   1
gd3TagSize        RMB   4
gd3TagTrackName   RMB   32
gd3TagGameName    RMB   32
gd3TagSystemName  RMB   32
gd3TagAuthorName  RMB   32
gd3TagReleaseDate RMB   16
gd3TagMadeByName  RMB   32
gd3TagNotes       RMB   32

stringBuffer  	RMB 	32

playlistBuffer    RMB   1024 
playlist_buffer_sz EQU 	.-playlistBuffer

; End of Variables
; -----------------------------------------------------
data_size         EQU   .

; -----------------------------------------------------
; Constants
moduleName              FCS 	"cctplay"
strProgInfo             FCN   "\r\nCoCo ChipTunes Player v1.6\r\nWritten By Todd Wallace (LordDragon)\r\n\n"
strThanksMsg            FCN   "\r\nSpecial thanks to Ed Snider, L. Curtis Boyle, William Astle, Deek,\r\nand everyone else on Discord for all your help.\r\n"

; Error messages 
strErrorFile            FCN 	"Error: File not found. Exiting.\r\n"
strErrorRam             FCN   "\r\nError: Not enough free RAM for that file. Aborted.\r\n"
strErrorRead            FCN   "\r\nError accessing the file. Aborted.\r\n"
strErrorParams          FCN   "Error: Invalid parameter. Type \x22cctplay\x22 for usage/syntax information.\r\n"
strErrorSuddenEnd       FCN   "\r\nError: Song data ended unexpectedly. Incomplete file? Exiting.\r\n"
strErrorUnknown         FCN   "\r\nError: Something weird has happened, probably a bug. Sorry about that. Aborting.\r\n"
strErrorNoFilename      FCN   "Error: No filename specified. Type \x22cctplay\x22 for usage/syntax information.\r\n"
strErrorFileInvalid     FCN   "Error: Unrecognized file format. File must be a VGM, CCT, or M3U playlist.\r\n"
strErrorVGMchips        FCN   "Error: This VGM file requires an unsupported sound chip. Skipped.\r\n"
strErrorOPLmissing      FCN   "\r\n\nError: OPL sound chip could not be detected. Do you have a MEGA-mini MPI?\r\nAborted.\r\n"
strErrorPlaylistFull 	FCN 	"Error: Playlist is too large. It must be under 1 KB in size. Aborted.\r\n"

; VGM format error msgs 
strGD3none              FCN   "No GD3 tag information found.\r\n"
strVGMinvalidVer        FCN   "Unsupported VGM file version or file is corrupt.\r\n"

strLoading              FCN   "\x03\rLoading... "
strPlsEntriesMsg1       FCN   "Playlist has "
strPlsEntriesMsg2       FCN   " entries.\r\n"
strLoadingPLS           FCN   "\x03\rLoading track "
strOf                   FCN   " of "
strDots                 FCN   "... "

; song length strings 
strSongLengthMsg        FCN   "\r\nSong Length:  "
strSongLengthMins       FCN   " Minutes "
strSongLengthSecs       FCN   " Seconds\r\n"

;strAudioOutput          FCN   "Audio Output:    "
;strAudioExternal        FCN   "MMMPI audio jack only.\r\n"
;strAudioCart            FCN   "Both MMMPI jack and internal CoCo audio.\r\n"

strChipType  		FCN 	"\r\nChip Type:    "
strAY8910  			FCN  	"AY-3-8910"
strYM2149  			FCN 	"YM2149"
strSN76489  		FCN  	"SN76489"
strOPL2  			FCN  	"YM3812 (OPL2)"
strOPL3   			FCN  	"YMF262 (OPL3)"

strOutputDevice  		FCN 	"\r\nCoCo Device:  "
strMMMPI  			FCN  	"MEGA-mini MPI\r\n"
strCocoPSG  		FCN 	"CocoPSG"
strGMC  			FCN 	"Game Master Cartridge @ 4 MHz"
strOutputSlot 		FCN  	" (MPI Slot ?)\r\n"
strVGMclock  		FCN 	"VGM Clock:    "
strHz  			FCN  	" Hz\r\n"
strCocoPSG1mhz 		FCN 	" @ 1 MHz"
strCocoPSG2mhz  		FCN 	" @ 2 MHz"

strCCTdeviceMsg         FCN   "CCT File Info: "
strCCTauthorMsg         FCN   "\r\nAuthor:        "
strCCTtitleMsg          FCN   "\r\nTitle:         "

strPlayingFrozen        FCN   "\r\nPlaying... (OS-9 will be frozen during playback. Press BREAK to stop)"
strPlayComplete         FCN   "\x03\rPlayback complete!\r\n"
strPlayAborted          FCN   "\x03\rPlayback aborted.\r\n"

strUsageMsg            	FCC   "Syntax: cctplay [-i] [-psg <slot>] [-gmc <slot>] [-l <0-9 | 'f'>] <filename>\r\n\n"
            		FCC 	"    -i = Display information about supported formats, soundchips, and hardware.\r\n"
            		FCC   "    -l = Set number of times to play looped section for VGMs that use one.\r\n"
				FCC 	"         Valid values are 0 through 9, or 'F' to loop forever. (Default is 1)\r\n"
				FCC 	"  -gmc = Specify an MPI slot for the Game Master Cartridge. (Default is Slot 1)\r\n"
				FCC 	"  -psg = Specify an MPI slot for the CocoPSG. (Default is Slot 2)\r\n\n"
				FCC 	" (Specifying an MPI slot for each device allows you to have them both connected\r\n"
				FCC  	"  at the same time and in the slots you choose. This lets you to do things like\r\n"
				FCC 	"  creating a playlist that mixes music for different supported soundchips. The\r\n"
				FCC 	"  player will then automatically route each track to the appropriate device!)\r\n"
strUsageMsgSz 		EQU 	*-strUsageMsg

strFileTypeInfo  		FCB 	$0C
				FCC   "CoCo ChipTunes Player 1.6 supports the .VGM, .CCT, and .M3U file formats.\r\n\n"
		  		FCC 	"The VGM file format covers a wide range of soundchips, but only a few of them\r\n"
		  		FCC 	"are supported using existing CoCo addons. These include:\r\n\n"
		  		FCC 	"   - YM3812/YMF262 (MEGA-mini MPI)\r\n"
		  		FCC 	"   - YM2149/AY-3-8910 (CocoPSG @ 1 or 2 MHz)\r\n"
		  		FCC 	"   - SN76489 (Game Master Cartridge @ 4 MHz)\r\n\n"
		  		FCC 	"CCT files are CoCo-specific chiptunes designed for Ed Snider's own custom Coco\r\n"
		  		FCC 	"ChipTunes Player for use with his MEGA-mini MPI and CocoPSG hardware.\r\n\n"
		  		FCC  	"M3U is a common playlist format supported by many other players/tools and unlike"
		  		FCC 	"previous versions of my player, these playlists are automatically detected and\r\n"
		  		FCC 	"no command-line flags are needed to play one. To manually create one with a text"
		  		FCC  	"editor, simply start with the header #EXTM3U followed by a carriage-return.\r\n"
		  		FCC 	"Then add the pathname or filename for each entry you want to add with a\r\n"
		  		FCC 	"carriage-return at the end of each line. That's it!\r\n\n"
		  		FCC 	"NOTE ON CLOCK SPEEDS: VGM files are often created for hardware with slightly\r\n"
		  		FCC 	"different clock speeds than our CoCo accessories. Notes may sound a bit off-key\r\n"
		  		FCC 	"or play a bit faster or slower than normal. There are various tools online that\r\n"
		  		FCC 	"can attempt to convert these files to match your own hardware's clock speed.\r\n"
strFileTypeInfoSz 	EQU 	*-strFileTypeInfo

strNewLine              FCN   "\r\n"

strPlaylist  		FCC 	"#EXTM3U\r"
strPlaylistSz  		EQU 	*-strPlaylist

sustainRelease          FCB   $80,$83,$81,$84,$82,$85,$88,$8B,$89,$8C,$8A,$8D,$90,$93,$91,$94,$92,$95

; vgm format constants 
vgmDataOffsetConst      FDB   $0000,$0034       ; VGM data offset
vgmBlockSizeConst       FDB   $0000,$2000       ; 8k block size 
vgmSamplesPerSec        FDB   $0000,44100       ; 32 bit value of samples per second for all vgm files 
vgmLoopHeaderConst      FDB   $0000,$001C       ; this is for looped files and is location of relative offset 
                                                ; for where future loop playback starts 

; gd3 tag constants and strings 
gd3TagWordConst         FDB   $0000,$0002
gd3TagOffsetConst       FDB   $0000,$0014

gd3TagTrackLabel        FCN   "Title Name:   "
gd3TagGameLabel         FCN   "Game Name:    "
gd3TagSystemLabel       FCN   "System:       "
gd3TagAuthorLabel       FCN   "Author:       "
gd3TagDateLabel         FCN   "Released:     "
gd3TagMadeByLabel       FCN   "VGM made by:  "
gd3TagNotesLabel        FCN   "Notes:        "

asciiHexList            FCC   "0123456789ABCDEF"
asciiHexPrefix          FCB   '$'

vgmClockMap150andBelow	FCB  	$10,$2C,$30
vgm_clock_map_150_size 	EQU 	*-vgmClockMap150andBelow
			      FCB   $38,$40,$44,$48,$4C,$54,$58,$60,$64,$68,$6C,$70
vgm_clock_map_151_size 	EQU  	*-vgmClockMap150andBelow
          			FCB   $80,$84,$88,$8C,$90,$98,$9C,$A0,$A4,$A8,$AC,$B0,$B4
vgm_clock_map_161_size 	EQU  	*-vgmClockMap150andBelow
          			FCB   $C0,$C4,$C8,$CC,$D0,$D8,$DC,$E0
vgm_clock_map_171_size 	EQU 	*-vgmClockMap150andBelow

psgClockAverage  		FQB 	1500000  		; 1.5 MHz 
psgClock1Const  		FQB  	1000000   		; 1 MHz
psgClock2Const  		FQB 	2000000 		; 2 MHz 
gmcClockConst  		FQB  	4000000   		; 4 MHz

bin32dec1B 			FQB 	1000000000 		; 1 billion decimal 
bin32dec100M 		FQB 	100000000 		; 100 million decimal 
bin32dec10M 		FQB 	10000000 		; 10 million decimal 
bin32dec1M 			FQB 	1000000 		; 1 million decimal 
bin32dec100K 		FQB 	100000 		; 100 thousand decimal 
bin32dec10K 		FQB 	10000 	
; -----------------------------------------------------

START_EXEC
**************************************************************************************
* Program code area 
* RULE #1 - USE U TO REFERENCE ANY CHANGEABLE VARIABLES IN THE DATA AREA.
* RULE #2 - USE PCR TO REFERENCE CONSTANTS SINCE THEY RESIDE WITH EXECUTABLE CODE.
* RULE #3 - NEVER USE JSR FOR CALLING SUBROUTINES. ALWAYS USE BSR OR LBSR INSTEAD.
**************************************************************************************

      stu   <uRegImage        ; save copy of data area pointer in U 
      stx  	<cmdlinePtr 

      ; save state of PIA (coco sound output)
      lda   >$FF23
      sta   <prevPIA          ; save for later restoration 

      ; save initial state of MPI register 
      lda   >mpi_reg
      sta   <prevMPI 
      ; set some MPI defaults for megamini 
      ora  	#%00001111  	; mega mini MPI extended features register slot
      sta 	<mpiExtFeatures
      anda 	#%11110000
      ora   #%00000100  	; YMF262 OPL sound chip slot value  
      sta   <mpiOPL 	

      ; init some variables
      clra  
      sta  	<abortFlag
      sta   <playlistCurTrack
      sta  	<oplDetectFlag
      sta 	<playlistFlag
      sta  	<mpiGMC   		; default for GMC cart in slot 1 (0)
      sta 	<psgClock 		; default psg clock setting to 2 MHz
      lda  	#1
      sta 	<mpiPSG  		; default for cocoPSG cart in slot 2 (1)
      lda   #$FF
      sta   <playlistFilePath
      sta   <songFilePath

      ; find out what CPU is being used, and if 6309, what execution mode 
      lbsr  TSTNM
      sta   <cpuMode

      ; set default 1 loop for VGMs that loop 
      lda   #1
      sta   vgmLoopParam,U 

      ; try and detect presence of OPL chip (and therefore presence of mega-mini mpi)
      ; NOTE: THIS SEEMS TO BE GLITCHY SOMETIMES
      lbsr  DETECT_OPL_CHIP
      bcs  	INIT_OPL_NOT_FOUND
      inc  	<oplDetectFlag
INIT_OPL_NOT_FOUND
      ; display program info 
      leax  strProgInfo,PCR 
      lbsr  PRINT_STR_OS9
      ; setup the intercept stuff 
      leax  SIGNAL_HANDLER,PCR
      os9   F$Icpt

      ; look for parameters. first restore pointer to command line arguments
      ldx 	<cmdlinePtr
      lda   ,X 
      cmpa  #$0D              ; check if user just wants to see usage info
      lbeq  USAGE_HELP_EXIT    
PARAMS_CHECK_NEXT
      lbsr  SEARCH_PARAMETER_FLAG
      lbcs  PARAMS_NO_MORE
      ; found a parameter of some sort. what is it? 
      lda   ,X 
      lbsr  CONVERT_UPPERCASE
  	cmpa 	#'I'
  	bne  	PARAMS_CHECK_FOR_LOOP
  	lda 	1,X 
  	cmpa 	#C$CR 
  	lbeq 	FILETYPE_HELP_INFO
  	cmpa 	#C$SPAC 
  	lbeq 	FILETYPE_HELP_INFO
  	lbra 	PARAM_ERROR_EXIT

PARAMS_CHECK_FOR_LOOP
      cmpa  #'L'
      bne 	PARAMS_CHECK_SLOTS
      ; if here, user wants to specify how to handle looped vgms 
      leax  1,X 
      lbsr  SEARCH_NEXT_NONSPACE
      lda   ,X+ 
      cmpa  #$0D 
      lbeq  PARAM_ERROR_EXIT
      lbsr  CONVERT_UPPERCASE
      cmpa  #'F'
      beq   PARAMS_LOOP_FOREVER
      ; if here, user specified a number of loops 
      suba  #$30        ; convert ASCII to value
      sta   vgmLoopParam,U 
      lbra  PARAMS_CHECK_NEXT 

PARAMS_LOOP_FOREVER
      ora   #$80        ; set bit 7 to let player know to play indefinetly
      sta   vgmLoopParam,U 
      lbra  PARAMS_CHECK_NEXT

PARAMS_CHECK_SLOTS
 	ldd  	,X
      lbsr 	CONVERT_UPPERCASE_WORD
      cmpd 	#"PS"
      bne  	PARAMS_CHECK_GMC
      ldd 	2,X
      lbsr 	CONVERT_UPPERCASE_WORD
      cmpd  #"G "
      bne 	PARAMS_CHECK_GMC
      ; if here, user wants to set cocopsg slot number  
      leax 	4,X 
      ; make sure slot parameter is properly seperated with a space at the end 
      ldd 	,X++ 
      cmpb 	#C$SPAC 
      lbne 	PARAM_ERROR_EXIT
  	; make sure the next value is between 1 and 4 for each MPI slot
      suba 	#$30  		; convert ascii to value 
      lbeq  PARAM_ERROR_EXIT
      cmpa  #4
      lbhi 	PARAM_ERROR_EXIT
      deca 				; convert 1-4 range to 0-3 range
      sta  	<u8Value 		; temporarily store value
      ; figure out our final MPI slot value for cocoPSG and save it
      lda  	<prevMPI
      anda 	#%11110000
      ora 	<u8Value
      sta 	<mpiPSG
      lbra  PARAMS_CHECK_NEXT

PARAMS_CHECK_GMC
	ldd 	,X 
	lbsr 	CONVERT_UPPERCASE_WORD
	cmpd 	#"GM"
	lbne	PARAM_ERROR_EXIT
	ldd 	2,X 
	lbsr 	CONVERT_UPPERCASE_WORD
	cmpd 	#"C "
	lbne 	PARAM_ERROR_EXIT
	; if here, user wants to set GMC slot number    
      leax 	4,X 
      ; make sure slot parameter is properly seperated with a space at the end 
      ldd 	,X++ 
      cmpb 	#C$SPAC 
      lbne 	PARAM_ERROR_EXIT
  	; make sure the next value is between 1 and 4 for each MPI slot
      suba 	#$30  		; convert ascii to value 
      lbeq  PARAM_ERROR_EXIT
      cmpa  #4
      lbhi 	PARAM_ERROR_EXIT
      deca 				; convert 1-4 range to 0-3 range
      sta  	<u8Value 		; temporarily store value
      ; figure out our final MPI slot value for the GMC and save it
      lda  	<prevMPI
      anda 	#%11110000
      ora 	<u8Value
      sta 	<mpiGMC
      lbra  PARAMS_CHECK_NEXT

PARAMS_NO_MORE
	lda 	,X 
	cmpa 	#C$CR 
	lbeq 	NO_FILENAME_ERROR_EXIT
	stx  	<filenamePtr
	; open the file specified by the user pointed to by X 
      lda   #READ.
      os9   I$Open 
      lbcs  FILE_ERROR_EXIT
      sta   <tempPath
      ; read the first 256 bytes
      leax 	vgmDataBuffer,U 
      ldy 	#256
      os9 	I$Read 
      lbcs 	READ_ERROR_EXIT
      ; now try and detect whether this file is a playlist or song file
      ; look for m3u header string "#EXTM3U" in the first 7 bytes + CR at the end (8 total bytes)
      leay 	strPlaylist,PCR
      ldb 	#strPlaylistSz
PLAYLIST_HEADER_NEXT
      lda  	,X+
      cmpa 	,Y+
      bne 	PLAYLIST_HEADER_NOT_MATCH
      decb 
      bne  	PLAYLIST_HEADER_NEXT
      ; if here, the specified file IS a playlist
      lda  	<tempPath
      sta  	<playlistFilePath

      lbsr  LOAD_PLAYLIST_ENTRIES
      lbcs  UNKNOWN_ERROR_EXIT
      inc  	<playlistFlag

      ; display number of entries  
      leax  strPlsEntriesMsg1,PCR
      lbsr  PRINT_STR_OS9  
      ldb   <playlistTotal
      leax  strNumeric,U 
      lbsr  CONVERT_BYTE_DEC
      lbsr  PRINT_STR_OS9     ; X should already be pointed to start of strNumeric
      leax  strPlsEntriesMsg2,PCR 
      lbsr  PRINT_STR_OS9

      ldx 	<playlistPtr
      bra  	VGM_OPEN_FILE

PLAYLIST_HEADER_NOT_MATCH
 	; copy temp path over to songFIlePath since we already have an actual song open instead of playlist
 	lda 	<tempPath
 	sta  	<songFilePath
 	leax  vgmDataBuffer,U
 	bra  	VGM_HEADER_ALREADY_LOADED

VGM_OPEN_FILE
      stx   <filenamePtr            ; save the filename pointer for later use 
      ; init the map with 0 to show NO blocks are allocated in the beginning 
      clr   vgmBlockMap,U 

	; open a song file pointed to by X and grab the first 256 bytes to get the header 					*****
      lda   #READ.
      os9   I$Open 
      lbcs  FILE_ERROR_EXIT
      sta   <songFilePath
      ; grab header data 
      leax  vgmDataBuffer,U
      ldy   #256
      os9   I$Read
      lbcs  READ_ERROR_EXIT

VGM_HEADER_ALREADY_LOADED
	lbsr 	PRINT_LOADING_MSG
	; next try and detect what kind of file it is. VGM or CCT (or is it a playlist?)     
      ldd   ,X 
      cmpd  #$5667            ; "Vg"
      lbne  CCT_LOADER
      ldd   2,X 
      cmpd  #$6D20            ; "m "
      lbne  CCT_LOADER

VGM_LOADER
      ; if here, seems to be a VGM !
  	; make sure VGM version is compatible 
      ldb   8,X 
      lda   9,X 
      std   <vgmVersion
      leay  vgmDataBuffer,U 

      ; this next section will check for the presence of unsupported chips in the file by
      ; scanning through all the potential clock frequencies supported with each known VGM 
      ; header version. if a value is anything but 0, then it means we found VGM commands 
      ; present for an unsupported soundchip
      cmpd 	#$0150
      bhs  	VGM_LOADER_VERSION_150_AND_ABOVE
      ; if here, the VGM header is old enough that it doesnt support relative data offsets
     	leau  vgmClockMap150andBelow,PCR
     	ldb  	#vgm_clock_map_150_size
     	stb  	<vgmClockCounter
     	clra
VGM_LOADER_VERSION_BELOW_150_NEXT
      ldb   ,U+ 
      leax  D,Y 
      lbsr  CHECK_FOR_32BIT_ZERO
      lbne  VGM_UNSUPPORTED_CHIPS
      dec  	<vgmClockCounter
      bne  	VGM_LOADER_VERSION_BELOW_150_NEXT
      ; if here, there are no unsupported chips found
	ldu 	<uRegImage
	leax  vgmDataBuffer+$0C,U   		; is it for the Game Master Cartridge (SN76489)?
	lbsr 	CHECK_FOR_32BIT_ZERO
	lbeq 	VGM_UNSUPPORTED_CHIPS
      ; if here, VGM is compatible with Game Master Cartridge
      ldd 	#0
      std  	vgmDataOffset,U 
      ldd 	#$0040
      std  	vgmDataOffset+2,U 

      ; copy in the clock frequency for SN76489
	lbsr  GRAB_VGM_CLOCK_VALUE
	lbsr 	PRINT_VGM_CLOCK

      lda  	#'G'
      lbra  VGM_LOADER_CHIP_SUPPORTED

VGM_LOADER_VERSION_150_AND_ABOVE
	; if here, VGM version will defintely have a VGM data relative offset value so grab it
      leax  vgmDataBuffer+$34,U 
      ldd   ,X 
      stb   vgmDataOffset+2,U 
      sta   vgmDataOffset+3,U 
      ldd   2,X 
      stb   vgmDataOffset,U 
      sta   vgmDataOffset+1,U 
      ; now calculate absolute offset by adding $0000 0034 
      leax  vgmDataOffset,U 
      leay  vgmDataOffsetConst,PCR 
      lbsr  ADD_32BIT

      ldd 	2,X 
      std  	<u16Value

      ldd  	<vgmVersion
      cmpd  #$0150
      bhi  	VGM_LOADER_CHECK_ABOVE_VERSION_150
      ldb  	#vgm_clock_map_150_size
      bra  	VGM_LOADER_SEARCH_UNSUPPORTED

VGM_LOADER_CHECK_ABOVE_VERSION_150
	cmpd  #$0160
      bhi  	VGM_LOADER_CHECK_ABOVE_VERSION_160
      ldb  	#vgm_clock_map_151_size
      bra  	VGM_LOADER_SEARCH_UNSUPPORTED

VGM_LOADER_CHECK_ABOVE_VERSION_160
	cmpd  #$0161
      bhi 	VGM_LOADER_CHECK_ABOVE_VERSION_161
      ldb  	#vgm_clock_map_161_size
      bra  	VGM_LOADER_SEARCH_UNSUPPORTED

VGM_LOADER_CHECK_ABOVE_VERSION_161
	cmpd  #$0171
      lbhi  VGM_VERSION_UNSUPPORTED 	; something went wrong since no known version above 0171
      ldb  	#vgm_clock_map_171_size
VGM_LOADER_SEARCH_UNSUPPORTED
	stb  	<vgmClockCounter
	clra 
	leay  vgmDataBuffer,U
	leau  vgmClockMap150andBelow,PCR 
VGM_LOADER_SEARCH_UNSUPPORTED_NEXT
      ldb   ,U+ 
      cmpd  <u16Value
      bhs  	VGM_LOADER_CLOCK_DONE 	; if vgm data area overlaps this part of header, then skip further checks 
      leax  D,Y 
      lbsr  CHECK_FOR_32BIT_ZERO
      lbne  VGM_UNSUPPORTED_CHIPS
      dec  	<vgmClockCounter
      bne  	VGM_LOADER_SEARCH_UNSUPPORTED_NEXT
      ; if here, there are no unsupported chips found
VGM_LOADER_CLOCK_DONE
      ldu   <uRegImage
      ; which chip type are we playing? 
      leax  vgmDataBuffer+$0C,U  
      lbsr  CHECK_FOR_32BIT_ZERO          ; is it for the Game Master Cartridge (SN76489)?
      beq   VGM_LOADER_CHIP_NOT_SN76489
	; copy in the clock frequency for SN76489
	lbsr  GRAB_VGM_CLOCK_VALUE
	; tell user which soundchip we detected and what hardware it will play on
      leax 	strChipType,PCR 
      lbsr 	PRINT_STR_OS9
      leax 	strSN76489,PCR 
      lbsr 	PRINT_STR_OS9
	leax  strOutputDevice,PCR 
	lbsr  PRINT_STR_OS9
	leax  strGMC,PCR 
	lbsr  PRINT_STR_OS9
	lda  	<mpiGMC
	anda 	#%00000011  			; strip off everything but mpi slot value 0-3
	adda 	#$31 					; convert to ASCII + 1 since MPI slots are 1-4
	leax 	strOutputSlot,PCR 
	sta  	11,X 					; WARNING: SELF-MODIFYING CODE. BE CAREFUL
	lbsr 	PRINT_STR_OS9

	lbsr 	PRINT_VGM_CLOCK

      lda   #'G'
      lbra  VGM_LOADER_CHIP_SUPPORTED

VGM_LOADER_CHIP_NOT_SN76489
      ldd   <vgmVersion 
      cmpd  #$0151
      lblo  VGM_VERSION_UNSUPPORTED    
      ; if here, is valid version for the chip but does it contain a clock value for AY8910 or variant?
      leax  vgmDataBuffer+$74,U  
      lbsr  CHECK_FOR_32BIT_ZERO          ; is it a AY8910 or variant of it?
      beq   VGM_LOADER_CHIP_NOT_AY8910_VARIANT    ; nope 
	; ok it is, copy in the clock frequency for AY8910
	lbsr  GRAB_VGM_CLOCK_VALUE
	; assume cocopsg clock of 2mhz to start and set variable accordingly
	clr 	<psgClock  		
	leax 	vgmCurrentClock,U 
	leay  psgClockAverage,PCR 
	lbsr 	COMPARE_32BIT
	bhs 	VGM_LOADER_CHIP_WHICH_AY8910_VARIANT
	; if here, vgm clock is less than 1.5mhz so set cocopsg variable for 1mhz
	lda 	#1
	sta 	<psgClock
VGM_LOADER_CHIP_WHICH_AY8910_VARIANT
      ; which one exactly is it?
      lda  	vgmDataBuffer+$78,U 
      beq  	VGM_LOADER_CHIP_IS_AY8910 		; if $00, it's generic AY8910. play with cocopsg
      cmpa 	#$10 						; if $10, VGM is for YM2149 
      lbne  VGM_UNSUPPORTED_CHIPS
      ; if here, VGM is for YM2149 
      leax 	strChipType,PCR 
      lbsr 	PRINT_STR_OS9
      leax 	strYM2149,PCR 
      lbsr 	PRINT_STR_OS9
      bra  	VGM_LOADER_CHIP_SHOW_DEVICE

VGM_LOADER_CHIP_IS_AY8910
	leax  strChipType,PCR 
	lbsr 	PRINT_STR_OS9
	leax  strAY8910,PCR 
	lbsr  PRINT_STR_OS9
VGM_LOADER_CHIP_SHOW_DEVICE
	leax  strOutputDevice,PCR 
	lbsr  PRINT_STR_OS9
	leax  strCocoPSG,PCR 
	lbsr  PRINT_STR_OS9
	; print to user whether PSG will be using 1 MHz or 2 MHz
	lda 	<psgClock
	beq  	VGM_LOADER_CHIP_PSG_CLOCK_2MHZ
	leax 	strCocoPSG1mhz,PCR
	bra 	VGM_LOADER_CHIP_PSG_PRINT_CLOCK

VGM_LOADER_CHIP_PSG_CLOCK_2MHZ
	leax 	strCocoPSG2mhz,PCR
VGM_LOADER_CHIP_PSG_PRINT_CLOCK
	lbsr 	PRINT_STR_OS9

	lda  	<mpiPSG
	anda 	#%00000011  			; strip off everything but mpi slot value 0-3
	adda 	#$31 					; convert to ASCII + 1 since MPI slots are 1-4
	leax 	strOutputSlot,PCR 
	sta  	11,X 					; WARNING: SELF-MODIFYING CODE. BE CAREFUL
	lbsr 	PRINT_STR_OS9

	lbsr 	PRINT_VGM_CLOCK

      lda  	#'P'
      bra   VGM_LOADER_CHIP_SUPPORTED

VGM_LOADER_CHIP_NOT_COCOPSG_COMPATIBLE
	cmpa 	#$02  				; $02 = AY8913 (same chip inside Tandy Speech and Sound Pak)
	bne  	VGM_LOADER_CHIP_NOT_AY8910_VARIANT
      lda   #'S'                          ; S for Speech/Sound Cart 
      bra   VGM_LOADER_CHIP_SUPPORTED

VGM_LOADER_CHIP_NOT_AY8910_VARIANT
      ; check if its OPL2 or OPL3 
      leax  vgmDataBuffer+$50,U 
      lbsr  CHECK_FOR_32BIT_ZERO
      beq   VGM_LOADER_CHIP_NOT_YM3812    ; if not an OPL2 file
      ; if here, it's an OPL2 data format 
	leax  strChipType,PCR 
	lbsr 	PRINT_STR_OS9
	leax  strOPL2,PCR 
	lbsr  PRINT_STR_OS9
      lda   #2   
      bra   VGM_LOADER_CHIP_CHECK_MMMPI         
 
VGM_LOADER_CHIP_NOT_YM3812
      leax  vgmDataBuffer+$5C,U 
      lbsr  CHECK_FOR_32BIT_ZERO
      beq   VGM_LOADER_CHIP_NOT_YMF262
      ; if here, it's OPL3 data format
	leax  strChipType,PCR 
	lbsr 	PRINT_STR_OS9
	leax  strOPL3,PCR 
	lbsr  PRINT_STR_OS9 
      lda   #1                            ; it's OPL3 (YM262)
      bra   VGM_LOADER_CHIP_CHECK_MMMPI

VGM_LOADER_CHIP_NOT_YMF262
      lbra  VGM_UNSUPPORTED_CHIPS

VGM_LOADER_CHIP_CHECK_MMMPI
      ; before we continue, make sure MMMPI and OPL chip are actually present 
      ldb  	<oplDetectFlag
      lbeq 	VGM_OPL_NOT_PRESENT
      ; if here, there IS an MMMPI present. tell user the output device we are using 
	leax  strOutputDevice,PCR 
	lbsr  PRINT_STR_OS9
	leax  strMMMPI,PCR 
	lbsr  PRINT_STR_OS9 
VGM_LOADER_CHIP_SUPPORTED
      sta   <vgmChipType

      ; init a few vars 
      leax  vgmDataBuffer,U 
      clr   vgmLoopCount,U 

      ; grab total number of samples in song track starting at $18 offset 
      lda   $1B,X 
      ldb   $1A,X 
      std   vgmTotalSamples,U 
      lda   $19,X 
      ldb   $18,X 
      std   vgmTotalSamples+2,U 

      ; grab the relative offset of loop point if any 
      leax  vgmDataBuffer+$1C,U 
      lbsr  CHECK_FOR_32BIT_ZERO
      beq   VGM_LOADER_LOOP_NONE
      lda   3,X 
      ldb   2,X 
      std   vgmLoopOffset,U 
      lda   1,X 
      ldb   ,X 
      std   vgmLoopOffset+2,U 
      ; now do some math to pre-calculate what that offset would be in terms of MMU block and RAM offset 
      lbsr  VGM_CALC_BLOCK_FROM_OFFSET
      ; now grab the total number of samples for loop section 
      lda   7,X 
      ldb   6,X 
      std   vgmLoopSamples,U 
      lda   5,X 
      ldb   4,X 
      std   vgmLoopSamples+2,U 
      ; setup the loop counter based on the CLI param if any, otherwise 
      lda   vgmLoopParam,U 
      sta   vgmLoopCount,U
      beq   VGM_LOADER_LOOP_NONE
      ; now use a loop based on number of playback loops requested (default is 1) to add to total song length calc 
      leax  vgmTotalSamples,U 
      leay  vgmLoopSamples,U 
VGM_LOADER_LOOP_ADD_MORE_SAMPLES
      lbsr  ADD_32BIT
      deca 
      bne   VGM_LOADER_LOOP_ADD_MORE_SAMPLES
VGM_LOADER_LOOP_NONE
      ; now calculate song length taking into account possible extra time from loops
      leax  vgmTotalSamples,U 
      lbsr  CALCULATE_SONG_LENGTH

      ; get GD3 tag offset at $14 in the header 
      leax  vgmDataBuffer+$14,U     
      lbsr  CHECK_FOR_32BIT_ZERO
      lbeq  GD3_TAG_NONE

      ; set the flag to 1 indicating there is a gd3 present 
      lda   #1
      sta   gd3TagFlag,U 

      ; grab the relative offset to GD3 tag (should be same as vgm data end)
      lda   3,X 
      ldb   2,X 
      std   vgmGD3start,U            ; also marks end of vgm song data 
      lda   1,X 
      ldb   ,X 
      std   vgmGD3start+2,U        

      ; add gd3 offset constant of $0000 0014 to get absolute offset  
      leax  vgmGD3start,U 
      leay  gd3TagOffsetConst,PCR      
      lbsr  ADD_32BIT

      ; seek to that location 
      ldx   <vgmGD3start 
      ldu   <vgmGD3start+2 
      lda   <songFilePath
      os9   I$Seek
      lbcs  READ_ERROR_EXIT
      ldu   <uRegImage

      lbsr  EXTRACT_GD3_TAG_INFO
      lbcs  UNKNOWN_ERROR_EXIT

      ; calculate vgm data area size from gd3 tag offset info 
      ldd   vgmGD3start,U 
      std   vgmBytesLeft,U 
      ldd   vgmGD3start+2,U 
      std   vgmBytesLeft+2,U 
      leax  vgmBytesLeft,U 
      leay  vgmDataOffset,U 
      lbsr  SUBTRACT_32BIT
      bra   VGM_LOADER_GET_BLOCKS

GD3_TAG_NONE
      clr   gd3TagFlag,U      ; clear flag to indicate no gd3 found 
      ; get filesize info to use in calculating vgm data length since theres 
      ; no GD3 tag to use as reference 
      lda   <songFilePath
      ldb   #$02        ; 2 for ss.siz get stat coommand 
      os9   I$GetStt
      lbcs  READ_ERROR_EXIT
 
      stx   <vgmBytesLeft 
      stu   <vgmBytesLeft+2 
      ldu   <uRegImage
      leax  vgmBytesLeft,U 
      leay  vgmDataOffset,U
      lbsr  SUBTRACT_32BIT

VGM_LOADER_GET_BLOCKS
      ; first seek file pointer to start of VGM raw command data
      lda   <songFilePath
      ldx   <vgmDataOffset 
      ldu   <vgmDataOffset+2 
      os9   I$Seek
      lbcs  READ_ERROR_EXIT
      ldu   <uRegImage

      leax  vgmBlockMap,U
      stx   <vgmBlockMapPtr
VGM_LOADER_NEXT_BLOCK 
      ldu   <uRegImage
      leax  vgmBytesLeft,U 
      leay  vgmBlockSizeConst,PCR 
      lbsr  SUBTRACT_32BIT
      bcs   VGM_LOADER_LAST_BLOCK
      beq   VGM_LOADER_LAST_BLOCK

      ldx   <vgmBlockMapPtr
      ldb   #1          ; request 1 8k block 
      os9   F$AllRAM
      lbcs  RAM_ERROR_EXIT
      stb   ,X+         ; store the block number in the list 
      stx   <vgmBlockMapPtr   ; update pointer 
      clra 
      tfr   D,X 
      ldb   #1
      os9   F$MapBlk
      lbcs  UNKNOWN_ERROR_EXIT
      ; check to see if OS9 assigned us $E000-$FFFF and if so, request another since all 8k cannot be used
      cmpu 	#$E000 
      bne 	VGM_LOADER_NOT_E000
      ; it WAS $E000 so request another WHILE E000 IS STILL MAPPED so that it wont just give it to us again
      ldb   #1
      stb  	<reservedMMUflag
      os9   F$MapBlk
      lbcs  UNKNOWN_ERROR_EXIT     
VGM_LOADER_NOT_E000
      tfr   U,X
      ; read an 8k block in to the newly mapped block 
      lda   <songFilePath 
      ldy   #$2000            ; read 8k
      os9   I$Read
      lbcs  READ_ERROR_EXIT
      lbrn  VGM_LOADER_NEXT_BLOCK   ; wait 5 cycles 
      ; now unmap the block from user space 
      ; U should already be still pointing to MMU mapped space from F$MapBlk
      ldb   #1
      os9   F$ClrBlk  
      lbcs  UNKNOWN_ERROR_EXIT

      ; (eventually put an EOF check here )
      ; check for EOF 
      lda   <songFilePath
      ldb   #$06        ; EOF test function code 
      os9   I$GetStt
      bcc   VGM_LOADER_NEXT_BLOCK
      bra   VGM_LOADER_DONE

VGM_LOADER_LAST_BLOCK
      lbsr  ADD_32BIT         ; since we rolled over, add to get back remainder 

      ; allocate, save, and deallocate last block 
      ldx   <vgmBlockMapPtr
      ldb   #1          ; request 1 8k block 
      os9   F$AllRAM
      lbcs  RAM_ERROR_EXIT
      stb   ,X+         ; store the block number in the list 
      stx   <vgmBlockMapPtr   ; update pointer 
      ldy   vgmBytesLeft+2,U        ; get last word of remainder since <= 8k 
      clra 
      tfr   D,X 
      ldb   #1
      os9   F$MapBlk
      lbcs  UNKNOWN_ERROR_EXIT
      tfr   U,X 
      lda   <songFilePath 
      os9   I$Read
      lbcs  READ_ERROR_EXIT
      lbrn  VGM_LOADER_NEXT_BLOCK   ; wait 5 cycles 

      ; U should already be still pointing to MMU mapped space from F$MapBlk
      ldb   #1
      os9   F$ClrBlk  
      lbcs  UNKNOWN_ERROR_EXIT

      ; check if we had to reserve the $E000-$FFFF area of ram so F$MapBlk wouldnt give it to us, and
      ; deallocate it now if we did 
      ldb 	<reservedMMUflag
      beq 	VGM_LOADER_DONE 		; nope, just skip passed deallocation of it
      ldb  	#1 
      ldu 	#$E000 
      os9   F$ClrBlk  
      lbcs  UNKNOWN_ERROR_EXIT
      clr  	<reservedMMUflag

VGM_LOADER_DONE
      ldu   <uRegImage
      ; mark the end of map with a NULL 
      ldx   <vgmBlockMapPtr
      clr   ,X

      ; close the song file path since we are done with it now
      lda  	<songFilePath
      os9  	I$Close 
      lbrn  VGM_LOADER_DONE

      lbsr  GD3_PRINT_TAG           ; print out the tag info to screen 

      leax  strSongLengthMsg,PCR 
      lbsr  PRINT_STR_OS9
      ; convert/print minutes value 
      ldb   vgmSongLengthMins,U 
      leax  strNumeric,U
      lbsr  CONVERT_BYTE_DEC
      lbsr  PRINT_STR_OS9
      leax  strSongLengthMins,PCR 
      lbsr  PRINT_STR_OS9
      ; convert/print minutes value 
      ldb   vgmSongLengthSecs,U 
      leax  strNumeric,U
      lbsr  CONVERT_BYTE_DEC
      lbsr  PRINT_STR_OS9
      leax  strSongLengthSecs,PCR 
      lbsr  PRINT_STR_OS9

      lbra  PLAY_VGM_DATA

VGM_VERSION_UNSUPPORTED
      leax  strVGMinvalidVer,PCR
      bra   VGM_ERROR_PRINT_RESULT

VGM_UNSUPPORTED_CHIPS
      leax  strErrorVGMchips,PCR
      bra   VGM_ERROR_PRINT_RESULT

VGM_OPL_NOT_PRESENT 
      leax  strErrorOPLmissing,PCR 
      bra   VGM_ERROR_PRINT_RESULT

VGM_ERROR_PRINT_RESULT
      ldu   <uRegImage
      lbsr  PRINT_STR_OS9
      lbra  EXIT_CLOSE_ALL_PATHS

; -------- CCT format file loader --------
CCT_LOADER
	; point to header area to extract device settings and file info
      leax  vgmDataBuffer,U
      ; byte 34 is chip type - $01=OPL3, $02=OPL2, $03=YM2149/AY
      ldb   34,X
      lbeq  INVALID_FILE_ERROR_EXIT
      cmpb  #$03
      lbhi  INVALID_FILE_ERROR_EXIT
      blo  	CCT_LOADER_SAVE_CHIPTYPE 	; since its not file for cocoPSG, skip checking clock speed
      ; if here, the number was $03 meaning its for cocopsg
      clr 	<psgClock 		; set default for 2 mhz unless we find out otherwise
      lda 	35,X 
      bne 	CCT_LOADER_SAVE_CHIPTYPE  	; clock speed for psg is correct so skip ahead 
      ; CCT is for PSG @ 1MHZ so modify the variable to set it
      lda  	#1
      sta  	<psgClock
      bra  	CCT_LOADER_SAVE_CHIPTYPE

CCT_LOADER_CHECK_FOR_MMMPI
	lda  	<oplDetectFlag
	beq 	VGM_OPL_NOT_PRESENT
CCT_LOADER_SAVE_CHIPTYPE
      stb   <vgmChipType
   
      ; grab total 8k block count at offset 30 bytes
      ldb   30,X
      stb   <vgmBlockCount  

      ; grab the device name from header 
      leay  strCCTdeviceName,U 
      ldb   #16         ; 16 chars in the device description
CCT_LOADER_DEVICE_NAME_NEXT_SPACE
      lda   ,X+
      lbsr  CONVERT_COCO_ASCII
      cmpa  #$20        ; remove leading space-padding
      bne   CCT_LOADER_DEVICE_NAME_STORE
      decb
      bne   CCT_LOADER_DEVICE_NAME_NEXT_SPACE
      bra   CCT_LOADER_DEVICE_NAME_EMPTY

CCT_LOADER_DEVICE_NAME_NEXT
      lda   ,X+
      lbsr  CONVERT_COCO_ASCII
CCT_LOADER_DEVICE_NAME_STORE
      sta   ,Y+
      decb 
      bne   CCT_LOADER_DEVICE_NAME_NEXT
CCT_LOADER_DEVICE_NAME_EMPTY
      clr   ,Y          ; null terminator

      ; convert title text coco ascii to normal 
      leax  vgmDataBuffer+100,U     ; 100 byte offset is song name 
      leay  strCCTtitleName,U
      ldb   #24
CCT_LOADER_TITLE_NAME_NEXT
      lda   ,X+
      lbsr   CONVERT_COCO_ASCII
      sta   ,Y+
      decb 
      bne    CCT_LOADER_TITLE_NAME_NEXT
      ; strip trailing spaces 
      ldb   #24   ; protect against an ALL-SPACE string 
CCT_LOADER_TITLE_NAME_STRIP_SPACE
      lda   ,-Y 
      cmpa  #$20
      bne   CCT_LOADER_TITLE_NAME_DONE
      decb 
      bne   CCT_LOADER_TITLE_NAME_STRIP_SPACE
CCT_LOADER_TITLE_NAME_DONE
      clr   1,Y          ; null terminator

      ; ; convert author text coco ascii to normal and remove trailing spaces  
      leay  strCCTauthorName,U
      ldb   #24
CCT_LOADER_AUTHOR_NAME_NEXT
      lda   ,X+
      lbsr  CONVERT_COCO_ASCII
      sta   ,Y+
      decb 
      bne   CCT_LOADER_AUTHOR_NAME_NEXT
      ; remove trailing spaces 
      ldb   #24
CCT_LOADER_AUTHOR_NAME_STRIP_SPACE
      lda   ,-Y 
      cmpa  #$20
      bne   CCT_LOADER_AUTHOR_NAME_DONE
      decb              ; protect against an ALL-SPACES string 
      bne   CCT_LOADER_AUTHOR_NAME_STRIP_SPACE
CCT_LOADER_AUTHOR_NAME_DONE
      clr   1,Y          ; null terminator

      ; seek file pointer to start of VGM data inside CCT file 
      lda   <songFilePath
      ldx   #0
      ldu   #6656
      os9   I$Seek 
      lbcs  READ_ERROR_EXIT
      ldu   <uRegImage              ; restore original value 

      ; initialize pointers and counters for read loop 
      ldb   <vgmBlockCount
      stb   <blockCounter
      leax  vgmBlockMap,U
      stx   <vgmBlockMapPtr

CCT_LOADER_REQUEST_NEXT_BLOCK    
      ldx   <vgmBlockMapPtr
      ldb   #1          ; request 1 8k block 
      os9   F$AllRAM
      lbcs  RAM_ERROR_EXIT
      stb   ,X+         ; store the block number in the list 
      stx   <vgmBlockMapPtr   ; update pointer 
      clra 
      tfr   D,X 
      ldb   #1
      os9   F$MapBlk
      lbcs  UNKNOWN_ERROR_EXIT
      ; check to see if OS9 assigned us $E000-$FFFF and if so, request another since all 8k cannot be used
      cmpu 	#$E000 
      bne 	CCT_LOADER_NOT_E000
      ; it WAS $E000 so request another WHILE E000 IS STILL MAPPED so that it wont just give it to us again
      ldb   #1
      stb  	<reservedMMUflag
      os9   F$MapBlk
      lbcs  UNKNOWN_ERROR_EXIT     
CCT_LOADER_NOT_E000
	tfr   U,X 
      ; read an 8k block in to the newly mapped block 
      lda   <songFilePath 
      ldy   #$2000            ; read 8k
      os9   I$Read
      lbcs  READ_ERROR_EXIT
      ; now unmap the block from user space 
      ; U should already be still pointing to MMU mapped space from F$MapBlk
      ldb   #1
      os9   F$ClrBlk  
      lbcs  UNKNOWN_ERROR_EXIT
      cmpy  #$2000            ; check if we read a full block or if we are at end
      bne   CCT_LOADER_READ_FILE_EOF
      ; decrement block counter and loop back if there are more to do 
      dec   <blockCounter 
      bne   CCT_LOADER_REQUEST_NEXT_BLOCK
CCT_LOADER_READ_FILE_EOF
      ; check if we had to reserve the $E000-$FFFF area of ram so F$MapBlk wouldnt give it to us, and
      ; deallocate it now if we did 
      ldb 	<reservedMMUflag
      lbeq 	CCT_LOADER_SKIP_DEALLOCATE_RESERVED 	; nope, just skip passed deallocation of it
      ldb  	#1 
      ldu 	#$E000 
      os9   F$ClrBlk  
      lbcs  UNKNOWN_ERROR_EXIT
      clr  	<reservedMMUflag

CCT_LOADER_SKIP_DEALLOCATE_RESERVED
      ; mark the end of map with a NULL 
      ldx   <vgmBlockMapPtr
      clr   ,X
      ldu   <uRegImage

      ; close the song file path since we are done with it now
      lda  	<songFilePath
      os9  	I$Close 
      lbrn  VGM_LOADER_DONE

      lbsr  PRINT_NEWLINE_OS9

      ; display title/author info 
      leax  strCCTdeviceMsg,PCR
      lbsr  PRINT_STR_OS9
      leax  strCCTdeviceName,U
      lbsr  PRINT_STR_OS9
      leax  strCCTauthorMsg,PCR
      lbsr  PRINT_STR_OS9
      leax  strCCTauthorName,U
      lbsr  PRINT_STR_OS9
      leax  strCCTtitleMsg,PCR
      lbsr  PRINT_STR_OS9
      leax  strCCTtitleName,U
      lbsr  PRINT_STR_OS9
      lbsr  PRINT_NEWLINE_OS9
      lbra  PLAY_VGM_DATA

; -------- END CCT format file loader --------

PLAY_VGM_DATA
      ldu   <uRegImage

      ; what type of chip are we playing to?
      lda  	<vgmChipType
      cmpa  #3
      blo  	PLAY_CHIP_OPL
      lbeq  PLAY_CHIP_YM2149_CCT
      cmpa  #'G'        ; CoCo GMC
      lbeq  PLAY_CHIP_SN76489
      cmpa  #'P' 		; CoCoPSG 
      lbeq  PLAY_CHIP_YM2149
      ;cmpa  #'S'        ; Speech/Sound Cart 
      ;lbeq  PLAY_CHIP_AY8910
      ; catch any weird unexpected value here and throw error 
      lbra  UNKNOWN_ERROR_EXIT

PLAY_CHIP_OPL
      ; report coco will be frozen during playback 
      leax  strPlayingFrozen,PCR
      lbsr  PRINT_STR_OS9
      ; lock down the coco for playback and initialize hardware stuff 
      orcc  #$50        ; disable all interrupts 

      ; force high-speed poke mode (to ensure timing loops work, mainly for the GIME-X)
      clra 
      sta  	>$FFD9

      ; activate megampi extended command mode to toggle CART audio on for OPL chip in MMMPI
      lda  	<mpiExtFeatures
      sta   >mpi_reg
      lbrn  PLAY_CHIP_OPL 
      lbrn  PLAY_CHIP_OPL
      lda   #%00000100        ; enable audio out from OPL chip through internal coco CART SND 
      sta   >mmmpi_extended_reg
      lbrn  PLAY_CHIP_OPL 
      lbrn  PLAY_CHIP_OPL

      ; reset the sound chip with some delays after to let the hardware react 
      lda   <mpiOPL
      sta   >mpi_reg     ; activate OPL "slot" on MPI 
      lbrn  PLAY_CHIP_OPL
      lbrn  PLAY_CHIP_OPL
      lbrn  PLAY_CHIP_OPL
      lda   >ymf_reset   ; reset OPL3 chip 
      lbsr  BURN_CYCLES

      ; enable coco sound output on PIA
      lda   <prevPIA
      ora   #%00001000
      sta   >$FF23

      ldb   <vgmBlockCount 
      stb   <blockCounter   

      ; swap in the first block of the song data 
      leax  vgmBlockMap,U 
      ldy   #vgm_block_start
VGM_CMD_START_DATA_LOOP
      ldb   ,X+
      stb   >$FFA9            ; force MMU block to $2000 like "play" command does
VGM_NEXT_COMMAND
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_NEXT_COMMAND_SKIP         ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT      
VGM_NEXT_COMMAND_SKIP
      lda   ,Y+                     ; 6/5 cycles 
      cmpa  #$5A                    ; 2 cycles
      beq   VGM_CMD_CHIP_1    ; 3 cycles 
      cmpa  #$5E                    ; 2 cycles
      beq   VGM_CMD_CHIP_1          ; 3 cycles 
      cmpa  #$AA                    ; 2 cycles
      beq   VGM_CMD_CHIP_2  ; 3 cycles 
      cmpa  #$5F                    ; 2 cycles
      beq   VGM_CMD_CHIP_2  ; 3 cycles 
      cmpa  #$61                    ; 2 cycles
      beq   VGM_CMD_WAIT_MANUAL     ; 3 cycles 
      cmpa  #$62                    ; 2 cycles
      lbeq  VGM_CMD_WAIT_735       
      cmpa  #$63                    ; 2 cycles
      lbeq  VGM_CMD_WAIT_882       
      cmpa  #$80                    ; 2 cycles
      bhs   VGM_NEXT_COMMAND        ; 3 cycles 
      cmpa  #$70                    ; 2 cycles
      lbhs  VGM_CMD_WAIT_4_BIT     
      cmpa  #$66                    ; 2 cycles
      lbeq  VGM_CHECK_FOR_LOOP                 
      bra   VGM_NEXT_COMMAND        ; 3 cycles 

VGM_CMD_CHIP_1
      cmpy  #vgm_block_end                ; 5/4 cycles 
      blo   VGM_CMD_CHIP_1_SKIP           ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
                                          ; total: 10/8 or 24/20 to call for new block 
VGM_CMD_CHIP_1_SKIP
      lda   ,Y+                           ; 6/5 cycles 
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_CMD_CHIP_1_SKIP_AGAIN     ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
                                          ; total: 16/13 or 30/25 to call for new block      
VGM_CMD_CHIP_1_SKIP_AGAIN
      ldb   ,Y+                           ; 6/5 cycles 
      sta   >ymf_rsel_0                   ; 5/4 cycles 
      brn   VGM_CMD_CHIP_1                ; 3 cycles 
      stb   >ymf_data_0                   ; 5/4 cycles 
      brn   VGM_CMD_CHIP_1                ; 3 cycles 
      lbra  VGM_NEXT_COMMAND              ; 5/4 cycles 
                                          ; ---------
                                          ; total: 27/23

VGM_CMD_CHIP_2
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_CMD_CHIP_2_SKIP           ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
VGM_CMD_CHIP_2_SKIP
      lda   ,Y+                           ; 6/5 cycles 
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_CMD_CHIP_2_SKIP_AGAIN     ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
VGM_CMD_CHIP_2_SKIP_AGAIN
      ldb   ,Y+                           ; 6/5 cycles 
      sta   >ymf_rsel_1                   ; 5/4 cycles 
      brn   VGM_CMD_CHIP_2                ; 3 cycles 
      stb   >ymf_data_1                   ; 5/4 cycles 
      brn   VGM_CMD_CHIP_2                ; 3 cycles 
      lbra  VGM_NEXT_COMMAND              ; 5/4 cycles 

VGM_CMD_WAIT_MANUAL
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_CMD_WAIT_MANUAL_SKIP_1          ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK                   ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT           ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
VGM_CMD_WAIT_MANUAL_SKIP_1
      ldb   ,Y+                                 ; 6/5 cycles 
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_CMD_WAIT_MANUAL_SKIP_2          ; 3 cycles
      lbsr  VGM_GET_RAM_BLOCK                   ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT           ; 5 cycles (if 6809, add 1 extra cycle if branch is taken) 
VGM_CMD_WAIT_MANUAL_SKIP_2
      lda   ,Y+                                 ; 6/5 cycles

VGM_WAIT_SAMPLES
      ; coco3 fast mode, 44.1khz vgm sample rate, is 40.58439909297052 cycles per sample 
      ; loop is tuned for a rounded-up 41 cycles 
      tst   <cpuMode                ; 6/4 cycles 
      beq   VGM_WAIT_SAMPLES_6809   ; 3 cycles 
      ; add extra cycles for 6309 
      ; brn   VGM_WAIT_SAMPLES        ; 3 cycles
      ;nop                           ; 2/1 cycles 
      lbrn  VGM_WAIT_SAMPLES        ; 5 cycles 
      nop                           ; 2/1 cycles 
      nop                           ; 2/1 cycles 
VGM_WAIT_SAMPLES_6809
      sta   <u8Value                ; 4/3 cycles 
      ; BREAK/ESC key test 
      lda   #%11111011              ; 2 cycles (both 6809/6309) 
      sta   >$FF02                  ; 5/4 cycles 
      lda   >$FF00                  ; 5/4 cycles 
      bita  #%01000000              ; 2 cycles 
      beq   VGM_WAIT_ABORTED        ; 3 cycles
      lda   <u8Value                ; 4/3 cycles 
                                    ; --------------
                                    ; 25 / 21

     ; nop                           ; 2/1 cycles 
     ; brn   VGM_WAIT_SAMPLES        ; 3 cycles 
      ;lbrn  VGM_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      subd  #1                      ; 4/3 cycles 
      bne   VGM_WAIT_SAMPLES        ; 3 cycles 
      lbra  VGM_NEXT_COMMAND        ; 5/4 cycles 

VGM_CMD_WAIT_735
      ldd   #735
      bra  VGM_WAIT_SAMPLES
VGM_CMD_WAIT_882
      ldd   #882
      bra  VGM_WAIT_SAMPLES
VGM_CMD_WAIT_4_BIT
      clra                          ; 2/1 cycles 
      ldb   -1,Y                    ; 5 cycles 
      subb  #$70                    ; 2 cycles 
      incb                          ; 2/1 cycles 
      bra   VGM_WAIT_SAMPLES        ; 3 cycles 

VGM_WAIT_ABORTED
      leax  strPlayAborted,PCR
      lbsr  PRINT_STR_OS9
VGM_WAIT_ABORTED_END
      lbra  VGM_OPL_END

VGM_CHECK_FOR_LOOP
      lda   vgmLoopCount,U 
      bmi   VGM_CHECK_FOR_LOOP_FOREVER
      beq   VGM_WAIT_ABORTED_END
      ldx   vgmLoopBlockPtr,U 
      ldy   vgmLoopStart,U
      dec   vgmLoopCount,U
      lbra  VGM_CMD_START_DATA_LOOP

VGM_CHECK_FOR_LOOP_FOREVER
      ldx   vgmLoopBlockPtr,U 
      ldy   vgmLoopStart,U
      lbra  VGM_CMD_START_DATA_LOOP

********************************************
* experemtinal 
PLAY_CHIP_SN76489   
      ; report coco will be frozen during playback 
      leax  strPlayingFrozen,PCR
      lbsr  PRINT_STR_OS9
      ; lock down the coco for playback and initialize hardware stuff 
      orcc  #$50        ; disable all interrupts 

      ; force high-speed poke mode (to ensure timing loops work, mainly for the GIME-X)
      clra 
      sta  	>$FFD9

      ; check if user is using a mega mini MPI with selectable CART audio slot and toggle it if exists
      lda 	<oplDetectFlag
      beq  	PLAY_CHIP_SN76489_NO_MMMPI
      lda  	<mpiExtFeatures
      sta  	>mpi_reg
      lbrn  PLAY_CHIP_SN76489
      lda  	<mpiGMC
      anda 	#%00000011 		; strip off the MPI stuff to only leave slot number 0-3
      sta  	>mmmpi_extended_reg
PLAY_CHIP_SN76489_NO_MMMPI
      lda 	<mpiGMC
      sta  	>mpi_reg
      lbrn  PLAY_CHIP_SN76489 
      lbrn  PLAY_CHIP_SN76489 
      lbrn  PLAY_CHIP_SN76489 
      lbrn  PLAY_CHIP_SN76489 

      lbsr 	SN76489_ALL_SOUND_OFF

      ; enable coco sound output on PIA 
      lda   <prevPIA
      ora   #%00001000
      sta   >$FF23
      lbrn  PLAY_CHIP_SN76489 
      lbrn  PLAY_CHIP_SN76489 

      ; swap in the first block of the song data 
      leax  vgmBlockMap,U 
      ldy   #vgm_block_start
VGM_SN76489_CMD_START_DATA_LOOP
      ldb   ,X+
      stb   >$FFA9            ; force MMU block to $2000 like "play" command does
VGM_SN76489_NEXT_COMMAND
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_SN76489_NEXT_COMMAND_SKIP         ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT  
VGM_SN76489_NEXT_COMMAND_SKIP
      lda   ,Y+                     	; 6/5 cycles 
      cmpa  #$50   				; 2 cycles
      beq   VGM_SN76489_CMD_CHIP 		; 3 cycles
      cmpa  #$61                    	; 2 cycles
      beq  	VGM_SN76489_CMD_WAIT_MANUAL    ; 3 cycles 
      cmpa  #$62                    	; 2 cycles
      lbeq  VGM_SN76489_CMD_WAIT_735       
      cmpa  #$63                    ; 2 cycles
      lbeq  VGM_SN76489_CMD_WAIT_882       
      cmpa  #$80                    ; 2 cycles
      bhs   VGM_SN76489_NEXT_COMMAND        ; 3 cycles 
      cmpa  #$70                    ; 2 cycles
      lbhs  VGM_SN76489_CMD_WAIT_4_BIT     
      cmpa  #$66                    ; 2 cycles
      lbeq  VGM_SN76489_CHECK_FOR_LOOP                 
      bra   VGM_SN76489_NEXT_COMMAND        ; 3 cycles 

VGM_SN76489_CMD_CHIP
      cmpy  #vgm_block_end                ; 5/4 cycles 
      blo   VGM_SN76489_CMD_CHIP_SKIP      ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
                                          ; total: 10/8 or 24/20 to call for new block 
VGM_SN76489_CMD_CHIP_SKIP
      lda   ,Y+                           ; 6/5 cycles 
      sta   >gmc_register             ; 5/4 cycles 
      ; delay 10 cycles 
      lbrn  PLAY_CHIP_SN76489 
      lbrn  PLAY_CHIP_SN76489  
      lbra  VGM_SN76489_NEXT_COMMAND       ; 5/4 cycles 
                                          ; ---------
                                          ; total: 27/23 
VGM_SN76489_CMD_WAIT_MANUAL
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_SN76489_CMD_WAIT_MANUAL_SKIP_1          ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK                   ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT           ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
VGM_SN76489_CMD_WAIT_MANUAL_SKIP_1
      ldb   ,Y+                                 ; 6/5 cycles 
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_SN76489_CMD_WAIT_MANUAL_SKIP_2          ; 3 cycles
      lbsr  VGM_GET_RAM_BLOCK                   ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT           ; 5 cycles (if 6809, add 1 extra cycle if branch is taken) 
VGM_SN76489_CMD_WAIT_MANUAL_SKIP_2
      lda   ,Y+                                 ; 6/5 cycles

VGM_SN76489_WAIT_SAMPLES
      ; coco3 fast mode, 44.1khz vgm sample rate, is 40.58439909297052 cycles per sample 
      ; loop is tuned for a rounded-up 41 cycles 
      tst   <cpuMode                ; 6/4 cycles 
      beq   VGM_SN76489_WAIT_SAMPLES_6809   ; 3 cycles 
      ; add extra cycles for 6309 
      ; brn   VGM_SN76489_WAIT_SAMPLES        ; 3 cycles
      ;nop                           ; 2/1 cycles 
      lbrn  VGM_SN76489_WAIT_SAMPLES        ; 5 cycles 
      nop                           ; 2/1 cycles 
      nop                           ; 2/1 cycles 
VGM_SN76489_WAIT_SAMPLES_6809
      sta   <u8Value                ; 4/3 cycles 
      ; BREAK/ESC key test 
      lda   #%11111011              ; 2 cycles (both 6809/6309) 
      sta   >$FF02                  ; 5/4 cycles 
      lda   >$FF00                  ; 5/4 cycles 
      bita  #%01000000              ; 2 cycles 
      beq   VGM_SN76489_WAIT_ABORTED        ; 3 cycles
      lda   <u8Value                ; 4/3 cycles 
                                    ; --------------
                                    ; 25 / 21

     ; nop                           ; 2/1 cycles 
     ; brn   VGM_SN76489_WAIT_SAMPLES        ; 3 cycles 
      ;lbrn  VGM_SN76489_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_SN76489_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_SN76489_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_SN76489_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      subd  #1                      ; 4/3 cycles 
      bne   VGM_SN76489_WAIT_SAMPLES        ; 3 cycles 
      lbra  VGM_SN76489_NEXT_COMMAND        ; 5/4 cycles 

VGM_SN76489_CMD_WAIT_735
      ldd   #735
      bra  VGM_SN76489_WAIT_SAMPLES
VGM_SN76489_CMD_WAIT_882
      ldd   #882
      bra  VGM_SN76489_WAIT_SAMPLES
VGM_SN76489_CMD_WAIT_4_BIT
      clra                          ; 2/1 cycles 
      ldb   -1,Y                    ; 5 cycles 
      subb  #$70                    ; 2 cycles 
      incb                          ; 2/1 cycles 
      bra   VGM_SN76489_WAIT_SAMPLES        ; 3 cycles 

VGM_SN76489_WAIT_ABORTED
      leax  strPlayAborted,PCR
      lbsr  PRINT_STR_OS9
VGM_SN76489_WAIT_ABORTED_END
      lbra  VGM_SN76489_END

VGM_SN76489_CHECK_FOR_LOOP
      lda   vgmLoopCount,U 
      bmi   VGM_SN76489_CHECK_FOR_LOOP_FOREVER
      beq   VGM_SN76489_WAIT_ABORTED_END
      ldx   vgmLoopBlockPtr,U 
      ldy   vgmLoopStart,U
      dec   vgmLoopCount,U
      lbra  VGM_SN76489_CMD_START_DATA_LOOP

VGM_SN76489_CHECK_FOR_LOOP_FOREVER
      ldx   vgmLoopBlockPtr,U 
      ldy   vgmLoopStart,U
      lbra  VGM_SN76489_CMD_START_DATA_LOOP

***********************************
* experemtinal 
PLAY_CHIP_YM2149   
PLAY_CHIP_YM2149_CCT
      ; report coco will be frozen during playback 
      leax  strPlayingFrozen,PCR
      lbsr  PRINT_STR_OS9
      ; lock down the coco for playback and initialize hardware stuff 
      orcc  #$50        ; disable all interrupts 

      ; force high-speed poke mode (to ensure timing loops work, mainly for the GIME-X)
      clra 
      sta  	>$FFD9

      ; check if user is using a mega mini MPI with selectable CART audio slot and toggle it if exists
      lda 	<oplDetectFlag
      beq  	PLAY_CHIP_YM2149_NO_MMMPI
      lda  	<mpiExtFeatures
      sta  	>mpi_reg
      lbrn  PLAY_CHIP_YM2149
      lda  	<mpiPSG
      anda 	#%00000011 		; strip off the MPI stuff to only leave slot number 0-3
      sta  	>mmmpi_extended_reg
PLAY_CHIP_YM2149_NO_MMMPI
      lda 	<mpiPSG
      sta  	>mpi_reg
      lbrn  PLAY_CHIP_YM2149
      lbrn  PLAY_CHIP_YM2149
      lbrn  PLAY_CHIP_YM2149
      lbrn  PLAY_CHIP_YM2149 

      ; setup CoCoPSG control register and merge in our correct clock speed setting 
      clra 
      ora  	<psgClock 
      sta  	>psg_control_reg

      ; enable coco PIA sound output 
      lda   <prevPIA
      ora   #%00001000
      sta   >$FF23
      lbrn  PLAY_CHIP_YM2149
      lbrn  PLAY_CHIP_YM2149
      lbrn  PLAY_CHIP_YM2149
      lbrn  PLAY_CHIP_YM2149

      ; swap in the first block of the song data 
      leax  vgmBlockMap,U 
      ldy   #vgm_block_start
VGM_YM2149_CMD_START_DATA_LOOP
      ldb   ,X+
      stb   >$FFA9            ; force MMU block to $2000 like "play" command does
VGM_YM2149_NEXT_COMMAND
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_YM2149_NEXT_COMMAND_SKIP         ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT  
VGM_YM2149_NEXT_COMMAND_SKIP
      lda   ,Y+                     	; 6/5 cycles 
      cmpa  #$A0   				; 2 cycles
      beq   VGM_YM2149_CMD_CHIP 		; 3 cycles
      cmpa  #$61                    	; 2 cycles
      beq  	VGM_YM2149_CMD_WAIT_MANUAL    ; 3 cycles 
      cmpa  #$62                    	; 2 cycles
      lbeq  VGM_YM2149_CMD_WAIT_735       
      cmpa  #$63                    ; 2 cycles
      lbeq  VGM_YM2149_CMD_WAIT_882       
      cmpa  #$80                    ; 2 cycles
      bhs   VGM_YM2149_NEXT_COMMAND        ; 3 cycles 
      cmpa  #$70                    ; 2 cycles
      lbhs  VGM_YM2149_CMD_WAIT_4_BIT     
      cmpa  #$66                    ; 2 cycles
      lbeq  VGM_YM2149_CHECK_FOR_LOOP                 
      bra   VGM_YM2149_NEXT_COMMAND        ; 3 cycles 

VGM_YM2149_CMD_CHIP
      cmpy  #vgm_block_end                ; 5/4 cycles 
      blo   VGM_YM2149_CMD_CHIP_SKIP      ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
                                          ; total: 10/8 or 24/20 to call for new block 
VGM_YM2149_CMD_CHIP_SKIP
      lda   ,Y+                           ; 6/5 cycles 
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_YM2149_CMD_CHIP_SKIP_AGAIN ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK             ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT     ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
                                          ; total: 16/13 or 30/25 to call for new block      
VGM_YM2149_CMD_CHIP_SKIP_AGAIN
      ldb   ,Y+                           ; 6/5 cycles 
      sta   >psg_ym_reg_select            ; 5/4 cycles 
      lbrn  VGM_YM2149_CMD_CHIP           ; 5 cycles
      stb   >psg_ym_data_port             ; 5/4 cycles 
      brn   VGM_YM2149_CMD_CHIP           ; 3 cycles 
      lbra  VGM_YM2149_NEXT_COMMAND       ; 5/4 cycles 
                                          ; ---------
                                          ; total: 27/23 
VGM_YM2149_CMD_WAIT_MANUAL
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_YM2149_CMD_WAIT_MANUAL_SKIP_1          ; 3 cycles 
      lbsr  VGM_GET_RAM_BLOCK                   ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT           ; 5 cycles (if 6809, add 1 extra cycle if branch is taken)
VGM_YM2149_CMD_WAIT_MANUAL_SKIP_1
      ldb   ,Y+                                 ; 6/5 cycles 
      cmpy  #vgm_block_end                ; 5/4 cycles
      blo   VGM_YM2149_CMD_WAIT_MANUAL_SKIP_2          ; 3 cycles
      lbsr  VGM_GET_RAM_BLOCK                   ; 9/7 cycles 
      lbcs  UNEXPECTED_END_ERROR_EXIT           ; 5 cycles (if 6809, add 1 extra cycle if branch is taken) 
VGM_YM2149_CMD_WAIT_MANUAL_SKIP_2
      lda   ,Y+                                 ; 6/5 cycles

VGM_YM2149_WAIT_SAMPLES
      ; coco3 fast mode, 44.1khz vgm sample rate, is 40.58439909297052 cycles per sample 
      ; loop is tuned for a rounded-up 41 cycles 
      tst   <cpuMode                ; 6/4 cycles 
      beq   VGM_YM2149_WAIT_SAMPLES_6809   ; 3 cycles 
      ; add extra cycles for 6309 
      ; brn   VGM_YM2149_WAIT_SAMPLES        ; 3 cycles
      ;nop                           ; 2/1 cycles 
      lbrn  VGM_YM2149_WAIT_SAMPLES        ; 5 cycles 
      nop                           ; 2/1 cycles 
      nop                           ; 2/1 cycles 
VGM_YM2149_WAIT_SAMPLES_6809
      sta   <u8Value                ; 4/3 cycles 
      ; BREAK/ESC key test 
      lda   #%11111011              ; 2 cycles (both 6809/6309) 
      sta   >$FF02                  ; 5/4 cycles 
      lda   >$FF00                  ; 5/4 cycles 
      bita  #%01000000              ; 2 cycles 
      beq   VGM_YM2149_WAIT_ABORTED        ; 3 cycles
      lda   <u8Value                ; 4/3 cycles 
                                    ; --------------
                                    ; 25 / 21

     ; nop                           ; 2/1 cycles 
     ; brn   VGM_YM2149_WAIT_SAMPLES        ; 3 cycles 
      ;lbrn  VGM_YM2149_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_YM2149_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_YM2149_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      ;lbrn  VGM_YM2149_WAIT_SAMPLES        ; 5 cycles (both 6809/6309)
      subd  #1                      ; 4/3 cycles 
      bne   VGM_YM2149_WAIT_SAMPLES        ; 3 cycles 
      lbra  VGM_YM2149_NEXT_COMMAND        ; 5/4 cycles 

VGM_YM2149_CMD_WAIT_735
      ldd   #735
      bra  VGM_YM2149_WAIT_SAMPLES
VGM_YM2149_CMD_WAIT_882
      ldd   #882
      bra  VGM_YM2149_WAIT_SAMPLES
VGM_YM2149_CMD_WAIT_4_BIT
      clra                          ; 2/1 cycles 
      ldb   -1,Y                    ; 5 cycles 
      subb  #$70                    ; 2 cycles 
      incb                          ; 2/1 cycles 
      bra   VGM_YM2149_WAIT_SAMPLES        ; 3 cycles 

VGM_YM2149_WAIT_ABORTED
      leax  strPlayAborted,PCR
      lbsr  PRINT_STR_OS9
VGM_YM2149_WAIT_ABORTED_END
      lbra  VGM_YM2149_END

VGM_YM2149_CHECK_FOR_LOOP
      lda   vgmLoopCount,U 
      bmi   VGM_YM2149_CHECK_FOR_LOOP_FOREVER
      beq   VGM_YM2149_WAIT_ABORTED_END
      ldx   vgmLoopBlockPtr,U 
      ldy   vgmLoopStart,U
      dec   vgmLoopCount,U
      lbra  VGM_YM2149_CMD_START_DATA_LOOP

VGM_YM2149_CHECK_FOR_LOOP_FOREVER
      ldx   vgmLoopBlockPtr,U 
      ldy   vgmLoopStart,U
      lbra  VGM_YM2149_CMD_START_DATA_LOOP

; ---------------------
; subroutine to try and swap 1 more block of data in if available
; Carry set if no more blocks to do, carry clear means a new page was swapped in
; --------------------
VGM_GET_RAM_BLOCK
      ; ASSUMES X IS POINTER TO NEXT MMU BLOCK NUMBER IN THE MAP 
      pshs  B
      ldb   ,X+
      beq   VGM_GET_RAM_BLOCK_NONE
      stb   >$FFA9      ; force MMU page into $2000 logical ram address (like "play" command does)
      ldy   #$2000      ; reset pointer address 
      andcc #$FE        ; carry clear for success 
      puls  B,PC 
VGM_GET_RAM_BLOCK_NONE
      orcc  #1
      puls  B,PC 

; ------------------------------
; Error output section
; ------------------------------
UNKNOWN_ERROR_EXIT
      leax  strErrorUnknown,PCR
      lbsr  PRINT_STR_OS9
      lbra  EXIT_DEALLOCATE_RAM 

PARAM_ERROR_EXIT
      leax  strErrorParams,PCR
      lbsr  PRINT_STR_OS9
      lbra  EXIT_TO_OS9 

UNEXPECTED_END_ERROR_EXIT
      leax  strErrorSuddenEnd,PCR
      lbsr  PRINT_STR_OS9
      lbra  PLAY_DONE_RESET_STATES 

READ_ERROR_EXIT
	stb  	<u8Value
	lbsr 	PRINT_BYTE_HEX
	lbsr 	PRINT_NEWLINE_OS9
      leax  strErrorRead,PCR 
      lbsr  PRINT_STR_OS9
      lbra  EXIT_DEALLOCATE_RAM 

RAM_ERROR_EXIT
      leax  strErrorRam,PCR
      lbsr  PRINT_STR_OS9
      lbra  EXIT_DEALLOCATE_RAM 

FILE_ERROR_EXIT
      leax  strErrorFile,PCR
      lbsr  PRINT_STR_OS9
      lbra  EXIT_CLOSE_ALL_PATHS

NO_FILENAME_ERROR_EXIT
      leax  strErrorNoFilename,PCR 
      lbsr  PRINT_STR_OS9
      lbra  EXIT_TO_OS9

INVALID_FILE_ERROR_EXIT
      leax  strErrorFileInvalid,PCR 
      lbsr  PRINT_STR_OS9
      lbra  EXIT_CLOSE_ALL_PATHS

USAGE_HELP_EXIT
	ldu 	<uRegImage
	lda 	#STDOUT 
	leax 	strUsageMsg,PCR 
	ldy 	#strUsageMsgSz 
	os9 	I$Write 
      leax  strThanksMsg,PCR
      lbsr  PRINT_STR_OS9
      lbra  EXIT_TO_OS9

FILETYPE_HELP_INFO
	ldu 	<uRegImage
	lda 	#STDOUT
	leax 	strFileTypeInfo,PCR 
	ldy  	#strFileTypeInfoSz
	os9  	I$Write 
	lbra  EXIT_TO_OS9

VGM_AY8910_END
      ; reset the hardware 
      ldu   <uRegImage
      lda   #1
      sta   >$FF7D
      clra 
      sta   >$FF7D
      lbra  PLAY_DONE_RESET_STATES

VGM_YM2149_END 
      ; reset the hardware 
      ldu   <uRegImage

      pshs 	CC   		; save current state of interrupts
      orcc 	#$50 		; temporarily disable them when talking to hardware directly 
      ; turn off tone and noise output in the mixer
      lda  	#$07
      sta  	>psg_ym_reg_select
      lbrn  VGM_YM2149_END
      lda 	>psg_ym_data_port 	; get current state of mixer register 
      lbrn  VGM_YM2149_END
      ora  	#%00111111 			; turn off both noise and tone output on A,B,C 
      sta   >psg_ym_data_port
      puls 	CC  		; restore CC and initial state of interrupts
      bra  	PLAY_DONE_RESET_STATES

VGM_SN76489_END
      ; reset the hardware 
      ldu   <uRegImage
   	lbsr  SN76489_ALL_SOUND_OFF
      lbra  PLAY_DONE_RESET_STATES

VGM_OPL_END 
      ldu   <uRegImage    
	lbsr 	OPL_ALL_SOUND_OFF  	; reset OPL chip before we exit 

PLAY_DONE_RESET_STATES
      ; restore original state of MPI 
      lda   <prevMPI
      sta   >mpi_reg
   	; restore original PIA state which SHOULD disable cart audio
      lda   <prevPIA
      sta   >$FF23
EXIT_DEALLOCATE_RAM
      ; deallocate ram before exiting 
      ldu   <uRegImage
      leay  vgmBlockMap,U 
EXIT_DEALLOCATE_NEXT
      clra
      ldb   ,Y+
      beq   EXIT_CHECK_PLAYLIST
      tfr   D,X 
      ldb   #1          ; deallocate a single block at a time 
      os9   F$DelRAM 
      cmpy  <vgmBlockMapPtr
      blo   EXIT_DEALLOCATE_NEXT
EXIT_CHECK_PLAYLIST
      lda   <playlistFlag
      beq  	EXIT_PRINT_COMPLETE_MSG  	; we werent playing from a playlist so we are done 
      ; ok we are using a playlist. search for another entry
      ldx  	<playlistPtr
      clrb 
EXIT_CHECK_PLAYLIST_NEXT
      lda  	,X+
      cmpa 	#C$CR
      beq  	EXIT_CHECK_PLAYLIST_FOUND
      decb
      bne  	EXIT_CHECK_PLAYLIST_NEXT 	
      ; if we are here, something really bad went wrong so just exit
      bra  	EXIT_CLOSE_ALL_PATHS
      
EXIT_CHECK_PLAYLIST_FOUND
	; is this the final CR though and therefore no more entries?
	lda 	,X 
	beq 	EXIT_PRINT_COMPLETE_MSG  	; yep, we are all done then 
	; nope, more entries left. update ptrs and jump back up to play next track 
      stx  	<playlistPtr
      lbra  VGM_OPEN_FILE

EXIT_CHECK_ABORT_FLAG
      lda   <abortFlag 
      bne   EXIT_CLOSE_ALL_PATHS           ; we are exiting because an abort, so skip completed message 
EXIT_PRINT_COMPLETE_MSG
      leax  strPlayComplete,PCR
      lbsr  PRINT_STR_OS9
EXIT_CLOSE_ALL_PATHS
      ; check each path if they are open and close each if they are  
      lda   <playlistFilePath
      bmi   EXIT_CLOSE_ALL_PATHS_SKIP_PLAYLIST
      os9   I$Close 
      lbrn  EXIT_CLOSE_ALL_PATHS
EXIT_CLOSE_ALL_PATHS_SKIP_PLAYLIST
      lda   <songFilePath
      bmi   EXIT_CLOSE_ALL_PATHS_SKIP_SONG
      os9   I$Close 
      lbrn  EXIT_CLOSE_ALL_PATHS          ; delay 5 cycles 
EXIT_CLOSE_ALL_PATHS_SKIP_SONG
EXIT_TO_OS9
	; check if there are '.' characters in the keyboard buffer from aborting tracks and read/purge them
	lda  	#STDIN 
	ldb 	#$01  		; SS.Ready
	os9  	I$GetStt 
	bcs  	EXIT_TO_OS9_SKIP_KEY_CLEAR
	tstb 
	beq  	EXIT_TO_OS9_SKIP_KEY_CLEAR
	; there are keystrokes of some kind waiting, read them to clear buffer so they dont display upon exit
	clra 
	tfr  	D,Y 
	lda  	#STDIN 
	leax  vgmDataBuffer,U 
	os9  	I$Read 

EXIT_TO_OS9_SKIP_KEY_CLEAR
      clrb 
      os9   F$Exit

********************************************************************
* Start of Sub-routine area 
********************************************************************
; ABORT signal handler
SIGNAL_HANDLER
      cmpb  #S$Intrpt
      beq   SIGNAL_HANDLER_ABORT
      cmpb  #S$Abort
      beq   SIGNAL_HANDLER_ABORT
      rti 

SIGNAL_HANDLER_ABORT
      lda   #1
      sta   <abortFlag 
      rti 

; ----------------------------------------
; convert coco ASCII text to regular ASCII
; Entry: A = coco ascii character 
; Exit: A = standard ascii equivalent character 
; ----------------------------------------
CONVERT_COCO_ASCII
      cmpa  #$60
      blo   CONVERT_COCO_ASCII_CHECK_NEXT
      suba  #$40
      rts

CONVERT_COCO_ASCII_CHECK_NEXT
      cmpa  #$20
      bhs   CONVERT_COCO_ASCII_SKIP
      adda  #$40
CONVERT_COCO_ASCII_SKIP
      rts

; ------------------------------------------------------
; Print a NULL terminated string of characters to STDOUT
; (Max 256 characters not including NULL)
; Entry: X = pointer to NULL terminated string 
; ------------------------------------------------------
PRINT_STR_OS9
      pshs  Y,X,D 

      ; first find length 
      clrb
PRINT_STR_OS9_NEXT
      lda   ,X+
      beq   PRINT_STR_OS9_FOUND_LENGTH
      incb 
      bne   PRINT_STR_OS9_NEXT
      ; string is over 256 chars so print just those and return 
      ldy   #256
      bra   PRINT_STR_OS9_SKIP_LENGTH

PRINT_STR_OS9_FOUND_LENGTH
      clra 
      tfr   D,Y         ; move character count to Y for I$Write syscall 
PRINT_STR_OS9_SKIP_LENGTH
      lda   #STDOUT
      ldx   2,S         ; grab original value from stack 
      os9   I$Write
      nop 
      nop 

      puls  D,X,Y,PC 

; --------------------------------
; do a CR+LF for a new line 
; --------------------------------
PRINT_NEWLINE_OS9
      pshs  Y,X,D 
      lda   #STDOUT
      ldy   #2
      leax  strNewLine,PCR 
      os9   I$Write
      puls  D,X,Y,PC 

; -------------------------------------------------------------------------
; print either single file "loading" message or playlist file entry loading
; message depending on if valid playlist file path has been opened 
; -------------------------------------------------------------------------
PRINT_LOADING_MSG
      pshs  Y,X,D 

      ldb   <playlistFilePath
      bmi   PRINT_LOADING_MSG_SINGLE_FILE
      ; if here, playlist mode. display "loading track x of x ..." msg 
      leax  strLoadingPLS,PCR 
      lbsr  PRINT_STR_OS9
      ldb   <playlistCurTrack
      incb 
      stb   <playlistCurTrack
      leax  strNumeric,U 
      lbsr  CONVERT_BYTE_DEC  
      lbsr  PRINT_STR_OS9           ; print current track number 
      leax  strOf,PCR
      lbsr  PRINT_STR_OS9           ; print " of "
      ldb   <playlistTotal
      leax  strNumeric,U
      lbsr  CONVERT_BYTE_DEC
      lbsr  PRINT_STR_OS9
      leax  strDots,PCR 
      lbsr  PRINT_STR_OS9           ; print "... "
      bra   PRINT_LOADING_MSG_FILENAME

PRINT_LOADING_MSG_SINGLE_FILE
      leax  strLoading,PCR
      lbsr  PRINT_STR_OS9

PRINT_LOADING_MSG_FILENAME
      ldx   <filenamePtr
      lda   #STDOUT 
      ldy   #256        ; max 256 chars 
      os9   I$WritLn

      puls  D,X,Y,PC 

;---------------------------------
; convert to uppercase 
; Entry: A = character to be converted 
; Exit: A = converted character 
; --------------------------------
CONVERT_UPPERCASE
      ; check and/or convert lowercase to uppercase
      cmpa  #$61        ; $61 is "a"
      blo   CONVERT_UPPERCASE_NO_CONVERSION
      cmpa  #$7A  ; $7A is "z"
      bhi   CONVERT_UPPERCASE_NO_CONVERSION
      suba  #$20  ; convert from lowercase to uppercase 
CONVERT_UPPERCASE_NO_CONVERSION
      rts 

;----------------------------------------------------
; convert both A and B registers to uppercase at once 
; Entry: A and B = characters to be converted 
; Exit: A and B = converted characters 
; ---------------------------------------------------
CONVERT_UPPERCASE_WORD
      ; check and/or convert lowercase to uppercase
      cmpa  #$61        ; $61 is "a"
      blo   CONVERT_UPPERCASE_WORD_NO_CONVERSION_A
      cmpa  #$7A  ; $7A is "z"
      bhi   CONVERT_UPPERCASE_WORD_NO_CONVERSION_A
      suba  #$20  ; convert from lowercase to uppercase 
CONVERT_UPPERCASE_WORD_NO_CONVERSION_A
      ; check and/or convert lowercase to uppercase
      cmpb  #$61        ; $61 is "a"
      blo   CONVERT_UPPERCASE_WORD_NO_CONVERSION_B
      cmpb  #$7A  ; $7A is "z"
      bhi   CONVERT_UPPERCASE_WORD_NO_CONVERSION_B
      subb  #$20  ; convert from lowercase to uppercase 
CONVERT_UPPERCASE_WORD_NO_CONVERSION_B
      rts 

; --------------------------------
; wait awhile 
; --------------------------------
BURN_CYCLES
      pshs  X,D 
      ldx   #$8000
BURN_CYCLES_LOOP
      leax  -1,X              ; 5 cycles 
      bne   BURN_CYCLES_LOOP  ; 3 cycles 
      puls  D,X,PC 

; -------------------------------------------------------
; determine what execution mode CPU is in 
; (Code is from "Motorola 6809 and Hitachi 6309 Programmer's Reference" by Darren Atkinson)
; -------------------------------------------------------
TSTNM 
      PSHS  U,Y,X,DP,CC       ; Preserve Registers
      ORCC  #$D0              ; Mask interrupts and set E flag
      TFR   W,Y               ; Y=W (6309), Y=$FFFF (6809)
      LDA   #1                ; Set result for NM=1
      BSR   L1                ; Set return point for RTI when NM=1
      BEQ   L0                ; Skip next instruction if NM=0
      TFR   X,W               ; Restore W
L0    PULS  CC,DP,X,Y,U       ; Restore other registers
      TSTA                    ; Setup CC.Z to reflect result
      RTS
L1    BSR   L2                ; Set return point for RTI when NM=0
      CLRA                    ; Set result for NM=0
      RTS
L2    PSHS  U,Y,X,DP,D,CC     ; Push emulation mode machine state
      RTI                     ; Return to one of the two BSR calls

; ----------------------------------------------------------
; use officially documented routine used for detecting adlib
; to detect whether or not MMMPI/OPL chip is connected
; Carry clear on positive detection, set if none found 
; ----------------------------------------------------------
DETECT_OPL_CHIP
      pshs  U,Y,X,D,CC 

      orcc 	#$50 			; temporarily disable all interrupts. will get restored with the PULS at end

      ; force high-speed poke mode (to ensure timing loops work, mainly for the GIME-X)
      clra 
      sta  	>$FFD9

      lsr  	,S  			; shift carry flag out of saved CC
      ; make YM262 chip active device in MPI slot
      lda   <mpiOPL 
      sta   >mpi_reg

      ; reset OPL chip 
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      lda 	>ymf_reset
      lbsr 	BURN_CYCLES

      lda   #4
      ldb   #$60
      sta   >ymf_rsel_0
      lbrn  DETECT_OPL_CHIP 	; delay for registers to settle 
      lbrn  DETECT_OPL_CHIP 	; delay for registers to settle 
      stb   >ymf_data_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP

      lda   #4
      ldb   #$80
      sta   >ymf_rsel_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP 
      stb   >ymf_data_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP

      ldb   >ymf_status
      andb  #%11100000        ; only the first 3 bits are valid so mask out the rest in case of intermittent bad bits 
      stb   <u16Value         ; store first result in high byte of u16Value 

      lda   #2
      ldb   #$FF
      sta   >ymf_rsel_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      stb   >ymf_data_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP 

      lda   #4
      ldb   #$21
      sta   >ymf_rsel_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      stb   >ymf_data_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP

      ; wait AT LEAST 80 microseconds
      ;ldb   #35
      ldb  	#42
DETECT_OPL_CHIP_WAIT_LOOP
      decb 
      bne   DETECT_OPL_CHIP_WAIT_LOOP

      ldb   >ymf_status 
      andb  #%11100000        ; only the first 3 bits are valid so mask out the rest in case of intermittent bad bits 
      stb   <u16Value+1       ; store second result in low byte of u16Value
 
      ; reset timers and IRQs regardless
      lda   #4
      ldb   #$60
      sta   >ymf_rsel_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      stb   >ymf_data_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP

      lda 	#4
      ldb   #$80
      sta   >ymf_rsel_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP
      stb   >ymf_data_0
      lbrn  DETECT_OPL_CHIP
      lbrn  DETECT_OPL_CHIP

      ; restore original MPI selection 
      lda   <prevMPI
      sta   >mpi_reg 

      ; check our results and return
      ldd   <u16Value
      cmpd  #$00C0 
      beq   DETECT_OPL_CHIP_SUCCESS  	; carry flag should already be clear if equal
      ; if here, it failed to detect an OPL chip/MMMPI 
      orcc  #1
DETECT_OPL_CHIP_SUCCESS
      rol  	,S  			; rotate result in carry flag into CC on the stack before returning
      puls  CC,D,X,Y,U,PC 

; --------------------------------------------------------------
; turn off all sound registers and disable sound on the OPL chip
; --------------------------------------------------------------
OPL_ALL_SOUND_OFF
	pshs 	X,D,CC
	
	orcc 	#$50 		; temporarily disable interrupts

      ; force high-speed poke mode (to ensure timing loops work, mainly for the GIME-X)
      clra 
      sta  	>$FFD9

	; toggle OPL active in MPI register 
      lda   <mpiOPL
      sta   >mpi_reg 
      lbrn  OPL_ALL_SOUND_OFF
      lbrn  OPL_ALL_SOUND_OFF 

      ; shut off the various operators, channels, sustain, etc 
      ; HUGE THANKS TO ED SNIDER FOR PROVIDNG ME WITH THIS METHOD 
      lda   #$05
      ldb   #%00000001              ; set ymf-262 top opl3 compatibility
      sta   >ymf_rsel_1  		; OPL3 MODE BIT ONLY EXISTS IN THIS SECOND SET OF REGISTERS
      lbrn  OPL_ALL_SOUND_OFF 
      stb   >ymf_data_1  		; OPL3 MODE BIT ONLY EXISTS IN THIS SECOND SET OF REGISTERS
      lbrn  OPL_ALL_SOUND_OFF 

      ; make sure all channels 2 op 
      lda   #$04                    ; connection sel 
      clrb 
      sta   >ymf_rsel_1
      lbrn  OPL_ALL_SOUND_OFF 
      stb   >ymf_data_1
      lbrn  OPL_ALL_SOUND_OFF 

      ; set sustain/release levels prioer to key off 
      leax  sustainRelease,PCR 
      ldb   #18
      stb   <u8Value
      ldb   #$0F
OPL_ALL_SOUND_OFF_RESET_1_NEXT 
      lda   ,X+      
      sta   >ymf_rsel_0
      lbrn  OPL_ALL_SOUND_OFF 
      stb   >ymf_data_0
      lbrn  OPL_ALL_SOUND_OFF 
      sta   >ymf_rsel_1
      lbrn  OPL_ALL_SOUND_OFF 
      stb   >ymf_data_1
      dec   <u8Value
      bne   OPL_ALL_SOUND_OFF_RESET_1_NEXT

      ; key off on all channels 
      lda   #$B0
      ldb   #9
      stb   <u8Value  
      clrb 
OPL_ALL_SOUND_OFF_RESET_2_NEXT
      sta   >ymf_rsel_0
      lbrn  OPL_ALL_SOUND_OFF 
      stb   >ymf_data_0
      lbrn  OPL_ALL_SOUND_OFF 
      sta   >ymf_rsel_1
      lbrn  OPL_ALL_SOUND_OFF 
      stb   >ymf_data_1
      lbrn  OPL_ALL_SOUND_OFF 
      inca 
      dec   <u8Value
      bne   OPL_ALL_SOUND_OFF_RESET_2_NEXT

      ; restore MPI's original state 
      lda 	<prevMPI
      sta   >mpi_reg 
      lbrn  OPL_ALL_SOUND_OFF
      lbrn  OPL_ALL_SOUND_OFF 

      puls 	CC,D,X,PC 

; ---------------------------------------
SN76489_ALL_SOUND_OFF
	pshs  D,CC

	orcc 	#$50  		; temporarily disable interrupts when talking directly to hardware 

      ; force high-speed poke mode (to ensure timing loops work, mainly for the GIME-X)
      clra 
      sta  	>$FFD9

	ldd 	#$9FBF 
	sta  	>gmc_register
	lbrn  SN76489_ALL_SOUND_OFF
	lbrn 	SN76489_ALL_SOUND_OFF
	lbrn  SN76489_ALL_SOUND_OFF
	lbrn 	SN76489_ALL_SOUND_OFF
	stb  	>gmc_register
	ldd  	#$DFFF
	sta  	>gmc_register
	lbrn  SN76489_ALL_SOUND_OFF
	lbrn 	SN76489_ALL_SOUND_OFF
	lbrn  SN76489_ALL_SOUND_OFF
	lbrn 	SN76489_ALL_SOUND_OFF
	stb  	>gmc_register
	lbrn  SN76489_ALL_SOUND_OFF
	lbrn 	SN76489_ALL_SOUND_OFF
	lbrn  SN76489_ALL_SOUND_OFF
	lbrn 	SN76489_ALL_SOUND_OFF

	puls  CC,D,PC 

; ---------------------------------------
; scan for another flag parameter 
; Entry: X = pointing to string to search 
; Exit: on success, carry clear, X is pointing to the flag character returned 
;       on fail, carry set, X is pointer to first non-space char 
; ---------------------------------------
SEARCH_PARAMETER_FLAG
      pshs  A

      lbsr  SEARCH_NEXT_NONSPACE
      lda   ,X+
      cmpa  #'-'
      bne   SEARCH_PARAMETER_FLAG_NONE
      andcc #$FE        ; carry clear success
      puls  A,PC              

SEARCH_PARAMETER_FLAG_NONE
      leax  -1,X        ; undo auto-increment 
      orcc  #1          ; not found 
      puls  A,PC 
       
; -------------------------------------------------------
; scan for the next non-space character 
; Entry: X = pointing to area of string to search through 
; Exit: on success, carry clear, X points to the first non-space character 
;       on fail, carry set, X is restored to original value 
; -------------------------------------------------------
SEARCH_NEXT_NONSPACE
      pshs  X,D 

      clrb 
SEARCH_NEXT_NONSPACE_NEXT
      lda   ,X+
      cmpa  #$20
      bne   SEARCH_NEXT_NONSPACE_DONE
      decb 
      bne   SEARCH_NEXT_NONSPACE_NEXT
      ; never found a non-space character within 256 bytes 
      orcc  #1
      puls  D,X,PC            ; restore everything and return 

SEARCH_NEXT_NONSPACE_DONE      
      leax  -1,X              ; reverse the auto-increment
      puls  D 
      leas  2,S               ; skip X on the stack 
      andcc #$FE              ; carry clear on success 
      rts                     ; return with X pointing to non-space character 

; --------------------------------------------------------------------------------
; copy a raw string until NULL 
; Entry: X = source pointer, Y = Destination Pointer 
; Exit: carry set = fail, carry clear success, Y = pointer to final NULL in dest 
; --------------------------------------------------------------------------------
STRING_COPY_RAW
	pshs 	X,D 
	clrb 
STRING_COPY_RAW_NEXT
	lda 	,X+
	sta 	,Y+
	beq 	STRING_COPY_RAW_DONE
	decb 
	bne 	STRING_COPY_RAW_NEXT
	coma 	; set carry for error 
	puls 	D,X,PC 

STRING_COPY_RAW_DONE
	leay 	-1,Y 		; undo auto-increment 
	; carry already cleared from STA of NULL 
	puls 	D,X,PC 

; -----------------------------
; convert 8-bit binary value to ascii decimal
; Entry: B = value to be printed in decimal ASCII 
;        X = destination to write result 
; --------------------------------
CONVERT_BYTE_DEC
      pshs  Y,X,D 

      ldy   #$0000      ; use Y as flag to tell if we need to ignore leading zeros
      clra 
CONVERT_BYTE_DEC_INC_100S
      subb  #100 
      blo   CONVERT_BYTE_DEC_JUMP_10S
      inca 
      leay  1,Y
      bra   CONVERT_BYTE_DEC_INC_100S
CONVERT_BYTE_DEC_JUMP_10S
      cmpy  #$0000
      beq   CONVERT_BYTE_DEC_SKIP_100S
      adda  #$30  ; the magic ASCII number 
      sta   ,X+
CONVERT_BYTE_DEC_SKIP_100S
      clra        ; reset counter
      addb  #100
CONVERT_BYTE_DEC_INC_10S
      subb  #10
      blo   CONVERT_BYTE_DEC_JUMP_1S 
      inca 
      leay  1,Y   
      bra   CONVERT_BYTE_DEC_INC_10S
CONVERT_BYTE_DEC_JUMP_1S
      cmpy  #$0000
      beq   CONVERT_BYTE_DEC_SKIP_10S
      adda  #$30
      sta   ,X+
CONVERT_BYTE_DEC_SKIP_10S
      addb  #$3A  ; $30 ASCII '0' + 10 from previous subtraction 
      stb   ,X+

      clr   ,X          ; NULL temrinator 

      puls  D,X,Y,PC

; --------------------------------------------------------
; convert 32 bit value to comma delimited decimal number 
; Entry: X = pointer to 32 bit value to convert
; Exit:  X = pointer to start position in strNumeric where
; 	   ascii result is stored with leading zeros removed
; --------------------------------------------------------
CONVERT_BINARY32_DECIMAL
	pshs 	Y,D 

	ldd 	,X 
	std 	u32Value,U 
	ldd 	2,X 
	std 	u32Value+2,U 

	ldd 	#"0,"
	std 	<strNumeric 
	ldd 	#"00"
	std 	<strNumeric+2
	ldd 	#"0,"
	std 	<strNumeric+4
	ldd 	#"00"
	std 	<strNumeric+6
	ldd 	#"0,"
	std 	<strNumeric+8
	ldd 	#"00"
	std 	<strNumeric+10
	ldd 	#$3000
	std 	<strNumeric+12

	leax 	u32Value,U 
	leay 	bin32dec1B,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_1B
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_100M
	inc 	<strNumeric
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_1B
CONVERT_BINARY32_DECIMAL_DO_100M
	lbsr 	ADD_32BIT
	leay 	bin32dec100M,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_100M
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_10M
	inc 	<strNumeric+2
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_100M
CONVERT_BINARY32_DECIMAL_DO_10M
	lbsr 	ADD_32BIT
	leay 	bin32dec10M,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_10M
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_1M
	inc 	<strNumeric+3
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_10M
CONVERT_BINARY32_DECIMAL_DO_1M
	lbsr 	ADD_32BIT
	leay 	bin32dec1M,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_1M
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_100K
	inc 	<strNumeric+4
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_1M
CONVERT_BINARY32_DECIMAL_DO_100K
	lbsr 	ADD_32BIT
	leay 	bin32dec100K,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_100K
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_10K
	inc 	<strNumeric+6
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_100K
CONVERT_BINARY32_DECIMAL_DO_10K
	lbsr 	ADD_32BIT
	leay 	bin32dec10K,PCR 
CONVERT_BINARY32_DECIMAL_NEXT_10K
	lbsr 	SUBTRACT_32BIT
	bcs 	CONVERT_BINARY32_DECIMAL_DO_1K
	inc 	<strNumeric+7
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_10K
CONVERT_BINARY32_DECIMAL_DO_1K
	lbsr 	ADD_32BIT
	ldd 	u32Value+2,U 
CONVERT_BINARY32_DECIMAL_NEXT_1K
	subd 	#1000
	bcs 	CONVERT_BINARY32_DECIMAL_DO_100
	inc 	<strNumeric+8
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_1K
CONVERT_BINARY32_DECIMAL_DO_100
	addd 	#1000
CONVERT_BINARY32_DECIMAL_NEXT_100
	subd 	#100
	bcs 	CONVERT_BINARY32_DECIMAL_DO_10
	inc 	<strNumeric+10
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_100
CONVERT_BINARY32_DECIMAL_DO_10
	addd 	#100
CONVERT_BINARY32_DECIMAL_NEXT_10
	subd 	#10
	bcs 	CONVERT_BINARY32_DECIMAL_DO_1
	inc 	<strNumeric+11
	bra 	CONVERT_BINARY32_DECIMAL_NEXT_10
CONVERT_BINARY32_DECIMAL_DO_1
	addd 	#10
	addb 	#$30
	stb 	<strNumeric+12

	; move pointer to eliminate leading zeroes 
	ldy 	2,S 		; get Y back from the stack 
	leax 	strNumeric,U 
CONVERT_BINARY32_DECIMAL_SKIP_COMMA
	lda 	,X+
	beq 	CONVERT_BINARY32_DECIMAL_ZERO_RESULT
	cmpa 	#','
	beq 	CONVERT_BINARY32_DECIMAL_SKIP_COMMA
	cmpa 	#$30
	bne 	CONVERT_BINARY32_DECIMAL_FOUND
	bra 	CONVERT_BINARY32_DECIMAL_SKIP_COMMA
CONVERT_BINARY32_DECIMAL_ZERO_RESULT
	leax 	-1,X 
CONVERT_BINARY32_DECIMAL_FOUND
	leax 	-1,X

	puls 	D,Y,PC 

; --------------------------------
; print hex byte value 
; --------------------------------
PRINT_BYTE_HEX
      pshs  U,Y,X,D

      ldu   <uRegImage

      leay  asciiHexList,PCR
      lda   asciiHexPrefix,PCR 
      sta   <strNumeric  
   
      lda   <u8Value
      lsra 
      lsra
      lsra
      lsra
      lda   A,Y
      sta   <strNumeric+1              ; store first digit

      lda   <u8Value 
      anda  #$0F
      lda   A,Y 
      sta   <strNumeric+2              ; store second digit

      lda   #STDOUT
      ldy   #3
      leax  strNumeric,U 
      os9   I$Write
      nop 
      nop 
      puls  D,X,Y,U,PC 

; ------------------------------------------------------------------------------
; load contents of a playlist up to 256 byte buffer. each entry should be a
; filename or a full pathname ending with a $0D byte (CR)
; Entry: pathname to playlist file must be open and stored in playlistFilePath 
; Exit: playlistTotal variable contains total entries (skipping empty lines)
; 	  playlist file path is closed.
;       ALWAYS resets U to the default pointer to variable area of os9 program 
; ------------------------------------------------------------------------------
LOAD_PLAYLIST_ENTRIES 
      pshs  U,Y,X,D 

      ; first seek to beginning of playlist filename/path area after header
      lda  	<playlistFilePath
      ldx   #0
      ldu   #8
      os9   I$Seek
      ldu 	<uRegImage

      ; init some vars
      leay 	playlistBuffer,U 
      sty 	<playlistPtr
      ldd 	#0
      std  	<playlistByteTotal
      sta   <playlistTotal
LOAD_PLAYLIST_ENTRIES_NEXT
	lda  	<playlistFilePath
	leax 	vgmDataBuffer,U 	; read into here temporarily
      ldy   #255 
      os9   I$ReadLn
      bcs   LOAD_PLAYLIST_ENTRIES_CHECK_FOR_ERROR
      cmpy  #1
      beq   LOAD_PLAYLIST_ENTRIES_NEXT   ; skip counter if line is empty (a single CR by itself)
      ; for now, ignore any .M3U info tags which are always prefixed with a '#'
      lda  	,X 
      cmpa  #'#'
      beq  	LOAD_PLAYLIST_ENTRIES_NEXT  
   	; ok now add new byte count to total and make sure theres enough room in the buffer 
   	tfr 	Y,D 
   	addd 	<playlistByteTotal
   	cmpd 	#playlist_buffer_sz
   	bhi 	LOAD_PLAYLIST_ENTRIES_ERROR
   	; if here, there should be enough room in playlistBuffer
   	std  	<playlistByteTotal
   	tfr 	Y,D
   	ldy 	<playlistPtr 
LOAD_PLAYLIST_ENTRIES_COPY_NEXT
   	lda 	,X+
   	sta 	,Y+
   	decb 
   	bne  	LOAD_PLAYLIST_ENTRIES_COPY_NEXT
   	sty  	<playlistPtr  	; update buffer ptr
	; terminate the current entry with NULL (will be overwritten if there are additional entries)
   	clr  	,Y 			
   	; increment entry counter
      inc   <playlistTotal
      bra   LOAD_PLAYLIST_ENTRIES_NEXT

LOAD_PLAYLIST_ENTRIES_CHECK_FOR_ERROR
      cmpb  #E$EOF 
      beq   LOAD_PLAYLIST_ENTRIES_DONE
LOAD_PLAYLIST_ENTRIES_ERROR
      orcc  #1          ; set carry for error 
      puls  D,X,Y,U,PC

LOAD_PLAYLIST_ENTRIES_DONE
	; close playlist file path
	lda  	<playlistFilePath
	os9  	I$Close 
	lbrn  PAUSE_5_CYCLES

      leay 	playlistBuffer,U 
      sty 	<playlistPtr

      andcc #$FE              ; clear carry for success 
      puls  D,X,Y,U,PC 

; --------------------------------
; check a 32 bit value to see if it's 0 
; Entry: X = pointer to 32 bit value (will be in "intel" little endian order)
; Exit: zero flag is set if 32bit value is all 0's, zero flag is clear otherwise 
; ----------------------------------
CHECK_FOR_32BIT_ZERO
      pshs  D 
      ldd   ,X 
      bne   CHECK_FOR_32BIT_ZERO_NOPE
      ldd   2,X 
CHECK_FOR_32BIT_ZERO_NOPE
      puls  D,PC 


; -----------------------------------
; compare two 32 bit numbers 
; -----------------------------------
COMPARE_32BIT
      pshs  D
      ldd   2,X 
      subd  2,Y 
      std  	<u32Value+2
      ldd   ,X 
      sbcb  1,Y 
      sbca  ,Y 
      std  	<u32Value
  
      ; carry should be set properly now from subtract, now make sure zero flag works too
      ;ldd   <u32Value	; not needed cuz previous instruction was STD which already sets the Z and N flags 
      bne   COMPARE_32BIT_NOT_ZERO
      ldd   <u32Value+2
      andcc #%11110111 
COMPARE_32BIT_NOT_ZERO
      puls  D,PC 

; -----------------------------------
; 32 bit subtraction 
; -----------------------------------
SUBTRACT_32BIT
      pshs  D
      ldd   2,X 
      subd  2,Y 
      std   2,X 
      ldd   ,X 
      sbcb  1,Y 
      sbca  ,Y 
      std   ,X 

      ; carry should be set properly now from subtract, now make sure zero flag works too
      ;ldd   ,X   ; not needed cuz previous instruction was STD ,X which already sets the Z and N flags 
      bne   SUBTRACT_32BIT_NOT_ZERO
      ldd   2,X
      andcc #%11110111 
SUBTRACT_32BIT_NOT_ZERO
      puls  D,PC 


 ;----------------------------------
 ; 32 bit addition 
 ; ---------------------------------
ADD_32BIT
      pshs  D 
      ldd   2,X 
      addd  2,Y 
      std   2,X 
      ldd   ,X 
      adcb  1,Y 
      adca  ,Y 
      std   ,X 

      bne   ADD_32BIT_NOT_ZERO
      ldd   2,X 
      andcc #%11110111
ADD_32BIT_NOT_ZERO
      puls  D,PC 

*******************************************************************************
* Extract GD3 tag info from VGM file 
EXTRACT_GD3_TAG_INFO
      pshs  U,Y,X,D 

      ldu   <uRegImage  ; make sure os9 data area pointer is loaded 

      ; read 12 bytes. file pointer should already be seeked to right spot 
      lda   <songFilePath
      ldy   #12
      leax  vgmDataBuffer,U 
      os9   I$Read 
      lbcs   EXTRACT_GD3_TAG_INFO_ERROR

      ldd   ,X 
      cmpd  #"Gd"
      bne   EXTRACT_GD3_TAG_INFO_ERROR
      ldd   2,X 
      cmpd  #"3 "
      bne   EXTRACT_GD3_TAG_INFO_ERROR
      ; if here, gd3 tag found 
      ldd   10,X
      stb   gd3TagSize,U 
      sta   gd3TagSize+1,U 
      ldd   8,X 
      stb   gd3TagSize+2,U
      sta   gd3TagSize+3,U 

      ; copy over the title info string 
      ;leax  12,X              ; skip to start of actual tag string fields 
      leay  gd3TagTrackName,U 
      lbsr  EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR
      lbsr  EXTRACT_GD3_TAG_INFO_SCAN_NULL  ; get passed the japanese version if present
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

      leay  gd3TagGameName,U 
      lbsr  EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR
      lbsr  EXTRACT_GD3_TAG_INFO_SCAN_NULL  ; get passed the japanese version if present
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

      leay  gd3TagSystemName,U 
      lbsr  EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR
      lbsr  EXTRACT_GD3_TAG_INFO_SCAN_NULL  ; get passed the japanese version if present
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

      leay  gd3TagAuthorName,U 
      bsr   EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR
      bsr   EXTRACT_GD3_TAG_INFO_SCAN_NULL  ; get passed the japanese version if present
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

      leay  gd3TagReleaseDate,U 
      bsr   EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

      leay  gd3TagMadeByName,U 
      bsr   EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

      leay  gd3TagNotes,U 
      bsr   EXTRACT_GD3_TAG_INFO_COPY_STRING
      bcs   EXTRACT_GD3_TAG_INFO_ERROR

EXTRACT_GD3_TAG_INFO_EOF
      andcc #$FE              ; success 
      puls  D,X,Y,U,PC 

EXTRACT_GD3_TAG_INFO_ERROR   
      orcc  #1          ; carry for error of some kind 
      puls  D,X,Y,U,PC 

; -----------------------------
; read 2 bytes from the gd3 tag in the file path open for songFilePath
; Entry: U pointing to program data area
;        songFilePath should be an open path to song file with file pointer 
;        pointing at next 2 bytes in gd3 tag 
; Exit: D = 2 bytes read from file. only valid, if carry is clear meaning no error
;       on fail, carry set 
; -----------------------------
EXTRACT_GD3_TAG_INFO_READ_WORD
      pshs  Y,X 

      lda   <songFilePath
      ldy   #2          ; 2 bytes to read 
      leax  u16Value,U 
      os9   I$Read 
      bcs   EXTRACT_GD3_TAG_INFO_READ_WORD_EXIT 

      ; decrement bytes remaining by 2 
      leax  gd3TagSize,U 
      leay  gd3TagWordConst,PCR 
      lbsr  SUBTRACT_32BIT
      bcs   EXTRACT_GD3_TAG_INFO_READ_WORD_EXIT

      ldd   <u16Value   ; return the word in D
EXTRACT_GD3_TAG_INFO_READ_WORD_EXIT
      ; carry already set for error condition, clear otherwise
      puls  X,Y,PC         

; ----------------------------------
; Entry: X = pointer to beginning of gd3 string 
;        y = pointer to where to copy the normal ascii to 
; Exit: X = will point to the byte AFTER the string null 
;        Exit: carry will have been set if we ran out of bytes 
; ----------------------------------
EXTRACT_GD3_TAG_INFO_COPY_STRING
      bsr   EXTRACT_GD3_TAG_INFO_READ_WORD
      bcs   EXTRACT_GD3_TAG_INFO_COPY_STRING_NULL
      beq   EXTRACT_GD3_TAG_INFO_COPY_STRING_NULL
      cmpd  #$0A00            ; detect newline character for "notes" section 
      beq   EXTRACT_GD3_TAG_INFO_COPY_STRING_NEWLINE
      sta   ,Y+
EXTRACT_GD3_TAG_INFO_COPY_STRING_NEXT
      bsr   EXTRACT_GD3_TAG_INFO_READ_WORD
      bcs   EXTRACT_GD3_TAG_INFO_COPY_STRING_NULL
      beq   EXTRACT_GD3_TAG_INFO_COPY_STRING_DONE
      cmpd  #$0A00            ; detect newline character for "notes" section 
      beq   EXTRACT_GD3_TAG_INFO_COPY_STRING_NEWLINE
      sta   ,Y+
      bra   EXTRACT_GD3_TAG_INFO_COPY_STRING_NEXT

EXTRACT_GD3_TAG_INFO_COPY_STRING_NEWLINE
      ldd   #cr_lf            ; coco CR+LF 
      std   ,Y++
      bra   EXTRACT_GD3_TAG_INFO_COPY_STRING_NEXT

EXTRACT_GD3_TAG_INFO_COPY_STRING_DONE
      ; add a newline CR+LF at the end of the name 
      ldd   #cr_lf
      std   ,Y++
EXTRACT_GD3_TAG_INFO_COPY_STRING_NULL
      ; mark null end 
      clr   ,Y 
      rts

; ----------------------------------
; entry: X = pointer to string to search for NULL in 
; Exit: carry will have been set if we ran out of bytes 
; ----------------------------------
EXTRACT_GD3_TAG_INFO_SCAN_NULL
      bsr   EXTRACT_GD3_TAG_INFO_READ_WORD
      bcs   EXTRACT_GD3_TAG_INFO_SCAN_NULL_END
      beq   EXTRACT_GD3_TAG_INFO_SCAN_NULL_END
      bra   EXTRACT_GD3_TAG_INFO_SCAN_NULL
EXTRACT_GD3_TAG_INFO_SCAN_NULL_END
      rts 

* end of GD3 tag extracting code 
*******************************************************************************
; -----------------------------------------------
; print the vgm tag info to the screen 
; Entry: None 
; -----------------------------------------------
GD3_PRINT_TAG
      pshs  U,X,D 

      ldu   <uRegImage

      lbsr  PRINT_NEWLINE_OS9

      ; check if we have valid tag info 
      lda   gd3TagFlag,U
      bne   GD3_PRINT_TAG_PRESENT
      leax  strGD3none,PCR 
      lbsr  PRINT_STR_OS9
      lbra  GD3_PRINT_TAG_EXIT

GD3_PRINT_TAG_PRESENT
      ; print out the vgm gd3 tag info 
      ; track title 
      ldb   gd3TagTrackName,U
      beq   GD3_SKIP_TRACK
      leax  gd3TagTrackLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagTrackName,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_TRACK
      ldb   gd3TagGameName,U 
      beq   GD3_SKIP_GAME
      leax  gd3TagGameLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagGameName,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_GAME
      ldb   gd3TagSystemName,U 
      beq   GD3_SKIP_SYSTEM
      leax  gd3TagSystemLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagSystemName,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_SYSTEM
      ldb   gd3TagAuthorName,U 
      beq   GD3_SKIP_AUTHOR
      leax  gd3TagAuthorLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagAuthorName,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_AUTHOR
      ldb   gd3TagReleaseDate,U 
      beq   GD3_SKIP_DATE
      leax  gd3TagDateLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagReleaseDate,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_DATE
      ldb   gd3TagMadeByName,U 
      beq   GD3_SKIP_MADE_BY
      leax  gd3TagMadeByLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagMadeByName,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_MADE_BY
      ldb   gd3TagNotes,U 
      beq   GD3_SKIP_NOTES
      leax  gd3TagNotesLabel,PCR 
      lbsr  PRINT_STR_OS9
      leax  gd3TagNotes,U 
      lbsr  PRINT_STR_OS9
GD3_SKIP_NOTES

GD3_PRINT_TAG_EXIT
      puls  D,X,U,PC


; ------------------------------------------------------------------
; calculate song length from total samples
; Entry: X = pointer to 32 bit total number of samples in song track
; ------------------------------------------------------------------
CALCULATE_SONG_LENGTH
      pshs  U,Y,X,D 

      ldu   <uRegImage

      ldd   ,X 
      std   <u32Value
      ldd   2,X 
      std   <u32Value+2

      ldd   #0
      ;std   <u16Value
      clra 
      sta   vgmSongLengthMins,U
      sta   vgmSongLengthSecs,U

      leax  u32Value,U 
      leay  vgmSamplesPerSec,PCR 
CALCULATE_SONG_LENGTH_DIV
      lbsr  SUBTRACT_32BIT
      bcs   CALCULATE_SONG_LENGTH_DIV_DONE
      addd  #1
      bra   CALCULATE_SONG_LENGTH_DIV

CALCULATE_SONG_LENGTH_DIV_DONE
      ; now we have length in seconds. store result temporarily
      lbsr  ADD_32BIT         ; get remainder back for fractional seconds 
      ldy   2,X               ; load only relevant 16 bit remainder of u32Value 
      cmpy  #22050            ; if we have half or more samples/sec left, add extra second to round 
      blo   CALCULATE_SONG_LENGTH_MINUTE_DIV    ; skip if less 
      addd  #1                ; add an extra second to round 
CALCULATE_SONG_LENGTH_MINUTE_DIV
      subd  #60         ; 60 secs per minute 
      bcs   CALCULATE_SONG_LENGTH_MINUTE_DIV_DONE
      inc   vgmSongLengthMins,U 
      bra   CALCULATE_SONG_LENGTH_MINUTE_DIV

CALCULATE_SONG_LENGTH_MINUTE_DIV_DONE
      addd  #60         ; get remainder back 
      stb   vgmSongLengthSecs,U 

      puls  D,X,Y,U,PC 

; -----------------------------------------------------------------------------------
VGM_CALC_BLOCK_FROM_OFFSET
      pshs  Y,X,D

      ; convert relative loop offset into absolute one 
      leax  vgmLoopOffset,U 
      leay  vgmLoopHeaderConst,PCR 
      lbsr  ADD_32BIT
      ; copy result to temp var 
      ldd   vgmLoopOffset,U 
      std   u32Value,U 
      ldd   vgmLoopOffset+2,U 
      std   u32Value+2,U 

     	leax  u32Value,U 
      leay  vgmDataOffset,U
      lbsr  SUBTRACT_32BIT
 
      leay  vgmBlockSizeConst,PCR         ; size of 1 memory block or 8192 bytes 
      ; now divide into the number of bytes the offset is at 
      clrb 
VGM_CALC_BLOCK_FROM_OFFSET_DIVIDE
      lbsr  SUBTRACT_32BIT
      bcs   VGM_CALC_BLOCK_FROM_OFFSET_FOUND
      incb 
      bra   VGM_CALC_BLOCK_FROM_OFFSET_DIVIDE

VGM_CALC_BLOCK_FROM_OFFSET_FOUND
      lbsr  ADD_32BIT
      clra 
      leay  vgmBlockMap,U 
      leay  D,Y 
      sty   vgmLoopBlockPtr,U 
      ldd   2,X 
      addd  #$2000            ; since we use a static local RAM address of $2000 for start of each data block 
      std   vgmLoopStart,U 

      puls  D,X,Y,PC 

; --------------------------------------------------------------------
; copy in the appropriate vgm soundchip clock speed to vgmCurrentClock
; Entry: X = pointer to appropriate offset in VGM header for clock
; 	  	 speed to copy
; --------------------------------------------------------------------
GRAB_VGM_CLOCK_VALUE
	pshs 	D 

	lda  	3,X 
	ldb  	2,X 
	std  	<vgmCurrentClock 
	lda  	1,X 
	ldb  	,X 
	std  	<vgmCurrentClock+2

	puls 	D,PC 

; --------------------------------------------------------------------
PRINT_VGM_CLOCK
	pshs 	U,Y,X 

	ldu 	<uRegImage
	; convert VGM clock speed into ascii and print it
	leay 	stringBuffer,U 
	leax 	strVGMclock,PCR 
	lbsr 	STRING_COPY_RAW
	leax 	vgmCurrentClock,U 
	lbsr 	CONVERT_BINARY32_DECIMAL
	lbsr 	STRING_COPY_RAW
	leax  strHz,PCR 
	lbsr 	STRING_COPY_RAW
	leax 	stringBuffer,U 
	lbsr 	PRINT_STR_OS9

	puls 	X,Y,U,PC 

PAUSE_5_CYCLES
*************************************************************************************
	EMOD 
MODULE_SIZE 	; put this at the end so it can be used for module size 


