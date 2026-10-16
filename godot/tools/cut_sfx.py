"""Cut one shot from each CC0 recording into a short mono OGG for the game.

Usage: python -I cut_sfx.py <firearm_dir> <kenney_scifi_audio_dir> <out_dir>
Finds the first loud onset (silencedetect), cuts `length` seconds from just before it, pitches, fades the tail
out, normalises the peak to -3 dBFS plus a per-clip gain, writes Ogg Vorbis 44.1 kHz mono.
"""
import os
import re
import subprocess
import sys

firearm, kenney, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)

# clip name -> (source, seconds, pitch, extra gain dB)
F = lambda gun, f: os.path.join(firearm, gun, f)
K = lambda f: os.path.join(kenney, f)
CLIPS = {
    "shot_pistol": (F("Walther PPQ", "X_31P.wav"), 0.45, 1.0, 0),
    "shot_smg": (F("PPSh", "P_22P.wav"), 0.18, 1.05, -2),
    "shot_minigun": (F("AK-47", "C_29P.wav"), 0.12, 1.25, -5),
    "shot_shotgun": (F("Mossberg", "N_30P.wav"), 0.7, 1.0, 0),
    "shot_railgun": (F("Savage 10 .300 Blackout", "T_17P.wav"), 0.9, 0.85, 0),
    "shot_rocket": (K("thrusterFire_000.ogg"), 0.5, 0.9, -2),
    "shot_grenade": (F("Model 12", "K_17P.wav"), 0.25, 0.6, -3),
    "shot_laser": (K("laserSmall_000.ogg"), 0.3, 1.0, -4),
    "shot_flamethrower": (K("thrusterFire_001.ogg"), 0.12, 1.1, -8),
    "explode": (K("explosionCrunch_000.ogg"), 0.9, 0.8, 0),  # the low-frequency one swells in over ~0.1 s: late
    "shot_hand_cannon": (F("Savage 10 .300 Blackout", "T_27P.wav"), 0.6, 1.1, 0),
    "shot_ripper": (F("PPSh", "P_34P.wav"), 0.2, 0.95, -2),
    "shot_scattergun": (F("Model 12", "K_22P.wav"), 0.8, 0.9, 0),
    "shot_prism": (K("laserLarge_000.ogg"), 0.35, 1.0, -4),
    "shot_swarm": (K("thrusterFire_002.ogg"), 0.5, 0.8, -2),
    "shot_bullet_storm": (F("AK-47", "C_31P.wav"), 0.12, 1.35, -5),
    "shot_annihilator": (F("Savage 10 .300 Blackout", "T_17P.wav"), 1.1, 0.7, 0),
    "shot_inferno": (K("thrusterFire_003.ogg"), 0.14, 0.95, -8),
    "shot_cluster": (F("Model 12", "K_22P.wav"), 0.25, 0.55, -3),
}


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def onset(src):
    r = run(["ffmpeg", "-hide_banner", "-i", src, "-af", "silencedetect=noise=-35dB:d=0.05", "-f", "null", "-"])
    starts = re.findall(r"silence_start: ([0-9.]+)", r.stderr)
    ends = re.findall(r"silence_end: ([0-9.]+)", r.stderr)
    if starts and float(starts[0]) > 0.02:
        return 0.0  # loud from the first sample
    return float(ends[0]) if ends else 0.0


def peak_db(path):
    r = run(["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"])
    m = re.search(r"max_volume: (-?[0-9.]+) dB", r.stderr)
    return float(m.group(1)) if m else 0.0


for name, (src, length, pitch, gain) in CLIPS.items():
    if not os.path.exists(src):
        raise SystemExit("missing " + src)
    start = max(0.0, onset(src) - 0.01)
    tmp = os.path.join(out, name + ".tmp.wav")
    fade_at = length * 0.55
    af = ("pan=mono|c0=0.5*c0+0.5*c1,aresample=44100,asetrate=%d,aresample=44100,"
          "afade=t=in:st=0:d=0.004,afade=t=out:st=%.3f:d=%.3f" % (int(44100 * pitch), fade_at, length - fade_at))
    # pitch p plays the input p times faster, so cut length x p of input for length of output
    r = run(["ffmpeg", "-hide_banner", "-y", "-ss", "%.3f" % start, "-t", "%.3f" % (length * pitch), "-i", src,
             "-af", af, tmp])
    if r.returncode != 0:
        raise SystemExit(name + ": " + r.stderr[-400:])
    boost = -3.0 + gain - peak_db(tmp)
    dst = os.path.join(out, name + ".ogg")
    r = run(["ffmpeg", "-hide_banner", "-y", "-i", tmp, "-af", "volume=%.2fdB" % boost, "-c:a", "libvorbis", "-q:a", "4", dst])
    os.remove(tmp)
    if r.returncode != 0:
        raise SystemExit(name + ": " + r.stderr[-400:])
    print("%-20s onset=%.3fs len=%.2fs pitch=%.2f boost=%+.1fdB %d bytes" % (name, start, length, pitch, boost, os.path.getsize(dst)))
