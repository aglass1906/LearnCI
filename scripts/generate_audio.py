
import os

import json
import random
import requests
from dotenv import load_dotenv
import time
import argparse
from openai import OpenAI

# Load environment variables
load_dotenv()
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Data')
AUDIO_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Audio')

# ElevenLabs Constants
EL_VOICES_URL = "https://api.elevenlabs.io/v1/voices"
EL_TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"

# OpenAI Constants
OPENAI_VOICES = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]

# --- ElevenLabs Functions ---

def get_elevenlabs_voices():
    if not ELEVENLABS_API_KEY:
        print("Error: ELEVENLABS_API_KEY not found needed for ElevenLabs provider.")
        return []
        
    headers = {"xi-api-key": ELEVENLABS_API_KEY}
    response = requests.get(EL_VOICES_URL, headers=headers)
    if response.status_code == 200:
        return response.json()['voices']
    else:
        print(f"Error fetching ElevenLabs voices: {response.status_code} - {response.text}")
        return []

def generate_audio_elevenlabs(text, voice_id, output_path, attempts=0):
    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }
    data = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75}
    }
    
    url = EL_TTS_URL.format(voice_id=voice_id)
    response = requests.post(url, json=data, headers=headers)
    
    if response.status_code == 200:
        with open(output_path, 'wb') as f:
            f.write(response.content)
        return True
    elif response.status_code == 429: # Rate limit
        if attempts < 3:
            print("Rate limited. Waiting 10 seconds...")
            time.sleep(10)
            return generate_audio_elevenlabs(text, voice_id, output_path, attempts + 1)
        else:
            print("Rate limit exceeded.")
            return False
    else:
        print(f"Error generating audio: {response.status_code} - {response.text}")
        return False

# --- OpenAI Functions ---

def generate_audio_openai(text, voice_id, output_path):
    if not OPENAI_API_KEY:
        print("Error: OPENAI_API_KEY not found needed for OpenAI provider.")
        return False

    client = OpenAI(api_key=OPENAI_API_KEY)
    
    try:
        response = client.audio.speech.create(
            model="tts-1",
            voice=voice_id,
            input=text
        )
        response.stream_to_file(output_path)
        return True
    except Exception as e:
        print(f"Error generating OpenAI audio: {e}")
        return False

# --- Main ---

def main():
    parser = argparse.ArgumentParser(description="Generate missing audio files for LearnCI.")
    parser.add_argument("--deck", "-d", help="Specific deck filename to process (e.g., 'spanish_beginner.json')", default=None)
    parser.add_argument("--provider", "-p", choices=['elevenlabs', 'openai'], default='elevenlabs', help="TTS Provider (default: elevenlabs)")
    args = parser.parse_args()

    voices = []
    
    if args.provider == 'elevenlabs':
        print("Fetching voices from ElevenLabs...")
        voices = get_elevenlabs_voices()
        if not voices:
            exit(1)
        print(f"Found {len(voices)} ElevenLabs voices.")
    elif args.provider == 'openai':
        print("Using OpenAI voices...")
        voices = [{'voice_id': v, 'name': v} for v in OPENAI_VOICES]
        print(f"Available OpenAI voices: {', '.join(OPENAI_VOICES)}")

    # Get existing audio files
    if not os.path.exists(AUDIO_DIR):
        os.makedirs(AUDIO_DIR)
    
    existing_audio = set(os.listdir(AUDIO_DIR))
    
    missing_files = []
    
    print("Scanning for missing audio files...")
    for root, dirs, files in os.walk(DATA_DIR):
        for file in files:
            if file.endswith('.json'):
                if args.deck and file != args.deck:
                    continue

                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r') as f:
                        data = json.load(f)
                        
                    if 'cards' in data:
                        print(f"Scanning deck: {file}")
                        for card in data['cards']:
                            # Select a voice for this card so word/sentence match
                            card_voice = random.choice(voices)
                            
                            if 'audioWordFile' in card and card['audioWordFile'] not in existing_audio:
                                missing_files.append({
                                    'text': card['wordTarget'], 
                                    'filename': card['audioWordFile'], 
                                    'type': 'word', 
                                    'deck': file,
                                    'voice': card_voice
                                })
                            if 'audioSentenceFile' in card and card['audioSentenceFile'] not in existing_audio:
                                missing_files.append({
                                    'text': card['sentenceTarget'], 
                                    'filename': card['audioSentenceFile'], 
                                    'type': 'sentence', 
                                    'deck': file,
                                    'voice': card_voice
                                })
                                    
                except Exception as e:
                    print(f"Error reading {file}: {e}")

    total_missing = len(missing_files)
    print(f"Found {total_missing} missing audio files.")
    
    if total_missing == 0:
        print("All audio files match! Nothing to do.")
        return

    print(f"Starting generation using {args.provider}...")
    
    success_count = 0
    fail_count = 0
    
    for i, item in enumerate(missing_files):
        voice = item['voice']
        voice_id = voice['voice_id']
        voice_name = voice['name']
        
        filename = item['filename']
        output_path = os.path.join(AUDIO_DIR, filename)
        
        print(f"[{i+1}/{total_missing}] Generating {filename} ({item['type']}) using {args.provider} voice '{voice_name}'...")
        
        success = False
        if args.provider == 'elevenlabs':
            success = generate_audio_elevenlabs(item['text'], voice_id, output_path)
        else:
            success = generate_audio_openai(item['text'], voice_id, output_path)
            
        if success:
            success_count += 1
            if args.provider == 'elevenlabs':
                time.sleep(0.5) # Delay for EL rate limits
        else:
            fail_count += 1
            
    print("-" * 30)
    print("Generation Complete!")
    print(f"Success: {success_count}")
    print(f"Failed: {fail_count}")
    print(f"Failed: {fail_count}")
    print("-" * 30)

if __name__ == "__main__":
    main()
