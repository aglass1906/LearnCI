# Veo Video Generation Plan

This document outlines the plan for integrating Google's Veo video generation model to create video content for the stories in the application.

## 1. Overview of the API

Google's Veo models (like `veo-2.0-generate-exp` or the newer `veo-3.1-generate-preview`) are accessible programmatically. The recommended modern approach for developers is utilizing the new **Gemini API** via the `google-genai` Python SDK, which natively supports Veo. 

> [!NOTE] 
> **Native "App" Access vs. API Access:**
> You are correct that Google Gemini Advanced (the $20/mo "Pro" consumer subscription) allows you to generate Veo videos *natively* right in the Gemini chat interface. However, that subscription is for human-in-the-loop chat usage. If we want an iOS app or a background script to automatically generate videos *for* us on demand, we cannot use the consumer chat interface. We must use the **Developer API**, which is billed separately (pay-per-API-call) through Google Cloud Platform (GCP).

The API operates asynchronously: you submit a generation request, receive an Operation ID, and then poll the API until the video rendering is complete.

## 2. How the API Works (The Technical Flow)

Here is the step-by-step technical process for generating a video using Python:

1. **Authentication:** 
   You need a Google API key associated with a billing-enabled Google Cloud Project, as Veo models are a paid feature.
2. **Initialization:**
   Initialize the Gemini client using the `google.genai` library.
3. **Submission (`generate_videos`):**
   Send a request to the API containing:
   - **Model ID:** e.g., `models/veo-2.0-generate-exp`
   - **Prompt:** Your descriptive text.
   - **Optional Parameters:** Aspect ratio (e.g., "16:9", "9:16"), person generation filters, etc.
4. **Polling:**
   Because video generation takes time (sometimes several minutes), the API returns a long-running operation object. You must actively poll this operation (e.g., checking every 10 seconds) until its status changes to `SUCCEEDED`.
5. **Retrieval:**
   Once successful, the operation result contains the video bytes (or a URI) which you can decode and save as an `.mp4` file.

### Example Python Snippet Concept

```python
from google import genai
from google.genai import types
import time

# 1. Initialize Client
client = genai.Client(api_key="YOUR_API_KEY")

# 2. Submit the Prompt
operation = client.models.generate_videos(
    model='models/veo-2.0-generate-exp',
    prompt='Your detailed cinematic story prompt goes here.',
    config=types.GenerateVideosConfig(
        aspect_ratio="16:9",
        person_generation="ALLOW_ADULT" # Required if prompt features people
    )
)

# 3. Poll for Completion
while not operation.done:
    print("Waiting for video to generate...")
    time.sleep(10)
    operation.update() # Refreshes the status

# 4. Save the Video
if operation.result:
    video_bytes = operation.result.generated_videos[0].video.video_bytes
    with open("story_scene.mp4", "wb") as f:
        f.write(video_bytes)
```

## 3. How to Create a Prompt for Stories

Veo responds exceptionally well to detailed, cinematic prompts that define the visual aesthetic, camera movement, and subject action. 

For the existing stories, we should use a two-step LLM pipeline to create the Veo prompts:
1. **Context Extraction:** Parse a specific scene or paragraph from the story.
2. **Prompt Engineering:** Use an LLM (like Gemini 1.5 Pro) to translate that scene into a *cinematic video prompt*. 

### Veo Prompting Best Practices:
A high-quality Veo prompt generally follows this structure:
**[Subject Description] + [Action/Movement] + [Environment/Lighting] + [Camera Choice/Movement] + [Aesthetic/Style]**

**Example from a Spanish Story:**
*   **Story Text:** *"Había una vez un pequeño pueblo en las montañas. La nieve caía suavemente sobre los techos de madera."* (Once upon a time there was a small village in the mountains. Snow fell softly on the wooden roofs.)
*   **Bad Veo Prompt:** "A snowy village in the mountains."
*   **Good Veo Prompt:** "Cinematic establishing shot, slow drone pan over a quaint rustic village nestled in rugged mountains. Gentle, photorealistic snow is falling softly onto wooden cabin roofs. Warm glowing lights emanate from the windows. Taken on 35mm lens, golden hour lighting peaking through winter clouds, hyper-detailed, 4k cinematic grading."

### Strategy for Our Stories
To automate this, we can formulate a meta-prompt for an LLM to generate the Veo prompts:
> *"You are an expert film director and cinematographer. Read the following story excerpt and write a highly detailed, 1-2 sentence visual prompt for an AI video generator. Describe the setting, lighting, camera angle, and movement. Do not include dialogue or abstract concepts. Ensure the style matches a [insert desired style, e.g., Pixar 3D animation, photorealistic, 2D anime] aesthetic."*

## 4. Proposed Implementation Steps

### Phase 1: Pre-authored Stories (Backend Script)
1. **Setup Environment:** Install the modern `google-genai` SDK and secure API keys. Connect to your Supabase project using the official Python client.
2. **Database Schema Update:**
   - Run a database migration to add three new columns to the `stories` table: `video_style` (text), `video_prompt` (text), and `video_url` (text).
3. **Interactive Script & Prompt Generation:** Write an interactive backend script that:
   - Queries the Supabase `stories` table and lists all stories (along with their IDs) in the terminal.
   - Prompts the user to select a specific Story ID to generate a video for.
   - **Style Selection:** Prompts the user to select a visual style from a predefined list (e.g., [1] Pixar 3D, [2] Studio Ghibli 2D Anime, [3] Photorealistic Cinematic, [4] Tim Burton Stop-Motion).
   - Extracts the scene for the chosen story and uses an LLM (with the user's selected style injected into the meta-prompt) to generate the optimal Veo prompt.
   - **Save Prompt & Style:** Immediately saves the chosen `video_style` and the generated `video_prompt` back to the respective fields in the database record.
4. **Video Generation Script:** Using the saved `video_prompt`, call the Veo API, handle the polling/waiting logic, and download the `.mp4` file.
5. **Storage & Local Integration:** 
   - **Local Save:** Save the generated `.mp4` video locally to the `resources/video` folder in the project.
   - **Cloud Save:** Upload the generated video to a designated Supabase Storage bucket (e.g., `story_videos`).
   - Update the specific story record in the database with its new `video_url`.

### Phase 2: AI-Generated Stories (iOS App / Edge Function Integration)

For stories created by users dynamically within the iOS app, we need backend infrastructure to securely call the Google API without exposing your API keys in the app code. This is where **Supabase Edge Functions** come in.

#### What is an Edge Function?
An Edge Function is a piece of server-side code (written in TypeScript/Deno) hosted by Supabase. Instead of running a large, always-on server, these functions "spin up" instantly only when called. They are deployed globally to the "edge" (servers physically closer to the user) for fast execution.
- **Why use it here?** It allows your iOS app to say "Hey server, I have a new story, please start generating a video!" The Edge Function holds your secret Google API key, makes the request to Google, and manages the database updates securely.

#### How it Works in Our Workflow
1. **Triggering Generation:** The iOS app (or a database trigger) calls the Edge Function with the new story text.
2. **Edge Function Pipeline:** The Edge Function executes the exact logic from Phase 1:
   - Call Gemini to generate visual prompts.
   - Submit the Veo video generation request.
3. **Asynchronous Polling:** Because Edge Functions have execution time limits (you can't leave them running for 5 minutes waiting for Veo to finish) and Veo takes up to several minutes, the Edge Function will just **submit** the operation and save the `Operation ID` to a new Supabase table (e.g., `video_jobs`).
4. **Completion:** A scheduled cron job (another Edge Function set to run every 1 minute) will poll the `video_jobs` table, check the Google API for completion, download the finished video, upload it to Supabase Storage, and update the existing story table. The iOS app listens for this database update in real-time to show the video.

#### How to Make and Deploy an Edge Function
Supabase allows you to develop and deploy these via their CLI right from the terminal.

1. **Initialize the Function:**
   ```bash
   # From your project root, initialize a new function
   npx supabase functions new generate-veo-video
   ```
   This creates a folder: `supabase/functions/generate-veo-video/index.ts`.

2. **Write the Code:**
   You open `index.ts` and write the TypeScript code using the Gemini REST API or fetching the official libraries, ensuring you access your secrets securely via `Deno.env.get('GEMINI_API_KEY')`.

3. **Deploy the Function:**
   ```bash
   # Deploy it to your live Supabase project
   npx supabase functions deploy generate-veo-video
   
   # Set the secret key in the Supabase cloud environment
   npx supabase secrets set GEMINI_API_KEY=your_actual_api_key
   ```

4. **Call from iOS App:**
   In your Swift code, you simply call the function via the Supabase Swift library:
   ```swift
   try await supabase.functions.invoke("generate-veo-video", options: .init(body: ["story_text": myStoryText]))
   ```
