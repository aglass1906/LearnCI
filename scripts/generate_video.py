import os
import time
import argparse
from dotenv import load_dotenv
from supabase import create_client, Client
from google import genai
from google.genai import types

# Load environment variables
load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Video')

STYLES = {
    "1": ("Pixar 3D", "highly detailed, expressive, and colorful Pixar 3D animation aesthetic"),
    "2": ("Studio Ghibli 2D Anime", "highly atmospheric, hand-drawn 2D Studio Ghibli anime aesthetic"),
    "3": ("Photorealistic Cinematic", "hyper-detailed, photorealistic cinematic grade shot on a 35mm lens"),
    "4": ("Tim Burton Stop-Motion", "moody, atmospheric, stylized, highly detailed Tim Burton stop-motion aesthetic"),
    "5": ("Watercolor Storybook", "soft, gentle, hand-painted watercolor illustration aesthetic, like a classic children's book brought to life"),
    "6": ("Claymation", "highly tactile, physical claymation stop-motion aesthetic, with visible textures, fingerprints, and studio lighting"),
    "7": ("Vintage 1930s Cartoon", "classic 1930s rubber-hose cartoon animation aesthetic, expressive bouncy movements, vintage film grain"),
    "8": ("Living Oil Painting", "living, breathing oil painting aesthetic, thick textured brushstrokes, vibrant colors, classical art style"),
    "9": ("Simple Line Drawing", "minimalist hand-drawn aesthetic, caricature style with simple distinct black lines drawn on a piece of textured white paper, with simple child-like shapes in the background")
}

def init_supabase() -> Client:
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("Error: Missing SUPABASE_URL or SUPABASE_KEY in .env")
        exit(1)
    return create_client(SUPABASE_URL, SUPABASE_KEY)

def init_gemini() -> genai.Client:
    if not GEMINI_API_KEY:
        print("Error: Missing GEMINI_API_KEY in .env")
        exit(1)
    return genai.Client(api_key=GEMINI_API_KEY)

def list_stories(supabase: Client):
    print("Fetching stories from database...")
    # Get stories, sorting by newest first
    response = supabase.table("stories").select("id, title, language, created_at").order("created_at", desc=True).limit(50).execute()
    stories = response.data
    
    if not stories:
        print("No stories found in the database.")
        exit(0)
        
    print("\n--- Available Stories ---")
    for i, s in enumerate(stories):
        print(f"[{i + 1}] {s['title']} (Lang: {s['language']}) - ID: {s['id']}")
    print("-------------------------\n")
    return stories

def get_story_details(supabase: Client, story_id: str):
    response = supabase.table("stories").select("*").eq("id", story_id).single().execute()
    return response.data

def generate_prompt(gemini_client, story_text, style_description):
    print("\nGenerating optimized Veo prompt via LLM...")
    system_instruction = f"You are an expert film director and cinematographer. Read the following story excerpt and write a highly detailed, 1-2 sentence visual prompt for an AI video generator. Describe setting, lighting, camera angle, and movement. Do not include dialogue. Ensure the style matches a {style_description}."
    
    response = gemini_client.models.generate_content(
        model='gemini-2.5-pro',
        contents=f"Story Excerpt:\n{story_text}\n\nWrite the visual prompt:",
        config=types.GenerateContentConfig(
            system_instruction=system_instruction,
            temperature=0.7
        )
    )
    prompt = response.text.strip()
    print(f"\n[Generated Prompt]:\n{prompt}\n")
    return prompt

def generate_veo_video(gemini_client, prompt, output_path):
    print(f"\nSubmitting to Veo API. Rendering may take a few minutes...")
    
    try:
        operation = gemini_client.models.generate_videos(
            model='veo-3.1-generate-preview',
            prompt=prompt,
            config=types.GenerateVideosConfig(
                aspect_ratio="16:9"
            )
        )
        
        # Block and wait for completion. In google.genai, operation usually has a result method or we check done
        print("Waiting for video generation", end="")
        while not operation.done:
            print(".", end="", flush=True)
            time.sleep(10)
            # Some SDK versions require re-fetching the operation status
            # If `operation.done` doesn't auto-update, you might need:
            # operation = gemini_client.models.get_operation(operation.name)
        
        print("\nGeneration finished.")
        
        if operation.error:
            print(f"API Error: {operation.error}")
            return False
            
        if operation.result and operation.result.generated_videos:
            video_bytes = operation.result.generated_videos[0].video.video_bytes
            with open(output_path, "wb") as f:
                f.write(video_bytes)
            print(f"Saved video locally to {output_path}")
            return True
        else:
            print("No video returned in the result.")
            return False
            
    except Exception as e:
        print(f"Failed to generate video: {e}")
        return False

def main():
    if not os.path.exists(VIDEO_DIR):
        os.makedirs(VIDEO_DIR)
        
    supabase = init_supabase()
    gemini_client = init_gemini()
    
    # 1. Select Story
    stories = list_stories(supabase)
    choice = input(f"Select a story number (1-{len(stories)}): ")
    try:
        selected_idx = int(choice) - 1
        selected_story = stories[selected_idx]
    except (ValueError, IndexError):
        print("Invalid selection.")
        exit(1)
        
    story_id = selected_story['id']
    full_story = get_story_details(supabase, story_id)
    story_text = full_story.get('target_text')
    if not story_text:
        print("Story text is empty!")
        exit(1)
        
    print(f"\nSelected Story: {selected_story['title']}")
    
    # 2. Select Style
    print("\n--- Visual Styles ---")
    for key, val in STYLES.items():
        print(f"[{key}] {val[0]}")
    style_choice = input("Select a visual style number: ")
    
    if style_choice not in STYLES:
        print("Invalid style choice.")
        exit(1)
        
    style_name, style_desc = STYLES[style_choice]
    print(f"Selected Style: {style_name}")
    
    # 3. Generate Prompt using LLM
    veo_prompt = generate_prompt(gemini_client, story_text, style_desc)
    
    # Save the prompt & style to database immediately
    try:
        supabase.table("stories").update({
            "video_prompt": veo_prompt,
            "video_style": style_name
        }).eq("id", story_id).execute()
        print("Saved generated prompt and style to the database.")
    except Exception as e:
        print(f"Warning: Failed to save prompt to database. Make sure you ran the schema migration! ({e})")
    
    # 4. Generate Video
    # Clean filename string
    safe_title = "".join([c if c.isalnum() else "_" for c in selected_story['title']]).strip("_").lower()
    filename = f"story_{safe_title}_{int(time.time())}.mp4"
    output_path = os.path.join(VIDEO_DIR, filename)
    
    proceed = input("\nProceed with video generation? This consumes API credits. (y/n): ")
    if proceed.lower() != 'y':
        print("Aborted.")
        exit(0)
        
    success = generate_veo_video(gemini_client, veo_prompt, output_path)
    
    # 5. Upload to Supabase Storage
    if success:
        upload_choice = input("\nUpload video to Supabase Storage ('story_videos' bucket)? (y/n): ")
        if upload_choice.lower() == 'y':
            try:
                print(f"Uploading {filename} to Supabase...")
                with open(output_path, 'rb') as f:
                    supabase.storage.from_("story_videos").upload(
                        file=f,
                        path=filename,
                        file_options={"content-type": "video/mp4", "x-upsert": "true"}
                    )
                
                # Get public URL
                public_url = supabase.storage.from_("story_videos").get_public_url(filename)
                
                # Update database record
                print("Updating database with video URL...")
                supabase.table("stories").update({
                    "video_url": public_url
                }).eq("id", story_id).execute()
                
                print("Upload and database update successful! 🎉")
            except Exception as e:
                print(f"Failed to upload or update database: {e}")

if __name__ == "__main__":
    main()
