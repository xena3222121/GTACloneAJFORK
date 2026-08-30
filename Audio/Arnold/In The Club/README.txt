Drop .wav voice lines here for Arnold's "just walked into Prism" line.

Wired up in building_entrance.gd (voice_clips_dir) on the club's Entrance
node in World.tscn, played via player.gd's play_random_voice_clip() - it
scans this folder at the moment you walk in, so no code changes are
needed when new files are added. One random .wav plays each time you
enter; it won't cut itself off or get interrupted by other lines mid-line
(checks voice_line_player.playing first), so a long clip is fine.
