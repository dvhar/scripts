#!/home/d/anaconda3/bin/python3
#pip install torch
#pip isntall espnet_model_zoo

import sys
import soundfile
import os
from espnet_model_zoo.downloader import ModelDownloader
from espnet2.bin.tts_inference import Text2Speech
d = ModelDownloader()
text2speech = Text2Speech(**d.download_and_unpack("kan-bayashi/csmsc_tts_train_conformer_fastspeech2_raw_phn_pypinyin_g2p_phone_train.loss.ave"))
speech, *_ = text2speech(sys.stdin.read())
soundfile.write("/tmp/espeakpy.wav", speech.numpy(), text2speech.fs, "PCM_16")
os.system("mpv /tmp/espeakpy.wav")
