
import os
import time
import requests
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables
load_dotenv()
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") # Use Service Role Key for uploads

# ElevenLabs Sound Effects API Constants
EL_SOUND_EFFECTS_URL = "https://api.elevenlabs.io/v1/sound-generation"

# Catalog matching AmbientSound.swift
SOUND_CATALOG = [
    {"id": "cafe_busy",       "prompt": "Busy café background noise, muffled chatter, clinking cups, espresso machine hiss"},
    {"id": "fireplace",       "prompt": "Crackling fireplace, warm cozy wood burning, steady hearth fire"},
    {"id": "urban_street",    "prompt": "City street ambience, distant traffic hum, occasional car pass, muffled sirens, urban background"},
    {"id": "jungle_wind",     "prompt": "Dense jungle wind, rustling leaves, distant tropical birds, humid rainforest atmosphere"},
    {"id": "rain_night",      "prompt": "Heavy rain at night, falling on a roof, rhythmic water sounds, distant thunder"},
    {"id": "old_building",    "prompt": "Creaking old building, wooden floorboard groans, settling house, whistling wind through cracks"},
    {"id": "enchanted_forest","prompt": "Magical enchanted forest, ethereal sparkles, gentle birdsong, soft wind, mystical atmosphere"},
    {"id": "tavern_crowd",    "prompt": "Medieval tavern ambience, rowdy crowd chatter, wooden table thuds, distant lute music, hearth fire"},
    {"id": "spaceship_hum",   "prompt": "Spaceship interior hum, low frequency engine vibration, technological drone, pneumatic hiss"},
    {"id": "futuristic_city", "prompt": "Futuristic city ambience, flying vehicle whirrs, neon digital hums, clean hi-tech background"},
    {"id": "coffee_shop",     "prompt": "Soft coffee shop ambience, light jazz background, gentle typing, quiet conversation, steaming milk"},
    {"id": "neighborhood",    "prompt": "Quiet suburban neighborhood, distant lawnmower, bird chirping, soft breeze, peaceful morning"},
    {"id": "park_outdoor",    "prompt": "Outdoor public park, children playing in distance, wind through trees, park bench sounds"},
    {"id": "eerie_wind",      "prompt": "Eerie haunted wind, whistling through empty trees, cold ghostly breeze, unsettling atmosphere"},
    {"id": "forest_night",    "prompt": "Dark forest at night, owl hoots, chirping crickets, rustling undergrowth, mysterious atmosphere"},
    {"id": "marketplace",     "prompt": "Bustling cobblestone marketplace, merchants shouting, horse hooves, crowd noise, historic atmosphere"},
    {"id": "countryside",     "prompt": "Open rolling countryside, sheep bleating, steady wind over grass, rural tranquility"}
]

def init_supabase() -> Client:
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("Error: Missing SUPABASE_URL or SUPABASE_KEY in .env")
        exit(1)
    return create_client(SUPABASE_URL, SUPABASE_KEY)

def generate_sound(id, prompt):
    print(f"Generating sound for '{id}': \"{prompt}\"")
    headers = {
        "xi-api-key": ELEVENLABS_API_KEY,
        "Content-Type": "application/json"
    }
    data = {
        "text": prompt,
        "loop": True,
        "duration_seconds": 22, # Generate 22s for better looping
        "prompt_influence": 0.5,
        "model_id": "eleven_text_to_sound_v2"
    }
    
    response = requests.post(EL_SOUND_EFFECTS_URL, json=data, headers=headers)
    
    if response.status_code == 200:
        filename = f"{id}.mp3"
        with open(filename, "wb") as f:
            f.write(response.content)
        print(f"Successfully generated {filename}")
        return filename
    else:
        print(f"Error generating {id}: {response.status_code} - {response.text}")
        return None

def upload_to_supabase(supabase: Client, filename):
    try:
        remote_path = f"ambient/{filename}"
        
        # Check if already exists
        res = supabase.storage.from_("ambient-sounds").list("ambient")
        if any(f['name'] == filename for f in res):
            print(f"Skipping {filename} - already exists in Supabase")
            return True

        print(f"Uploading {filename} to Supabase 'ambient-sounds' bucket as '{remote_path}'...")
        with open(filename, 'rb') as f:
            supabase.storage.from_("ambient-sounds").upload(
                file=f,
                path=remote_path,
                file_options={"content-type": "audio/mpeg", "x-upsert": "true"}
            )
        print(f"Successfully uploaded {filename}")
        return True
    except Exception as e:
        print(f"Failed to upload {filename}: {e}")
        return False

def main():
    if not ELEVENLABS_API_KEY:
        print("Error: ELEVENLABS_API_KEY not found in .env")
        exit(1)
        
    supabase = init_supabase()
    
    # Pre-fetch existing files to avoid redundant work
    try:
        existing_files = [f['name'] for f in supabase.storage.from_("ambient-sounds").list("ambient")]
        print(f"Found {len(existing_files)} existing sounds in bucket.")
    except Exception as e:
        print(f"Error listing bucket: {e}")
        existing_files = []

    for item in SOUND_CATALOG:
        filename = f"{item['id']}.mp3"
        if filename in existing_files:
            print(f"Skipping {item['id']} - already exists")
            continue

        filename = generate_sound(item["id"], item["prompt"])
        if filename:
            success = upload_to_supabase(supabase, filename)
            if success:
                # Remove local file after upload
                if os.path.exists(filename):
                    os.remove(filename)
            # Small sleep to be kind to APIs
            time.sleep(2)

if __name__ == "__main__":
    main()
