"""Offline asset authoring only. Neural model/runtime remain under builds, outside game exports.
Uses Kokoro-82M (Apache-2.0) through kokoro-onnx (MIT).
Run with builds/voice-tools/venv/bin/python tools/generate_pa_voice.py.
"""
from pathlib import Path
import shutil
import subprocess
import numpy as np
import soundfile as sf
from misaki import en, espeak
from kokoro_onnx import Kokoro

ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'builds/voice-tools'
DEST=ROOT/'audio/pa'
RAW=DEST/'generated'
LINES={
 'welcome': 'Attention, staff. Station Seven is now open.',
 'approach': 'Your attention, please. The next train is arriving at platform seven. Please stay behind the yellow line.',
 'boarding': 'The train to North Terminal is now boarding at platform seven. Please mind the gap.',
 'false_call': 'Your attention, please. The final service has been cancelled. Please leave the platform.',
 'departure': 'Please stand clear of the doors. The train is now departing.',
}
model=Kokoro(str(CACHE/'kokoro-v1.0.onnx'),str(CACHE/'voices-v1.0.bin'))
g2p=en.G2P(trf=False,british=False,fallback=espeak.EspeakFallback(british=False))
print('Voice A: American female af_heart, Misaki English pronunciation', flush=True)
for name,text in LINES.items():
 phonemes,_=g2p(text)
 samples,rate=model.create(phonemes,voice='af_heart',speed=0.96,is_phonemes=True)
 assert np.isfinite(samples).all() and len(samples)>rate
 sf.write(RAW/(name+'-female-clean.wav'),samples,rate,subtype='PCM_16')
 target=DEST/(name+'.wav')
 backup=RAW/(name+'-previous-emma.wav')
 if target.exists() and not backup.exists(): shutil.copy2(target,backup)
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(RAW/(name+'-female-clean.wav')),'-af','highpass=f=70,loudnorm=I=-19:TP=-3:LRA=9,adelay=200,apad=pad_dur=0.3','-ar','48000','-ac','1','-c:a','pcm_s16le',str(target)],check=True)
 print(name,round(len(samples)/rate,2),'seconds',flush=True)
