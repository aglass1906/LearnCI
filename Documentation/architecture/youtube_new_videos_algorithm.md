# YouTube "New Videos" Algorithm

The algorithm for showing the list of "New Videos" (your YouTube subscriptions) is primarily handled in `YouTubeManager.swift` using a multi-step API process. Because YouTube's API doesn't have a single "give me my feed" endpoint anymore, the app has to reconstruct it manually.

Here is the exact step-by-step process it follows when `loadVideosFromAPI()` is triggered:

1. **Authentication Check:** It first verifies you are securely logged in with a valid Google/YouTube Access Token.
2. **Fetch Subscriptions (`fetchSubscriptions`):** It queries the YouTube API to get the complete list of channels you are subscribed to, handling multiple pages of results if you have many subscriptions. This gives the app a list of `channelIds`.
3. **Find Upload Playlists (`fetchVideosFromChannels`):** For every subscribed channel, it asks YouTube's API: *"What is the special Playlist ID that holds all of this channel's uploaded videos?"* (It batches these requests in groups of 50 to respect API rate limits).
4. **Collect Video IDs:** Once it has the "Uploads" playlist ID for each channel, it scrapes the most recent video IDs from those playlists.
5. **Fetch Video Details (`fetchVideoDetails`):** It takes that giant list of recent video IDs, batches them in chunks of 50 again, and queries the API for the full metadata: the video title, thumbnail, description, duration, and exactly when it was published.
6. **Sort and Display:** Finally, it takes all of those fetched videos across all of your subscriptions, **sorts them chronologically** (newest `publishedAt` date first), and hands them to the User Interface to be displayed in your "New Videos" grid! 

*(It also attempts to cache these results locally, so if you open the app without internet access or an API failure occurs, it will fall back to your previously loaded cache!)*
