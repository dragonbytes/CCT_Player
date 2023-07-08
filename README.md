# CoCo ChipTunes Player

A chiptunes player written for the Tandy Color Computer 3 running under <a href="https://sourceforge.net/projects/nitros9/">NitrOS-9</a>.

Written by Todd Wallace  
YouTube: https://www.youtube.com/@tekdragon  
Website: https://tektodd.com  
<br>
<p align="center"><img src="https://github.com/dragonbytes/CCT_Player/assets/17234382/51b232a8-649c-40eb-b9b1-14c11eb5c99f"></p>
<br>

A "ChipTune" is basically a music file that contains FM-synthersizer instructions that allow the right hardware to perfectly reproduce the original song. This differs from most of the standard music formats we are used to that contain SAMPLED audio waveforms. (Think MP3s, WAV files, etc). The downside is that in order for chiptunes to be playable, you have to have compatible hardware or software capable of emulating the real hardware. As of version 1.6, my player currently supports 3 different CoCo hardware accessories, the Mega-Mini MPI (which has an onboard OPL 3 soundchip), the CoCoPSG cart, and the GMC (Game Master Cartridge). Both the PSG and GMC can be emulated under MAME, so even if you don't have the hardware, you can still enjoy some chiptune goodness!

This player supports 3 file formats: VGM, CCT and M4U. VGM is a standardized format mostly for 8-bit video-game oriented soundtracks. CCT files are Ed Snider's custom CoCo-specific chiptune format compatible with his Mega-Mini MPI and CoCoPSG hardware. M4U files are standard playlist files that allow you to put together your own mixes of chiptunes tracks. If you have more than one of the supported soundchips, you can actually include songs that will play on them all in the same playlist. My player will automatically select the appropriate hardware needed on the fly to play them! I am particuarly proud of this feature! :-D

If you download the whole VHD image for the latest release, in addition to the program itself, you will find an assortment of sample song files that are sorted in directories based on the hardware chip type. VGM files that depend on unsupported chips will not work with this player and will generate an error message explaining why. Running the "cctplay" program by itself without any other arguments will display an extensive list of configuration flags and detailed file format information. Have fun and happy listening!

<br><br>

### New in Version 1.6

This update has been long in the making, but I finally feel like it’s ready for the wild! ALOT has changed since my last update of the player. For one thing, I completely restructured the code to make things more modular in order to more easily support other hardware while reusing some of the same routines (more on this shortly). I pretty much had this new version finished a few months ago, but I discovered a bug in the OPL code where it wouldn’t silence all the instruments in a song when you would abruptly stop playback, and I wanted to fix that before releasing it. Then I got sidetracked with boring life stuff, but I finally had time to find the bug and squash it! Sooo on to the good stuff!

The first new feature I’ve added is VGM Loop support. Some VGM files include embedded instructions to loop certain sections of the song, usually so you can have a unique intro separate from the main looping section, and these are now supported natively. I also added a flag to allow the user to customize how many iterations the loop should go through before finishing. The default is 1 loop, but you can select between 0 and 9, or have it loop forever.

The next major change is new hardware support! For one thing, I have added code for users using native GIME-X NitrOS-9 builds that will force it out of turbo speed mode into normal high-speed mode in order for my timing loops to work correctly. NitrOS-9 automatically returns the GIME-X back into turbo mode periodically on its own so this shouldn’t affect anything after playback is done. Maybe I can find a more elegant solution in the future. But now, the BIG news.

I had explored the possibility in the past of adding support for devices other than the Mega Mini-MPI, but I lacked any way to experiment and test code to see if I could get them working. A few months ago though, I learned that MAME can actually emulate most of them! I had been talking with someone on IRC who was excited to receive his new CocoPSG and was asking if it was supported in my player, so I started tinkering. One device supported became TWO! At the same time, I started poking into how the Game Master Cartridge worked as well, and in short order, two became THREE! During my testing using MAME, it became apparent that addressing these sound carts if more than one were connected at the same time could make things tricky. So I decided on implementing some new flags that allow the user to specify an MPI slot for both the GMC and PSG (OPL uses “virtual” slots so flags aren’t needed for it). This means that you could potentially have a Mega Mini-MPI with both a Game Master Cartridge AND a CocoPSG connected to it, and be able to play song files made for any one of them at any time. For example, you could create a playlist mix that has OPL, PSG, and GMC music files that automatically route sound to the appropriate device!

Speaking of playlists, that is another significant change from the previous version of my player. In the past, playlists were just pathnames to files separated by carriage returns and the only way for the player to recognize one was for you to use the -p flag. This new version supports proper M3U playlist files which are automatically detected regardless of the file extension and without the need of any flags! You can easily make one with any CoCo text editor and instructions are including in the help section of the program.

I’m super proud of how this player has evolved and hope to add more support in the future as well. I do warn you though that all my testing has been done inside an emulation environment and so I can’t guarantee it will work perfectly on real hardware as I don’t own any (yet). Please let me know if you have any problems so I can troubleshoot! Feel free to check out my demo video below and use the download link to try it for yourself. The VHD disk image contains sample music for all the new devices as well as the previous OPL ones so you can experiment. Have fun!
